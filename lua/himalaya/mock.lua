local config = require('himalaya.config')
local data = require('himalaya.mock.data')

local M = {}

local noop_handle = {
  kill = function() end,
  wait = function() end,
}

--- Build the full subcmd string from opts (same logic as request._build_cmd).
--- @param opts table
--- @return string
local function subcmd(opts)
  local args = opts.args or {}
  if #args > 0 then
    return string.format(opts.cmd, unpack(args))
  end
  return opts.cmd
end

--- Schedule on_data callback to preserve async behavior.
--- @param opts table
--- @param result any
local function deliver(opts, result)
  if opts.is_stale and opts.is_stale() then
    return
  end
  vim.schedule(function()
    if opts.is_stale and opts.is_stale() then
      return
    end
    if opts.on_data then
      opts.on_data(result)
    end
    vim.cmd('redraw')
  end)
end

--- Check whether mock mode is active.
--- @return boolean
function M.enabled()
  return config.get().mock == true
end

--- Check whether a single envelope matches a query string.
--- Supports: subject, body (→subject), from, to, flag, not flag.
--- Multiple terms are ANDed together. Unknown terms are ignored.
--- @param env table
--- @param query string
--- @return boolean
local function envelope_matches(env, query)
  if not query or query == '' then
    return true
  end
  local q = query:lower()
  -- Strip "order by ..." suffix
  q = q:gsub('%s*order%s+by%s+.*$', '')
  if q == '' then
    return true
  end

  local subj = (env.subject or ''):lower()
  local from_name = ((env.from or {}).name or ''):lower()
  local from_addr = ((env.from or {}).addr or ''):lower()

  -- Parse simple terms: "subject X", "from X", "flag X", "not flag X"
  -- Connected by "and" / "or" with parentheses stripped
  q = q:gsub('[()]', '')

  -- Split on " and " to get conjuncts
  local conjuncts = {}
  for part in (q .. ' and '):gmatch('(.-)%s+and%s+') do
    if part ~= '' then
      conjuncts[#conjuncts + 1] = part
    end
  end
  if #conjuncts == 0 then
    conjuncts = { q }
  end

  for _, conj in ipairs(conjuncts) do
    local matched = false
    -- Split on " or " to get disjuncts
    local disjuncts = {}
    for part in (conj .. ' or '):gmatch('(.-)%s+or%s+') do
      if part ~= '' then
        disjuncts[#disjuncts + 1] = part
      end
    end
    if #disjuncts == 0 then
      disjuncts = { conj }
    end

    for _, term in ipairs(disjuncts) do
      term = vim.trim(term)
      local field, value = term:match('^(%S+)%s+(.+)$')
      if field == 'subject' or field == 'body' then
        if subj:find(value, 1, true) then
          matched = true
        end
      elseif field == 'from' then
        if from_name:find(value, 1, true) or from_addr:find(value, 1, true) then
          matched = true
        end
      elseif field == 'to' then
        -- Mock envelopes don't have a to field; match against from as fallback
        if from_name:find(value, 1, true) or from_addr:find(value, 1, true) then
          matched = true
        end
      elseif field == 'not' then
        local flag_name = value:match('^flag%s+(%S+)')
        if flag_name then
          local has = false
          for _, f in ipairs(env.flags or {}) do
            if f:lower() == flag_name then
              has = true
            end
          end
          if not has then
            matched = true
          end
        end
      elseif field == 'flag' then
        for _, f in ipairs(env.flags or {}) do
          if f:lower() == value then
            matched = true
          end
        end
      else
        -- Bare word: match against subject
        if subj:find(term, 1, true) then
          matched = true
        end
      end
    end

    if not matched then
      return false
    end
  end
  return true
end

--- Mock replacement for request.json().
--- @param opts table  same shape as request.json opts
--- @return table handle  noop handle with kill/wait methods
function M.json(opts)
  local cmd = subcmd(opts)

  local result
  if cmd:match('^folder list') then
    result = data.folders()
  elseif cmd:match('^envelope thread') then
    local folder = cmd:match('--folder%s+(%S+)') or 'INBOX'
    result = data.thread_edges(folder)
  elseif cmd:match('^envelope list') then
    local folder = cmd:match('--folder%s+(%S+)') or 'INBOX'
    local page_size = tonumber(cmd:match('--page%-size%s+(%d+)')) or 25
    local page = tonumber(cmd:match('--page%s+(%d+)')) or 1
    -- Extract query: everything after "--page N "
    local query = cmd:match('--page%s+%d+%s+(.+)$') or ''
    local filter = nil
    if query ~= '' then
      filter = function(env)
        return envelope_matches(env, query)
      end
    end
    result = data.envelopes(folder, page_size, page, filter)
    -- Respect "order by <field> asc" — default is desc (newest first)
    if query:match('order%s+by%s+%S+%s+asc') then
      local reversed = {}
      for i = #result, 1, -1 do
        reversed[#reversed + 1] = result[i]
      end
      result = reversed
    end
  else
    result = {}
  end

  deliver(opts, result)
  return noop_handle
end

--- Mock replacement for request.plain().
--- @param opts table  same shape as request.plain opts
--- @return table handle  noop handle with kill/wait methods
function M.plain(opts)
  local cmd = subcmd(opts)

  local result
  if cmd:match('^message read') then
    local id = cmd:match('(%d+)%s*$')
    result = data.message_body(id)
  elseif cmd:match('^template forward') then
    local id = cmd:match('(%d+)%s*$')
    result = data.forward_template(id)
  elseif cmd:match('^template reply') then
    local id = cmd:match('(%d+)%s*$')
    result = data.reply_template(id)
  elseif cmd:match('^template write') then
    result = data.write_template()
  elseif cmd:match('^template send') then
    result = ''
  elseif cmd:match('^template save') then
    result = ''
  elseif cmd:match('^flag') then
    result = ''
  elseif cmd:match('^message delete') then
    result = ''
  elseif cmd:match('^message copy') then
    result = ''
  elseif cmd:match('^message move') then
    result = ''
  elseif cmd:match('^attachment download') then
    result = ''
  else
    result = ''
  end

  deliver(opts, result)
  return noop_handle
end

return M
