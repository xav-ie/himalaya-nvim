local config = require('himalaya.config')

local M = {}

local default_flags = { 'seen', 'answered', 'flagged', 'deleted', 'drafts' }

function M.complete_list()
  local cfg = config.get()
  local all = vim.list_extend(vim.deepcopy(default_flags), cfg.custom_flags)
  return all
end

function M.complete(arg_lead, cmd_line, cursor_pos)
  return table.concat(M.complete_list(), '\n')
end

return M
