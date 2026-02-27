local config = require('himalaya.config')
local perf = require('himalaya.perf')

local M = {}

local FLAG_ORDER = { 'flagged', 'unseen', 'answered', 'attachment' }
M.FLAG_ORDER = FLAG_ORDER

--- Map JSON flags array + has_attachment to compact symbols.
--- @param envelope table
--- @param cfg? table  optional config (defaults to config.get())
--- @return string
function M.format_flags(envelope, cfg)
  local cfg_flags = (cfg or config.get()).flags
  local raw = envelope.flags or {}
  local seen, answered, flagged = false, false, false

  for _, f in ipairs(raw) do
    if f == 'Seen' then
      seen = true
    end
    if f == 'Answered' then
      answered = true
    end
    if f == 'Flagged' then
      flagged = true
    end
  end

  local active = {
    flagged = flagged,
    unseen = not seen,
    answered = answered,
    attachment = envelope.has_attachment and true or false,
  }

  local parts = {}
  for _, key in ipairs(FLAG_ORDER) do
    local sym = cfg_flags[key]
    if type(sym) == 'string' then
      if active[key] then
        parts[#parts + 1] = sym
      else
        parts[#parts + 1] = string.rep(' ', vim.fn.strdisplaywidth(sym))
      end
    end
  end
  return table.concat(parts)
end

--- Prefer `.name`, fall back to `.addr`.
--- @param from table|nil
--- @return string
function M.format_from(from)
  if not from then
    return ''
  end
  if from.name and from.name ~= vim.NIL and from.name ~= '' then
    return from.name
  end
  if from.addr and from.addr ~= vim.NIL and from.addr ~= '' then
    return from.addr
  end
  return ''
end

--- Extract uppercase initials (max 2) from sender name, or first char of addr.
--- @param from table|nil
--- @return string
function M.format_from_initials(from)
  if not from then
    return ''
  end
  local name = from.name
  if name and name ~= vim.NIL and name ~= '' then
    local initials = ''
    for word in name:gmatch('%S+') do
      local first = word:sub(1, 1)
      if first:match('%a') then
        initials = initials .. first:upper()
      end
    end
    if initials ~= '' then
      return initials:sub(1, 2)
    end
  end
  local addr = from.addr
  if addr and addr ~= vim.NIL and addr ~= '' then
    return addr:sub(1, 1)
  end
  return ''
end

--- Format a date string using the configured format.
--- Parses ISO-ish dates from himalaya (e.g. "2026-02-17 13:18+00:00")
--- and reformats using strftime-style tokens. Converts to local time.
--- Returns the raw string when no date_format is configured.
--- @param raw string
--- @param cfg? table  optional config (defaults to config.get())
--- @return string
function M.format_date(raw, cfg)
  perf.count('format_date')
  local fmt = (cfg or config.get()).date_format
  if not fmt or raw == '' then
    return raw
  end
  local tree = require('himalaya.domain.email.tree')
  local utc_epoch = tree.date_to_epoch(raw)
  if utc_epoch == 0 then
    return raw
  end
  return os.date(fmt, utc_epoch)
end

--- Pad or truncate a string to exactly `width` display columns.
--- Uses a pure-Lua fast path for ASCII strings (no vim.fn overhead).
--- Falls back to vim.fn.strdisplaywidth/strcharpart for multi-byte.
--- Truncated strings get a trailing `~`.
--- @param s string
--- @param width number
--- @return string
function M.fit(s, width)
  if width <= 0 then
    return ''
  end
  s = tostring(s)
  perf.count('fit')

  -- ASCII fast path: byte length == display width, pure Lua ops only.
  if not s:find('[\128-\255]') then
    local len = #s
    if len == width then
      return s
    elseif len < width then
      return s .. string.rep(' ', width - len)
    else
      return s:sub(1, width - 1) .. '~'
    end
  end

  -- Multi-byte path: use vim.fn for correct display-width handling.
  local dw = vim.fn.strdisplaywidth(s)
  perf.count('strdisplaywidth')
  if dw == width then
    return s
  elseif dw < width then
    return s .. string.rep(' ', width - dw)
  else
    -- Binary search for the longest character prefix that fits in (width - 1) columns.
    local nchars = vim.fn.strchars(s)
    local lo, hi, best = 0, nchars - 1, 0
    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      local subdw = vim.fn.strdisplaywidth(tostring(vim.fn.strcharpart(s, 0, mid)))
      if subdw <= width - 1 then
        best = mid
        lo = mid + 1
      else
        hi = mid - 1
      end
    end
    local sub = tostring(vim.fn.strcharpart(s, 0, best)) .. '~'
    local finaldw = vim.fn.strdisplaywidth(sub)
    if finaldw < width then
      sub = sub .. string.rep(' ', width - finaldw)
    end
    return sub
  end
end

-- Box-drawing characters (hex-escaped for tokenizer safety)
local BOX_V = '\xe2\x94\x82' -- │
local BOX_H = '\xe2\x94\x80' -- ─
local BOX_CROSS = '\xe2\x94\xbc' -- ┼
M.BOX_V = BOX_V
M.BOX_H = BOX_H
M.BOX_CROSS = BOX_CROSS

--- Compute column widths, row format, header, and separator for the 5-column layout.
--- @param items table[] input array (envelopes or display_rows)
--- @param total_width number available display width
--- @param get_env_fn function(item): envelope  extracts envelope from each item
--- @param cfg? table  optional config (defaults to config.get())
--- @return table { id_w, flags_w, date_w, subject_w, from_w, row_fmt, header, separator }
function M.compute_layout(items, total_width, get_env_fn, cfg)
  cfg = cfg or config.get()
  local cfg_flags = cfg.flags
  local id_w = 2 -- minimum: fits "ID" header
  for _, item in ipairs(items) do
    local env = get_env_fn(item)
    local len = #tostring(env.id or '')
    if len > id_w then
      id_w = len
    end
  end
  local num_slots = 0
  local flags_w = 0
  for _, key in ipairs(FLAG_ORDER) do
    local sym = cfg_flags[key]
    if type(sym) == 'string' then
      flags_w = flags_w + vim.fn.strdisplaywidth(sym)
      num_slots = num_slots + 1
    end
  end
  local date_w = 4 -- minimum: fits "DATE" header
  -- format_date with a fixed strftime format produces constant-width output,
  -- so formatting one sample is sufficient instead of formatting all N dates.
  for _, item in ipairs(items) do
    local env = get_env_fn(item)
    local raw = tostring(env.date or '')
    if raw ~= '' then
      local len = #M.format_date(raw, cfg)
      if len > date_w then
        date_w = len
      end
      break
    end
  end
  local gutters = cfg.gutters
  -- With gutters:    " col │ col │ col │ col │ col" → 1 + 4×3 = 13
  -- Without gutters: "col│col│col│col│col"          → 4×1 = 4
  local overhead = gutters and 13 or 4
  local fixed = id_w + flags_w + date_w
  local remaining = total_width - fixed - overhead
  if remaining < 2 then
    remaining = 2
  end

  local subject_w = math.floor(remaining * 0.6)
  local from_w = remaining - subject_w

  local narrow = false
  local NARROW_FROM_W = 2
  local NARROW_THRESHOLD = 12
  if from_w < NARROW_THRESHOLD then
    narrow = true
    subject_w = subject_w + from_w - NARROW_FROM_W
    from_w = NARROW_FROM_W
  end

  local col_sep = gutters and (' ' .. BOX_V .. ' ') or BOX_V
  local leading = gutters and ' ' or ''
  local row_fmt = leading .. '%s' .. col_sep .. '%s' .. col_sep .. '%s' .. col_sep .. '%s' .. col_sep .. '%s'

  local from_label = narrow and 'FR' or 'FROM'
  local header = string.format(
    row_fmt,
    M.fit('ID', id_w),
    M.fit(cfg_flags.header or 'FLGS', flags_w),
    M.fit('SUBJECT', subject_w),
    M.fit(from_label, from_w),
    M.fit('DATE', date_w)
  )

  -- Horizontal separator under header
  local cross_sep = gutters and (BOX_H .. BOX_CROSS .. BOX_H) or BOX_CROSS
  local leading_h = gutters and string.rep(BOX_H, 1 + id_w) or string.rep(BOX_H, id_w)
  local separator = leading_h
    .. cross_sep
    .. string.rep(BOX_H, flags_w)
    .. cross_sep
    .. string.rep(BOX_H, subject_w)
    .. cross_sep
    .. string.rep(BOX_H, from_w)
    .. cross_sep
    .. string.rep(BOX_H, date_w)

  return {
    id_w = id_w,
    flags_w = flags_w,
    date_w = date_w,
    subject_w = subject_w,
    from_w = from_w,
    narrow = narrow,
    row_fmt = row_fmt,
    header = header,
    separator = separator,
  }
end

--- Identity envelope extractor for flat listing.
local function env_identity(item)
  return item
end

--- Render envelopes into box-drawn display lines.
--- Returns { header = string, separator = string, lines = string[] }
--- Fixed widths: ID=6, FLAGS=6|8, DATE=19
--- Remaining space split 60/40 between SUBJECT and FROM
--- @param envelopes table[]
--- @param total_width number
--- @param cfg? table  optional config (defaults to config.get())
--- @return table
function M.render(envelopes, total_width, cfg)
  perf.start('renderer.render')
  cfg = cfg or config.get()
  local layout = M.compute_layout(envelopes, total_width, env_identity, cfg)

  local format_from_fn = layout.narrow and M.format_from_initials or M.format_from
  local lines = {}
  for _, env in ipairs(envelopes) do
    local id = tostring(env.id or '')
    local flags = M.format_flags(env, cfg)
    local subject = env.subject or ''
    local from = ''
    if env.from and env.from ~= vim.NIL then
      if env.from.name or env.from.addr then
        from = format_from_fn(env.from)
      elseif type(env.from) == 'table' and #env.from > 0 then
        from = format_from_fn(env.from[1])
      end
    end
    local date = M.format_date(env.date or '', cfg)

    local line = string.format(
      layout.row_fmt,
      M.fit(id, layout.id_w),
      M.fit(flags, layout.flags_w),
      M.fit(subject, layout.subject_w),
      M.fit(from, layout.from_w),
      M.fit(date, layout.date_w)
    )
    table.insert(lines, line)
  end

  perf.stop('renderer.render')
  return { header = layout.header, separator = layout.separator, lines = lines }
end

return M
