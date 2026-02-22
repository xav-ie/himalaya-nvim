local config = require('himalaya.config')
local job = require('himalaya.job')

local M = {}
local current_account = ''
local cached_accounts = nil
local cache_ts = 0
local CACHE_TTL = 120 -- seconds
local refresh_in_flight = false

function M.current()
  return current_account
end

function M.select(name)
  current_account = name
end

local function build_cmd()
  local cfg = config.get()
  local cmd = { cfg.executable, '--output', 'json', 'account', 'list' }
  if cfg.config_path then
    table.insert(cmd, 2, '--config')
    table.insert(cmd, 3, cfg.config_path)
  end
  return cmd
end

local function parse_result(stdout, code)
  if code ~= 0 then
    return nil
  end
  local ok, entries = pcall(vim.json.decode, stdout)
  if not ok or type(entries) ~= 'table' then
    return nil
  end
  local names = {}
  local default_name = nil
  for _, entry in ipairs(entries) do
    if entry.name then
      names[#names + 1] = entry.name
      if entry.default then
        default_name = entry.name
      end
    end
  end
  table.sort(names)
  return names, default_name
end

local function refresh(callback)
  if refresh_in_flight then
    return
  end
  refresh_in_flight = true
  job.run(build_cmd(), {
    on_exit = function(stdout, _stderr, code)
      refresh_in_flight = false
      local names, default_name = parse_result(stdout, code)
      if names then
        cached_accounts = names
        cache_ts = vim.uv.now()
        if current_account == '' and default_name then
          current_account = default_name
        end
      end
      if callback then
        callback(cached_accounts or {})
      end
    end,
  })
end

function M.list()
  if cached_accounts and (vim.uv.now() - cache_ts) < CACHE_TTL * 1000 then
    return cached_accounts
  end
  refresh()
  return cached_accounts or {}
end

function M.list_async(callback)
  if cached_accounts and (vim.uv.now() - cache_ts) < CACHE_TTL * 1000 then
    callback(cached_accounts)
    return
  end
  refresh(callback)
end

function M.warmup()
  if not cached_accounts then
    refresh()
  end
end

--- Return '--account <name>' when account is set, or '' to let CLI use its default.
--- @param account string
--- @return string
function M.flag(account)
  if account == '' then
    return ''
  end
  return '--account ' .. account
end

return M
