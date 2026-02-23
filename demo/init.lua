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
  vim.api.nvim_echo({ { opts.args, 'Title' } }, false, {})
end, { nargs = 1 })
require('himalaya').setup({ mock = true })
