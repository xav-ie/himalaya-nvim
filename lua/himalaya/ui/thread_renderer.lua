local renderer = require('himalaya.ui.renderer')

local M = {}

--- Extract envelope from a thread display row.
local function get_env(row) return row.env end

--- Render thread display rows into box-drawn display lines.
--- 5 columns: ID | FLAGS | SUBJECT | FROM | DATE
--- FLAGS column is present (empty) for visual consistency with flat listing.
--- Tree connector prefixes appear inside the SUBJECT column.
--- @param display_rows table[] Array of {env, depth, is_last_child, prefix, thread_idx}
--- @param total_width number
--- @return table {header=string, separator=string, lines=string[]}
function M.render(display_rows, total_width)
  local layout = renderer.compute_layout(display_rows, total_width, get_env)
  local empty_flags = string.rep(' ', layout.flags_w)

  local lines = {}
  for _, row in ipairs(display_rows) do
    local env = row.env

    -- Subject: prefix + truncated subject text within subject_w columns
    local prefix = row.prefix or ''
    local prefix_dw = vim.fn.strdisplaywidth(prefix)
    local subject_space = layout.subject_w - prefix_dw
    local full_subject
    if subject_space <= 0 then
      full_subject = renderer.fit(prefix, layout.subject_w)
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

    local line = string.format(layout.row_fmt,
      renderer.fit(tostring(env.id or ''), layout.id_w),
      env.flags and renderer.format_flags(env) or empty_flags,
      full_subject,
      renderer.fit(from, layout.from_w),
      renderer.fit(date, layout.date_w))
    lines[#lines + 1] = line
  end

  return { header = layout.header, separator = layout.separator, lines = lines }
end

return M
