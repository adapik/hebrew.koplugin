# Hebrew Dictionary Support Plugin for KOReader

A KOReader plugin that improves Hebrew dictionary lookups by automatically stripping common attached prefixes before searching. This ensures that words written with prepositions or conjunctions fused to them are still found in the dictionary.

---

## The Problem

Hebrew words are frequently written with one or more prefixes attached directly to the root word — no space, no separator. For example:

| Written form | Prefix | Root |
|---|---|---|
| בַּבַּיִת | בּ (in) | בַּיִת (house) |
| לַמֶּלֶךְ | לְ (to/for) | מֶּלֶךְ (king) |
| וְהָאִישׁ | וְהָ (and the) | אִישׁ (man) |

When a reader selects *בַּבַּיִת*, a standard dictionary lookup fails because the dictionary entry is filed under the bare root. This plugin intercepts the lookup and tries the stripped forms as additional candidates.

---

## How It Works

1. The plugin registers itself with KOReader's `languagesupport` module via `languagesupport:registerPlugin`.
2. Before every dictionary lookup, `onWordLookup` is called with the selected text.
3. If the text contains at least one Hebrew character, `strip_prefixes` attempts to remove known prefixes (up to two layers deep, handling stacked combinations like **ובה → בה → root**).
4. All valid stripped candidates are returned to the dictionary module, which queries each one in turn.

---

## Supported Prefixes

The plugin handles single-letter prefixes and their common multi-letter combinations, tried longest-first to avoid over-stripping:

| Category | Prefixes |
|---|---|
| Single letters | ו, ב, ל, כ, מ, ש, ה |
| Two-letter (vav + X) | וה, וש, וב, ול, וכ, ומ |
| Two-letter (shin + X) | שה, שב, של, שמ, שכ |
| Two-letter (X + he-article) | בה, לה, כה, מה |
| Three-letter (vav + shin + X) | ושה, ושכ, ושמ, ושל, ושב |
| Three-letter (vav + X + he-article) | ובה, ולה, וכה, ומה |

Nikud (vowel points, U+05B0–U+05CF) in the selected text is handled transparently — the Hebrew-detection routine recognises diacriticised text correctly.

---

## Installation

1. Copy the plugin folder (`hebrew.koplugin/`) into KOReader's `plugins/` directory:

```
koreader/
└── plugins/
    └── hebrew.koplugin/
        ├── main.lua
        └── _meta.lua
```

2. Restart KOReader. The plugin is loaded automatically alongside the other plugins.

No configuration is required.

---

## Compatibility

| Requirement | Detail |
|---|---|
| KOReader API | `languagesupport.registerPlugin` / `onWordLookup` |
| Lua version | 5.1+ (no `bit` library or `utf8` module required) |
| Document language | Works for any document; prioritised when the document language is set to `he` or `iw` |

---

## File Structure

```
hebrew.koplugin/
├── main.lua      — Plugin logic: Hebrew detection, prefix stripping, API registration
└── _meta.lua     — Plugin metadata (name, full name, description)
```

---

## Contributing

- To add a missing prefix, append its literal UTF-8 byte sequence to the `PREFIXES` table in `main.lua`. Place longer combinations before shorter ones so they are tried first.
- The minimum candidate length after stripping is **4 bytes** (≈ 2 Hebrew characters). Adjust `MIN_BYTES` if needed.
- Debug output is written via `logger.dbg` and visible in KOReader's log when debug logging is enabled.

---

## License

This plugin follows the same license as KOReader itself (AGPL-3.0). See the main KOReader repository for details.
