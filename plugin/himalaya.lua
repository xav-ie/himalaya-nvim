if vim.g.himalaya_loaded then
  return
end

local himalaya = require('himalaya')
himalaya._register_commands()
himalaya._register_filetypes()

vim.g.himalaya_loaded = true
