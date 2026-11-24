--[[
    Hebrew Dictionary Support Plugin for KOReader
    ===============================================
    Strips common Hebrew prefixes before dictionary lookup so that words
    written with attached prepositions (ב ל מ כ ש ה ו) are found.

    Based on the official LanguageSupport API (languagesupport.registerPlugin /
    onWordLookup), modelled after plugins/japanese.koplugin/main.lua.
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger          = require("logger")
local _               = require("gettext")

-- ── UTF-8 helpers (Lua 5.1 compatible, no `bit` needed for detection) ─────────

-- Returns the byte-length of the UTF-8 character starting at position i.
local function utf8len(s, i)
    local b = s:byte(i)
    if not b    then return 0 end
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

-- Returns true when s contains at least one Hebrew character.
-- Hebrew Unicode block U+05D0–U+05EA is encoded as:
--   U+05D0 = 0xD7 0x90  …  U+05EA = 0xD7 0xAA
-- Nikud (U+05B0–U+05CF):
--   U+05B0 = 0xD6 0xB0  …  U+05CF = 0xD7 0x8F
-- We detect by looking for the lead byte 0xD6 or 0xD7 followed by a
-- continuation byte in the correct range — no bitops required.
local function has_hebrew(s)
    local i = 1
    while i <= #s do
        local b1 = s:byte(i)
        if b1 == 0xD6 then
            local b2 = s:byte(i + 1) or 0
            if b2 >= 0xB0 and b2 <= 0xBF then return true end  -- U+05B0–U+05BF
        elseif b1 == 0xD7 then
            local b2 = s:byte(i + 1) or 0
            -- U+05C0–U+05CF: b2 0x80–0x8F   (nikud cont.)
            -- U+05D0–U+05EA: b2 0x90–0xAA   (letters)
            if b2 >= 0x80 and b2 <= 0xAA then return true end
        end
        local l = utf8len(s, i)
        if l == 0 then break end
        i = i + l
    end
    return false
end

-- ── Prefix table ──────────────────────────────────────────────────────────────
-- Literal UTF-8 byte sequences, longest first (so 3-letter combos are tried
-- before their constituent single letters).

local PREFIXES = {
    -- 3-letter (vav + shin + X)
    "\xD7\x95\xD7\xA9\xD7\x94", -- ושה
    "\xD7\x95\xD7\xA9\xD7\x9B", -- ושכ
    "\xD7\x95\xD7\xA9\xD7\x9E", -- ושמ
    "\xD7\x95\xD7\xA9\xD7\x9C", -- ושל
    "\xD7\x95\xD7\xA9\xD7\x91", -- ושב
    -- 3-letter (vav + X + he-article)
    "\xD7\x95\xD7\x91\xD7\x94", -- ובה
    "\xD7\x95\xD7\x9C\xD7\x94", -- ולה
    "\xD7\x95\xD7\x9B\xD7\x94", -- וכה
    "\xD7\x95\xD7\x9E\xD7\x94", -- ומה
    -- 2-letter (vav + X)
    "\xD7\x95\xD7\x94", -- וה
    "\xD7\x95\xD7\xA9", -- וש
    "\xD7\x95\xD7\x91", -- וב
    "\xD7\x95\xD7\x9C", -- ול
    "\xD7\x95\xD7\x9B", -- וכ
    "\xD7\x95\xD7\x9E", -- ומ
    -- 2-letter (shin + X)
    "\xD7\xA9\xD7\x94", -- שה
    "\xD7\xA9\xD7\x91", -- שב
    "\xD7\xA9\xD7\x9C", -- של
    "\xD7\xA9\xD7\x9E", -- שמ
    "\xD7\xA9\xD7\x9B", -- שכ
    -- 2-letter (X + he-article)
    "\xD7\x91\xD7\x94", -- בה
    "\xD7\x9C\xD7\x94", -- לה
    "\xD7\x9B\xD7\x94", -- כה
    "\xD7\x9E\xD7\x94", -- מה
    -- single letters
    "\xD7\x95", -- ו  vav
    "\xD7\x91", -- ב  bet
    "\xD7\x9C", -- ל  lamed
    "\xD7\x9B", -- כ  kaf
    "\xD7\x9E", -- מ  mem
    "\xD7\xA9", -- ש  shin
    "\xD7\x94", -- ה  he
}

-- Minimum byte-length a stripped candidate must have to be worth keeping.
-- 2 Hebrew chars = 4 bytes.  We use 4 as the floor.
local MIN_BYTES = 4

local function strip_prefixes(word)
    local seen = { [word] = true }
    local out  = {}

    local function add(w)
        if #w >= MIN_BYTES and not seen[w] then
            seen[w] = true
            out[#out + 1] = w
        end
    end

    for _, pre in ipairs(PREFIXES) do
        if word:sub(1, #pre) == pre then
            local s1 = word:sub(#pre + 1)
            add(s1)
            -- second-level strip (handles stacked prefixes like ובה → בה → root)
            for _, pre2 in ipairs(PREFIXES) do
                if s1:sub(1, #pre2) == pre2 then
                    add(s1:sub(#pre2 + 1))
                end
            end
        end
    end

    return #out > 0 and out or nil
end

-- ── Plugin ────────────────────────────────────────────────────────────────────

local HebrewPlugin = WidgetContainer:extend{
    name     = "hebrew",
    -- Language code used by languagesupport to prioritise this plugin when
    -- the document language is "he" or "iw".  For all other documents it is
    -- still called as a fallback whenever the selected text contains Hebrew.
    language = "he",
}

function HebrewPlugin:init()
    -- Plugins are instantiated during ReaderUI:init() before the modules
    -- (languagesupport, dictionary, …) are registered on self.ui.
    -- We must therefore defer registration to after ReaderUI:init() finishes.
    -- The correct pattern (used by readerrolling.lua and others) is to
    -- insert directly into self.ui.postInitCallback.
    table.insert(self.ui.postInitCallback, function()
        if self.ui.languagesupport then
            self.ui.languagesupport:registerPlugin(self)
            logger.dbg("hebrew.koplugin: registered with languagesupport")
        else
            logger.warn("hebrew.koplugin: languagesupport module not available")
        end
    end)
end

--- Checks whether a given BCP 47 / ISO language code represents Hebrew.
-- Called by `languageSupport._findAndCallPlugin`.
-- @param language_code string Language tag (e.g., `"he"`, `"iw"`, `"heb"`, `"he-IL"`).
-- @return boolean `true` if the primary subtag is `"he"`, `"iw"` (legacy ISO 639-1),
--                 or `"heb"` (ISO 639-2/3), including regional/script variants
--                 (e.g., `"he-IL"`, `"he_IL"`); `false` otherwise.
function HebrewPlugin:supportsLanguage(language_code)
    if type(language_code) ~= "string" then return false end
    local base = language_code:lower():match("^(%a+)")
    return base == "he" or base == "iw" or base == "heb"
end

-- Called by languagesupport.extraDictionaryFormCandidates before every lookup.
-- @param args  table with field `text` (string)
-- @return      array of candidate strings, or nil
function HebrewPlugin:onWordLookup(args)
    local text = args and args.text
    if not text or not has_hebrew(text) then return nil end

    local candidates = strip_prefixes(text)
    if candidates then
        logger.dbg("hebrew.koplugin:", text, "->", table.concat(candidates, " / "))
    end
    return candidates
end

return HebrewPlugin
