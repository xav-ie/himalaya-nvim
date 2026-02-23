-- Reset runtimepath to only include Neovim runtime and this plugin,
-- avoiding system plugins (cmp, telescope, etc.) that would error.
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrw = 1
local nvim_runtime = vim.env.VIMRUNTIME
vim.opt.runtimepath = { '.', nvim_runtime }
vim.opt.packpath = {}
vim.o.termguicolors = true
vim.o.number = false
vim.o.signcolumn = 'no'
vim.o.swapfile = false
vim.api.nvim_create_user_command('Msg', function(opts)
  local chunks = {}
  local text = opts.args
  local i = 1
  while i <= #text do
    local s, e = text:find('<[^>]+>', i)
    if s then
      if s > i then
        table.insert(chunks, { text:sub(i, s - 1), 'Title' })
      end
      table.insert(chunks, { text:sub(s + 1, e - 1), 'Special' })
      i = e + 1
    else
      table.insert(chunks, { text:sub(i), 'Title' })
      break
    end
  end
  vim.api.nvim_echo(chunks, false, {})
end, { nargs = 1 })
require('himalaya').setup({ mock = true })
