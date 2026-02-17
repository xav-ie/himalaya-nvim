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
  for _, entry in ipairs(entries) do
    if entry.name then
      table.insert(names, entry.name)
    end
  end

  cached_accounts = names
  return cached_accounts
end

return M
