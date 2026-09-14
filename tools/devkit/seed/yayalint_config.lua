-- yayalint project configuration (used by tools/lint.ps1 and the yayalint VS Code extension).
-- yayalint loads this file from the folder that contains yaya.txt.
-- It extends yayalint's bundled defaults (such as the builtin function list) instead of replacing them.
-- Patterns are Lua patterns: https://www.lua.org/pil/20.2.html
-- Chain talk labels (':chain=name') are recognized by tools/lint.ps1, so they need not be listed here.

local config = require("yayalint_config")

local function add(list, patterns)
  for _, pattern in ipairs(patterns) do
    table.insert(list, pattern)
  end
end

-- Functions that SSP, the SHIORI framework or the template call by name,
-- so they look unused from inside the dictionaries.
add(config.func.used, {
  "^On",             -- SHIORI events and resources (OnBoot, On_username, ...)
  "^RandomTalk",     -- random talk entry points
  "^Menu_",          -- menu choice handlers
  "^Mouse",          -- MouseMove0Head etc. (AYATEMPLATE.MouseEventExec)
  "^TalkTo",         -- communicate handlers
  "^ReplyTo",        -- communicate handlers
  "^AYATEMPLATE%.",  -- template internals
  "^SHIORI3FW%.",    -- system dictionary framework
})

-- Files whose unused globals are not reported (paths relative to the folder of yaya.txt).
add(config.file.no_unused_global, {
  "^dic/system/",    -- yaya-dic git submodule; do not edit
})

return config
