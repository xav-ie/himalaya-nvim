if vim.g.himalaya_loaded then
  return
end

local himalaya = require('himalaya')
himalaya.register_commands()
himalaya.register_filetypes()

vim.g.himalaya_loaded = true
