local M = {}

function M.open_picker(callback)
  local account_state = require('himalaya.state.account')
  local context = require('himalaya.state.context')
  local pickers = require('himalaya.pickers')

  -- Capture account now, while we are on the listing buffer.
  -- list_async may fire its callback via vim.schedule, at which point
  -- the current-buffer context is no longer guaranteed.
  local current = context.resolve()

  -- When the initial listing was opened before warmup completed,
  -- himalaya_account may be empty.  Fall back to the CLI default
  -- so the rotation still works on the first picker invocation.
  if current == '' then
    current = account_state.default()
  end

  account_state.list_async(function(names)
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
