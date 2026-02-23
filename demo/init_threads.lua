vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrw = 1
local nvim_runtime = vim.env.VIMRUNTIME
vim.opt.runtimepath = { '.', nvim_runtime }
vim.opt.packpath = {}
vim.o.termguicolors = true
vim.o.number = false
vim.o.signcolumn = 'no'
vim.o.swapfile = false
require('himalaya').setup({ mock = true, thread_view = true })
