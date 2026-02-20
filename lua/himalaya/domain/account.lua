local M = {}

function M.open_picker(callback)
  local account_state = require('himalaya.state.account')
  local pickers = require('himalaya.pickers')
  local names = account_state.list()
  local current = account_state.current()

  -- Rotate so the account after the current one is first.
  -- ga<Enter> cycles to the next account.
  local start = 1
  for i, name in ipairs(names) do
    if name == current then
      start = i + 1
      break
    end
  end

  local items = {}
  for i = 0, #names - 1 do
    local idx = ((start - 1 + i) % #names) + 1
    items[#items + 1] = { name = names[idx] }
  end

  pickers.select(callback, items)
end

function M.select()
  local in_thread = vim.b.himalaya_buffer_type == 'thread-listing'
  M.open_picker(function(name)
    if in_thread then
      require('himalaya.state.account').select(name)
      require('himalaya.domain.email.thread_listing').list()
    else
      require('himalaya.domain.email').list(name)
    end
  end)
end

return M
