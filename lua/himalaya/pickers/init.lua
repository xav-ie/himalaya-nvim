local config = require('himalaya.config')

local M = {}

function M.detect()
  local cfg = config.get()
  if cfg.folder_picker then
    return cfg.folder_picker
  end

  if pcall(require, 'telescope') then
    return 'telescope'
  elseif pcall(require, 'fzf-lua') then
    return 'fzflua'
  elseif vim.fn.exists('*fzf#run') == 1 then
    return 'fzf'
  else
    return 'native'
  end
end

function M.select(callback, folders)
  local picker_name = M.detect()
  local picker = require('himalaya.pickers.' .. picker_name)
  picker.select(callback, folders)
end

return M
