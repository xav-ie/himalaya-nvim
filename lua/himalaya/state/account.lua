local config = require('himalaya.config')

local M = {}
local current_account = ''
local cached_accounts = nil

function M.current()
  return current_account
end

function M.select(name)
  current_account = name
end

function M.list()
  if cached_accounts then
    return cached_accounts
  end

  local cfg = config.get()
  local cmd = { cfg.executable, '--output', 'json', 'account', 'list' }
  if cfg.config_path then
    table.insert(cmd, 2, '--config')
    table.insert(cmd, 3, cfg.config_path)
  end

  local result = vim.system(cmd):wait()
  if result.code ~= 0 then
    return {}
  end

  local ok, entries = pcall(vim.json.decode, result.stdout)
  if not ok or type(entries) ~= 'table' then
    return {}
  end

  local names = {}
  local default_name = nil
  for _, entry in ipairs(entries) do
    if entry.name then
      table.insert(names, entry.name)
      if entry.default then
        default_name = entry.name
      end
    end
  end
  table.sort(names)

  if current_account == '' and default_name then
    current_account = default_name
  end

  cached_accounts = names
  return cached_accounts
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
