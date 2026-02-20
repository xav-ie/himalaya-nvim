local request = require('himalaya.request')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local pickers = require('himalaya.pickers')

local M = {}

--- Return '--account <name>' when account is set, or '' to let CLI use its default.
local function account_flag(account)
  if account == '' then
    return ''
  end
  return '--account ' .. account
end

function M.open_picker(callback)
  local account = account_state.current()
  request.json({
    cmd = 'folder list %s',
    args = { account_flag(account) },
    msg = 'Listing folders',
    on_data = function(data)
      -- Sort folders alphabetically for deterministic order
      table.sort(data, function(a, b) return a.name < b.name end)

      -- Rotate so the folder after the current one is first
      local current = folder_state.current()
      local start = 1
      for i, f in ipairs(data) do
        if f.name == current then
          start = i + 1
          break
        end
      end
      local rotated = {}
      for i = 0, #data - 1 do
        local idx = ((start - 1 + i) % #data) + 1
        rotated[#rotated + 1] = data[idx]
      end

      pickers.select(callback, rotated)
    end,
  })
end

function M.select()
  M.open_picker(M.set)
end

function M.set(folder)
  folder_state.set(folder)
  require('himalaya.domain.email').list()
end

function M.select_next_page()
  local ps = vim.b.himalaya_page_size
  if not ps then return end
  -- Partial page means we're already on the last page.
  if vim.api.nvim_buf_line_count(0) < ps then
    return
  end
  -- When the probe knows the exact total, prevent going past the last page
  -- even if the current page happened to be exactly full.
  local page = vim.b.himalaya_page or 1
  local cache_key = vim.b.himalaya_cache_key
  if cache_key then
    local probe = require('himalaya.domain.email.probe')
    local total = probe.total_count(cache_key)
    if total and page >= math.ceil(total / ps) then
      return
    end
  end
  folder_state.next_page()
  require('himalaya.domain.email').list()
end

function M.select_previous_page()
  folder_state.previous_page()
  require('himalaya.domain.email').list()
end

return M
