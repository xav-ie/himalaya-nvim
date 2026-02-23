local request = require('himalaya.request')
local account_state = require('himalaya.state.account')
local pickers = require('himalaya.pickers')
local log = require('himalaya.log')

local M = {}

local account_flag = account_state.flag

-- Folder list cache: keyed by account, expires after 60 seconds.
local folder_cache = {} -- { [account] = { data = ..., ts = ... } }
local CACHE_TTL = 60 -- seconds

local function rotate_folders(data, current)
  table.sort(data, function(a, b)
    return a.name < b.name
  end)
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
  for _, f in ipairs(rotated) do
    if f.name == current then
      f.name = f.name .. ' (current)'
      break
    end
  end
  return rotated
end

local function strip_current(name)
  return name:gsub(' %(current%)$', '')
end

function M.open_picker(callback)
  local context = require('himalaya.state.context')
  local account, current = context.resolve()

  -- Return cached folder list if fresh.
  local cached = folder_cache[account]
  local function pick(items)
    pickers.select(function(choice)
      callback(strip_current(choice))
    end, items)
  end

  if cached and (vim.uv.now() - cached.ts) < CACHE_TTL * 1000 then
    pick(rotate_folders(vim.deepcopy(cached.data), current))
    return
  end

  request.json({
    cmd = 'folder list %s',
    args = { account_flag(account) },
    msg = 'Listing folders',
    on_data = function(data)
      folder_cache[account] = { data = data, ts = vim.uv.now() }
      pick(rotate_folders(vim.deepcopy(data), current))
    end,
  })
end

function M.select()
  local in_thread = vim.b.himalaya_buffer_type == 'thread-listing'
  M.open_picker(function(folder)
    if in_thread then
      vim.b.himalaya_folder = folder
      vim.b.himalaya_page = 1
      require('himalaya.domain.email.thread_listing').list()
    else
      M.set(folder)
    end
  end)
end

function M.set(folder)
  vim.b.himalaya_folder = folder
  vim.b.himalaya_page = 1
  require('himalaya.events').emit('FolderChanged', {
    account = vim.b.himalaya_account or '',
    folder = folder,
  })
  require('himalaya.domain.email').list()
end

function M.select_next_page()
  local in_thread = vim.b.himalaya_buffer_type == 'thread-listing'
  if in_thread then
    require('himalaya.domain.email.thread_listing').next_page()
    return
  end
  local ps = vim.b.himalaya_page_size
  if not ps then
    return
  end
  -- Partial page means we're already on the last page.
  if vim.api.nvim_buf_line_count(0) < ps then
    log.warn('Already on last page')
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
      log.warn('Already on last page')
      return
    end
  end
  vim.b.himalaya_page = (vim.b.himalaya_page or 1) + 1
  require('himalaya.domain.email').list()
end

function M.select_previous_page()
  local in_thread = vim.b.himalaya_buffer_type == 'thread-listing'
  if in_thread then
    require('himalaya.domain.email.thread_listing').previous_page()
    return
  end
  if (vim.b.himalaya_page or 1) <= 1 then
    log.warn('Already on first page')
    return
  end
  vim.b.himalaya_page = math.max(1, (vim.b.himalaya_page or 1) - 1)
  require('himalaya.domain.email').list()
end

return M
