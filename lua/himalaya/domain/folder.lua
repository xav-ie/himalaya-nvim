local request = require('himalaya.request')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local pickers = require('himalaya.pickers')

local M = {}

function M.open_picker(callback)
  local account = account_state.current()
  request.json({
    cmd = 'folder list --account %s',
    args = { account },
    msg = 'Listing folders',
    on_data = function(data)
      pickers.select(callback, data)
    end,
  })
end

function M.select()
  M.open_picker(M.set)
end

function M.set(folder)
  folder_state.set(folder)
  -- Bridge to VimScript until email domain is migrated (Task 17)
  vim.fn['himalaya#domain#email#list']()
end

function M.select_next_page()
  folder_state.next_page()
  vim.fn['himalaya#domain#email#list']()
end

function M.select_previous_page()
  folder_state.previous_page()
  vim.fn['himalaya#domain#email#list']()
end

return M
