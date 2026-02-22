local M = {}

function M.open_picker(callback)
  local account_state = require('himalaya.state.account')
  local context = require('himalaya.state.context')
  local pickers = require('himalaya.pickers')

  account_state.list_async(function(names)
    local current = context.resolve()

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

    for _, item in ipairs(items) do
      if item.name == current then
        item.name = item.name .. ' (current)'
        break
      end
    end

    pickers.select(function(choice)
      callback(choice:gsub(' %(current%)$', ''))
    end, items)
  end)
end

function M.select()
  local in_thread = vim.b.himalaya_buffer_type == 'thread-listing'
  M.open_picker(function(name)
    if in_thread then
      require('himalaya.domain.email.thread_listing').list(name)
    else
      require('himalaya.domain.email').list(name)
    end
  end)
end

return M
