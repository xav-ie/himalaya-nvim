local renderer = require('himalaya.ui.renderer')
local perf = require('himalaya.perf')

local M = {}

--- Extract envelope from a thread display row.
local function get_env(row)
  return row.env
end

--- Render thread display rows into box-drawn display lines.
--- 5 columns: ID | FLAGS | SUBJECT | FROM | DATE
--- FLAGS column is present (empty) for visual consistency with flat listing.
--- Tree connector prefixes appear inside the SUBJECT column.
--- @param display_rows table[] Array of {env, depth, is_last_child, prefix, thread_idx}
--- @param total_width number
--- @param cfg? table  optional config (defaults to config.get())
--- @return table {header=string, separator=string, lines=string[]}
function M.render(display_rows, total_width, cfg)
  perf.start('thread_renderer.render')
  local layout = renderer.compute_layout(display_rows, total_width, get_env, cfg)
  local empty_flags = string.rep(' ', layout.flags_w)

  local format_from_fn = layout.narrow and renderer.format_from_initials or renderer.format_from
  local lines = {}
  for _, row in ipairs(display_rows) do
    local env = row.env

    -- Subject: prefix + truncated subject text within subject_w columns
    local prefix = row.prefix or ''
    local prefix_dw = (row.visual_depth or row.depth or 0) * 2

    local from = ''
    if env.from and env.from ~= vim.NIL then
      if env.from.name or env.from.addr then
        from = format_from_fn(env.from)
      elseif type(env.from) == 'table' and #env.from > 0 then
        from = format_from_fn(env.from[1])
      end
    end

    local date = renderer.format_date(env.date or '', cfg, layout.date_fmt)

    local line
    if layout.flags_compacted then
      local flags_str = env.flags and renderer.format_flags_compact(env, cfg) or ''
      local flags_dw = not flags_str:find('[\128-\255]') and #flags_str or vim.fn.strdisplaywidth(flags_str)
      local subject_space = layout.subject_w - flags_dw - prefix_dw
      local full_subject
      if subject_space <= 0 then
        full_subject = renderer.fit(flags_str .. prefix, layout.subject_w)
      else
        full_subject = flags_str .. prefix .. renderer.fit(env.subject or '', subject_space)
      end
      line = string.format(
        layout.row_fmt,
        renderer.fit(tostring(env.id or ''), layout.id_w),
        full_subject,
        renderer.fit(from, layout.from_w),
        renderer.fit(date, layout.date_w)
      )
    else
      local subject_space = layout.subject_w - prefix_dw
      local full_subject
      if subject_space <= 0 then
        full_subject = renderer.fit(prefix, layout.subject_w)
      else
        full_subject = prefix .. renderer.fit(env.subject or '', subject_space)
      end
      line = string.format(
        layout.row_fmt,
        renderer.fit(tostring(env.id or ''), layout.id_w),
        env.flags and renderer.format_flags(env, cfg) or empty_flags,
        full_subject,
        renderer.fit(from, layout.from_w),
        renderer.fit(date, layout.date_w)
      )
    end
    lines[#lines + 1] = line
  end

  perf.stop('thread_renderer.render')
  return { header = layout.header, separator = layout.separator, lines = lines, flags_compacted = layout.flags_compacted }
end

return M
