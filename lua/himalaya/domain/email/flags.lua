local config = require('himalaya.config')

local M = {}

local default_flags = { 'Seen', 'Answered', 'Flagged', 'Deleted', 'Draft' }

function M.complete_list()
  local cfg = config.get()
  local all = vim.list_extend(vim.deepcopy(default_flags), cfg.custom_flags)
  return all
end

--- Check whether an envelope is confirmed unseen (has flags but no Seen flag).
--- Returns false when flags are nil (unknown state ≠ unseen).
--- @param env table
--- @return boolean
function M.is_unseen(env)
  local flags = env.flags
  if not flags then
    return false
  end
  for _, f in ipairs(flags) do
    if f == 'Seen' then
      return false
    end
  end
  return true
end

--- Check whether an envelope has the Seen flag.
--- @param env table
--- @return boolean
function M.is_seen(env)
  return not M.is_unseen(env)
end

--- Count unseen envelopes in a flat list.
--- @param envelopes table[]
--- @return number
function M.count_unseen(envelopes)
  local n = 0
  for _, env in ipairs(envelopes) do
    if M.is_unseen(env) then
      n = n + 1
    end
  end
  return n
end

--- Count unseen envelopes in a list of display rows (where each row has an .env field).
--- @param rows table[]
--- @return number
function M.count_unseen_rows(rows)
  local n = 0
  for _, row in ipairs(rows) do
    if M.is_unseen(row.env) then
      n = n + 1
    end
  end
  return n
end

return M
