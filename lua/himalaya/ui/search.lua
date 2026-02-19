local M = {}

-- Date helpers for when-presets
local function today_str(offset_days)
  return os.date('%Y-%m-%d', os.time() + offset_days * 86400)
end

-- Returns the Monday of the current ISO week
local function week_start()
  local t = os.time()
  local d = os.date('*t', t)
  local wday = (d.wday + 5) % 7  -- Mon=0 .. Sun=6
  return os.date('%Y-%m-%d', t - wday * 86400)
end

local WHEN_PRESETS = {
  { label = 'today',         resolve = function() return 'date ' .. today_str(0) end },
  { label = 'yesterday',     resolve = function() return 'date ' .. today_str(-1) end },
  { label = 'past 3 days',   resolve = function() return 'after ' .. today_str(-3) end },
  { label = 'past week',     resolve = function() return 'after ' .. today_str(-7) end },
  { label = 'past 2 weeks',  resolve = function() return 'after ' .. today_str(-14) end },
  { label = 'past month',    resolve = function() return 'after ' .. today_str(-30) end },
  { label = 'past 3 months', resolve = function() return 'after ' .. today_str(-90) end },
  { label = 'this week',     resolve = function() return 'after ' .. week_start() end },
  { label = 'this month',    resolve = function() return 'after ' .. os.date('%Y-%m') .. '-01' end },
  { label = 'this year',     resolve = function() return 'after ' .. os.date('%Y') .. '-01-01' end },
}

-- Per-field highlight sources for query coloring and linked labels
local FIELD_HL = {
  subject = 'DiagnosticInfo',
  body    = 'String',
  from    = 'DiagnosticWarn',
  to      = 'Special',
  when    = 'Type',
  flag    = 'DiagnosticError',
}

-- Field definitions: each field maps to a buffer line.
-- `keyword`  = the himalaya query keyword (nil for the query meta-line)
-- `quote`    = wrap value in double quotes (text patterns need it for multi-word)
-- `sep`      = place a virtual separator line below this field
-- `complete` = 'flag' | 'when' — enables Tab-completion on this line
local FIELDS = {
  { label = 'subject: ', keyword = 'subject', quote = true },
  { label = '   body: ', keyword = 'body',    quote = true },
  { label = '   from: ', keyword = 'from',    quote = true },
  { label = '     to: ', keyword = 'to',      quote = true },
  { label = '   when: ', complete = 'when' },
  { label = '   flag: ', keyword = 'flag',    sep = true, complete = 'flag' },
  { label = '  query: ' },
}

local FLAG_LINE, WHEN_LINE
for i, f in ipairs(FIELDS) do
  if f.complete == 'flag' then FLAG_LINE = i - 1 end
  if f.complete == 'when' then WHEN_LINE = i - 1 end
end

local SUBJECT_LINE = 0
local BODY_LINE = 1
local QUERY_LINE = #FIELDS - 1

--- Open the search popup. Calls callback(query_string) on submit.
--- @param callback fun(query: string)
function M.open(callback)
  local buf = vim.api.nvim_create_buf(false, true)
  local num_lines = #FIELDS

  -- Reactive state
  local body_subscribed = true
  local query_subscribed = true
  local propagating = false

  local ns = vim.api.nvim_create_namespace('himalaya_search')

  -- Per-field linked value highlights (field color + underline for content)
  local linked_value_hl = {}
  for kw, source in pairs(FIELD_HL) do
    local name = 'HimalayaSearch' .. kw:sub(1, 1):upper() .. kw:sub(2) .. 'Linked'
    local attrs = vim.api.nvim_get_hl(0, { name = source, link = false })
    attrs.underline = true
    vim.api.nvim_set_hl(0, name, attrs)
    linked_value_hl[kw] = name
  end

  -- Namespace for underline highlights on linked field values
  local value_hl_ns = vim.api.nvim_create_namespace('himalaya_search_value_hl')
  -- Namespace for per-field coloring on the query line
  local query_hl_ns = vim.api.nvim_create_namespace('himalaya_search_query_hl')

  local label_marks = {}

  local function set_label(line_idx, field)
    local opts = {
      virt_text = { { field.label, 'Comment' } },
      virt_text_pos = 'inline',
      right_gravity = false,
    }
    if field.sep then
      opts.virt_lines = { { { string.rep('\u{2500}', 56), 'FloatBorder' } } }
    end
    if label_marks[line_idx] then
      opts.id = label_marks[line_idx]
    end
    label_marks[line_idx] = vim.api.nvim_buf_set_extmark(buf, ns, line_idx, 0, opts)
  end

  local function restore_labels()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for k in pairs(label_marks) do label_marks[k] = nil end
    for i, field in ipairs(FIELDS) do
      set_label(i - 1, field)
    end
  end

  -- Set initial buffer lines (all empty)
  local init_lines = {}
  for _ = 1, num_lines do init_lines[#init_lines + 1] = '' end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, init_lines)

  -- Labels as inline virtual text
  for i, field in ipairs(FIELDS) do
    set_label(i - 1, field)
  end

  -- Open floating window
  local width = 60
  local height = num_lines + 1 -- +1 for the virtual separator line
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Search ',
    title_pos = 'center',
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  -- Completion: build candidate lists for flag and when lines.
  local flag_candidates = require('himalaya.domain.email.flags').complete_list()

  local when_candidates = {}
  for _, p in ipairs(WHEN_PRESETS) do
    when_candidates[#when_candidates + 1] = {
      word = p.resolve(),
      menu = p.label,
    }
  end

  vim.api.nvim_buf_set_var(buf, '_himalaya_flag_candidates', flag_candidates)
  vim.api.nvim_buf_set_var(buf, '_himalaya_when_candidates', when_candidates)
  vim.api.nvim_buf_set_var(buf, '_himalaya_flag_line', FLAG_LINE)
  vim.api.nvim_buf_set_var(buf, '_himalaya_when_line', WHEN_LINE)
  vim.bo[buf].completefunc = 'v:lua._himalaya_search_completefunc'
  -- Global completefunc wrapper (scoped to this buffer via buf-local var).
  if not _G._himalaya_search_completefunc then
    function _G._himalaya_search_completefunc(findstart, base)
      local b = vim.api.nvim_get_current_buf()
      local row = vim.fn.line('.') - 1 -- 0-based

      local ok_fl, fl = pcall(vim.api.nvim_buf_get_var, b, '_himalaya_flag_line')
      local ok_wl, wl = pcall(vim.api.nvim_buf_get_var, b, '_himalaya_when_line')

      if ok_wl and row == wl then
        -- When-line completion
        local ok, candidates = pcall(vim.api.nvim_buf_get_var, b, '_himalaya_when_candidates')
        if not ok then return findstart == 1 and -3 or {} end
        if findstart == 1 then return 0 end
        local matches = {}
        for _, c in ipairs(candidates) do
          if c.word:lower():find(base:lower(), 1, true) == 1 then
            matches[#matches + 1] = c
          end
        end
        return matches
      elseif ok_fl and row == fl then
        -- Flag-line completion
        local ok, candidates = pcall(vim.api.nvim_buf_get_var, b, '_himalaya_flag_candidates')
        if not ok then return findstart == 1 and -3 or {} end
        if findstart == 1 then return 0 end
        local matches = {}
        for _, flag in ipairs(candidates) do
          if flag:lower():find(base:lower(), 1, true) == 1 then
            matches[#matches + 1] = flag
          end
        end
        return matches
      end

      return findstart == 1 and -3 or {}
    end
  end

  --- Read a single buffer line by 0-based index.
  local function get_line(line_idx)
    return vim.api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)[1] or ''
  end

  --- Set a single buffer line by 0-based index (preserves extmarks).
  local function set_line(line_idx, text)
    local old = get_line(line_idx)
    vim.api.nvim_buf_set_text(buf, line_idx, 0, line_idx, #old, { text })
  end

  --- Format a single field condition for the query string.
  --- Text-pattern fields escape spaces with backslash for multi-word support.
  local function format_condition(field, val)
    if field.quote then
      return field.keyword .. ' ' .. val:gsub(' ', '\\ ')
    end
    return field.keyword .. ' ' .. val
  end

  --- Update underline highlights on linked field values.
  local function update_value_hl()
    vim.api.nvim_buf_clear_namespace(buf, value_hl_ns, 0, -1)
    if body_subscribed then
      local len = #get_line(BODY_LINE)
      if len > 0 then
        vim.api.nvim_buf_set_extmark(buf, value_hl_ns, BODY_LINE, 0, {
          end_col = len, hl_group = linked_value_hl.body,
        })
      end
    end
  end

  --- Recompose the query line from all filter fields.
  --- Text-search fields (subject, body) are OR-grouped together, then
  --- AND-combined with all other conditions. Each field's contribution
  --- is colored with its field highlight on the query line.
  local function recompose_query()
    if not query_subscribed then return end
    local or_segs = {}
    local and_segs = {}
    for i, field in ipairs(FIELDS) do
      if field.complete == 'when' then
        local val = get_line(i - 1)
        if val ~= '' then
          and_segs[#and_segs + 1] = { text = val, hl = FIELD_HL.when }
        end
      elseif field.keyword then
        local val = get_line(i - 1)
        if val ~= '' then
          local cond = format_condition(field, val)
          local hl = FIELD_HL[field.keyword]
          if field.keyword == 'subject' or field.keyword == 'body' then
            or_segs[#or_segs + 1] = { text = cond, hl = hl }
          else
            and_segs[#and_segs + 1] = { text = cond, hl = hl }
          end
        end
      end
    end
    -- Build segments with separators
    local segments = {}
    if #or_segs > 0 then
      local need_parens = #and_segs > 0 and #or_segs > 1
      if need_parens then segments[#segments + 1] = { text = '(' } end
      for j, seg in ipairs(or_segs) do
        if j > 1 then segments[#segments + 1] = { text = ' or ' } end
        segments[#segments + 1] = seg
      end
      if need_parens then segments[#segments + 1] = { text = ')' } end
    end
    for _, seg in ipairs(and_segs) do
      if #segments > 0 then segments[#segments + 1] = { text = ' and ' } end
      segments[#segments + 1] = seg
    end
    -- Build final string and track highlight positions
    local texts = {}
    local hl_ranges = {}
    local pos = 0
    for _, seg in ipairs(segments) do
      texts[#texts + 1] = seg.text
      if seg.hl then
        hl_ranges[#hl_ranges + 1] = { pos, pos + #seg.text, seg.hl }
      end
      pos = pos + #seg.text
    end
    propagating = true
    set_line(QUERY_LINE, table.concat(texts))
    -- Apply per-field coloring on the query line
    vim.api.nvim_buf_clear_namespace(buf, query_hl_ns, QUERY_LINE, QUERY_LINE + 1)
    for _, r in ipairs(hl_ranges) do
      vim.api.nvim_buf_set_extmark(buf, query_hl_ns, QUERY_LINE, r[1], {
        end_col = r[2], hl_group = r[3],
      })
    end
    propagating = false
  end

  -- Per-line generation counters to prevent vim.schedule race conditions.
  -- Each on_lines increments the counter; stale scheduled callbacks skip.
  local edit_gen = {}

  -- Attach reactive listener.
  -- Buffer modifications are not allowed inside on_lines, so we defer
  -- all propagation with vim.schedule.
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, first_line, lastline, new_lastline)
      if propagating then return end
      if not vim.api.nvim_buf_is_valid(buf) then return true end

      -- Undo any line additions/deletions to preserve buffer structure
      if lastline ~= new_lastline then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          propagating = true
          vim.cmd('silent! undo')
          propagating = false
          restore_labels()
          update_value_hl()
          recompose_query()
        end)
        return
      end

      if first_line == SUBJECT_LINE then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          local subject_val = get_line(SUBJECT_LINE)
          propagating = true
          if body_subscribed then set_line(BODY_LINE, subject_val) end
          propagating = false
          query_subscribed = true
          update_value_hl()
          recompose_query()
        end)
      elseif first_line == QUERY_LINE then
        edit_gen[QUERY_LINE] = (edit_gen[QUERY_LINE] or 0) + 1
        local gen = edit_gen[QUERY_LINE]
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          if edit_gen[QUERY_LINE] ~= gen then return end
          local val = get_line(QUERY_LINE)
          if val == '' and not query_subscribed then
            query_subscribed = true
            recompose_query()
          elseif query_subscribed then
            query_subscribed = false
            vim.api.nvim_buf_clear_namespace(buf, query_hl_ns, QUERY_LINE, QUERY_LINE + 1)
          end
        end)
      else
        edit_gen[first_line] = (edit_gen[first_line] or 0) + 1
        local gen = edit_gen[first_line]
        local fl = first_line
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          if edit_gen[fl] ~= gen then return end
          -- Re-link body when cleared
          if fl == BODY_LINE then
            local val = get_line(BODY_LINE)
            if val == '' and not body_subscribed then
              body_subscribed = true
              local subject_val = get_line(SUBJECT_LINE)
              if subject_val ~= '' then
                propagating = true
                set_line(BODY_LINE, subject_val)
                propagating = false
              end
            elseif body_subscribed then
              body_subscribed = false
            end
          end
          query_subscribed = true
          update_value_hl()
          recompose_query()
        end)
      end
    end,
  })

  --- Close the popup window and clean up.
  local function close()
    vim.cmd('stopinsert')
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  --- Submit the query.
  local function submit()
    local final_query = get_line(QUERY_LINE)
    close()
    callback(final_query)
  end

  --- Move to the next field line, wrapping around.
  local function next_field()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local next_row = (row % num_lines) + 1
    vim.api.nvim_win_set_cursor(win, { next_row, 0 })
    vim.cmd('startinsert!')
  end

  --- Move to the previous field line, wrapping around.
  local function prev_field()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local prev_row = ((row - 2) % num_lines) + 1
    vim.api.nvim_win_set_cursor(win, { prev_row, 0 })
    vim.cmd('startinsert!')
  end

  -- Buffer-local keymaps
  local map_opts = { buffer = buf, noremap = true, silent = true }

  -- <Tab>: on completable lines trigger completion, otherwise navigate fields.
  local complete_lines = {}
  for i, f in ipairs(FIELDS) do
    if f.complete then complete_lines[i - 1] = true end
  end
  vim.keymap.set({ 'n', 'i' }, '<Tab>', function()
    local row = vim.api.nvim_win_get_cursor(win)[1] - 1 -- 0-based
    if complete_lines[row] then
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes('<C-x><C-u>', true, false, true),
        'n', false)
    else
      next_field()
    end
  end, map_opts)
  vim.keymap.set({ 'n', 'i' }, '<S-Tab>', prev_field, map_opts)
  vim.keymap.set({ 'n', 'i' }, '<CR>', submit, map_opts)
  vim.keymap.set('n', '<Esc>', close, map_opts)

  -- Prevent <BS> at column 0 from joining lines
  vim.keymap.set('i', '<BS>', function()
    local col = vim.fn.col('.')
    if col <= 1 then return '' end
    return '<BS>'
  end, { buffer = buf, noremap = true, silent = true, expr = true })

  -- Map dd to clear line content instead of deleting the line
  vim.keymap.set('n', 'dd', '0D', map_opts)

  -- Map visual d/x to clear selected lines' content instead of deleting them.
  -- Each set_line triggers on_lines → vim.schedule, which handles re-link logic.
  for _, key in ipairs({ 'd', 'x' }) do
    vim.keymap.set('x', key, function()
      local sl = vim.fn.line("'<") - 1
      local el = vim.fn.line("'>") - 1
      for l = sl, el do set_line(l, '') end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end, map_opts)
  end

  -- Start in insert mode on line 0
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd('startinsert')
end

return M
