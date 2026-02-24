local config = require('himalaya.config')

local M = {}

local default_flags = { 'Seen', 'Answered', 'Flagged', 'Deleted', 'Draft' }

function M.complete_list()
  local cfg = config.get()
  local all = vim.list_extend(vim.deepcopy(default_flags), cfg.custom_flags)
  return all
end

return M
