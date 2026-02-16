vim.opt.runtimepath:append('.')

local plenary_path = vim.fn.stdpath('data') .. '/site/pack/test/start/plenary.nvim'
if vim.fn.isdirectory(plenary_path) == 0 then
  vim.fn.system({
    'git', 'clone', '--depth', '1',
    'https://github.com/nvim-lua/plenary.nvim',
    plenary_path,
  })
end
vim.opt.runtimepath:append(plenary_path)
