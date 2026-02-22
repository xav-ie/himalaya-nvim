-- Prepend current directory to load local plugin source
vim.opt.runtimepath:prepend('.')

-- Enable coverage when LUACOV=1 (used by `make coverage`)
-- LuaJIT's JIT compiler skips debug hooks, so we disable it.
-- Neovim doesn't trigger luacov's atexit handler, so we flush via VimLeavePre.
if os.getenv('LUACOV') then
  jit.off()
  local runner = require('luacov.runner')
  runner.init()
  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function() runner.shutdown() end,
  })
end
