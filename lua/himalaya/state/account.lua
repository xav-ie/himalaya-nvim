local M = {}
local current_account = ''

function M.current()
  return current_account
end

function M.select(name)
  current_account = name
end

return M
