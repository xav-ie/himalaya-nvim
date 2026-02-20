local config = require('himalaya.config')
local renderer = require('himalaya.ui.renderer')

local M = {}

local FLAG_ORDER = { 'flagged', 'unseen', 'answered', 'attachment' }

-- Box-drawing characters (hex-escaped for tokenizer safety)
local BOX_V = "\xe2\x94\x82" -- │
local BOX_H = "\xe2\x94\x80" -- ─
local BOX_CROSS = "\xe2\x94\xbc" -- ┼

--- Render thread display rows into box-drawn display lines.
--- 5 columns: ID │ FLAGS │ SUBJECT │ FROM │ DATE
--- FLAGS column is present (empty) for visual consistency with flat listing.
--- Tree connector prefixes appear inside the SUBJECT column.
--- @param display_rows table[] Array of {env, depth, is_last_child, prefix, thread_idx}
--- @param total_width number
--- @return table {header=string, separator=string, lines=string[]}
function M.render(display_rows, total_width)
  local gutters = config.get().gutters
  local cfg_flags = config.get().flags

  local id_w = 2 -- minimum: fits "ID" header
  for _, row in ipairs(display_rows) do
    local len = #tostring(row.env.id or '')
    if len > id_w then id_w = len end
  end

  local num_slots = 0
  for _, key in ipairs(FLAG_ORDER) do
    if type(cfg_flags[key]) == 'string' then num_slots = num_slots + 1 end
  end
  local flags_w = num_slots * 2

  local date_w = 4 -- minimum: fits "DATE" header
  for _, row in ipairs(display_rows) do
    local len = #renderer.format_date(tostring(row.env.date or ''))
    if len > date_w then date_w = len end
  end

  -- 5 columns → 4 separators
  -- With gutters:    " col │ col │ col │ col │ col" → 1 + 4×3 = 13
  -- Without gutters: "col│col│col│col│col"           → 4×1 = 4
  local overhead = gutters and 13 or 4
  local fixed = id_w + flags_w + date_w
  local remaining = total_width - fixed - overhead
  if remaining < 2 then remaining = 2 end

  local subject_w = math.floor(remaining * 0.6)
  local from_w = remaining - subject_w

  local col_sep = gutters and (' ' .. BOX_V .. ' ') or BOX_V
  local leading = gutters and ' ' or ''
  local row_fmt = leading .. '%s' .. col_sep .. '%s' .. col_sep .. '%s' .. col_sep .. '%s' .. col_sep .. '%s'

  local empty_flags = string.rep(' ', flags_w)

  local header = string.format(row_fmt,
    renderer.fit('ID', id_w),
    renderer.fit(cfg_flags.header or 'FLGS', flags_w),
    renderer.fit('SUBJECT', subject_w),
    renderer.fit('FROM', from_w),
    renderer.fit('DATE', date_w))

  -- Horizontal separator under header
  local cross_sep = gutters and (BOX_H .. BOX_CROSS .. BOX_H) or BOX_CROSS
  local leading_h = gutters and string.rep(BOX_H, 1 + id_w) or string.rep(BOX_H, id_w)
  local separator = leading_h
    .. cross_sep .. string.rep(BOX_H, flags_w)
    .. cross_sep .. string.rep(BOX_H, subject_w)
    .. cross_sep .. string.rep(BOX_H, from_w)
    .. cross_sep .. string.rep(BOX_H, date_w)

  local lines = {}
  for _, row in ipairs(display_rows) do
    local env = row.env

    -- Subject: prefix + truncated subject text within subject_w columns
    local prefix = row.prefix or ''
    local prefix_dw = vim.fn.strdisplaywidth(prefix)
    local subject_space = subject_w - prefix_dw
    local full_subject
    if subject_space <= 0 then
      full_subject = renderer.fit(prefix, subject_w)
    else
      full_subject = prefix .. renderer.fit(env.subject or '', subject_space)
    end

    local from = ''
    if env.from and env.from ~= vim.NIL then
      if env.from.name or env.from.addr then
        from = renderer.format_from(env.from)
      elseif type(env.from) == 'table' and #env.from > 0 then
        from = renderer.format_from(env.from[1])
      end
    end

    local date = renderer.format_date(env.date or '')

    local line = string.format(row_fmt,
      renderer.fit(tostring(env.id or ''), id_w),
      empty_flags,
      full_subject,
      renderer.fit(from, from_w),
      renderer.fit(date, date_w))
    lines[#lines + 1] = line
  end

  return { header = header, separator = separator, lines = lines }
end

return M
