local M = {}

function M.open_picker(callback)
  local account_state = require('himalaya.state.account')
  local pickers = require('himalaya.pickers')
  local names = account_state.list()
  local items = {}
  for _, name in ipairs(names) do
    table.insert(items, { name = name })
  end
  pickers.select(callback, items)
end

function M.select()
  M.open_picker(function(name)
    require('himalaya.domain.email').list(name)
  end)
end

return M
