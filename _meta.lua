local _ = require("gettext")
return {
    name = "hebrew",
    fullname = _("Hebrew Dictionary Support"),
    description = _([[Improves Hebrew dictionary lookups by stripping common prefixes (ב, ל, מ, כ, ש, ה, ו and their combinations) before searching. This helps find words written with prepositions attached.]]),
}
