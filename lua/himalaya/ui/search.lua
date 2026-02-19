local M = {}

-- Field definitions: each field maps to a buffer line.
-- `keyword`  = the himalaya query keyword (nil for search/query meta-lines)
-- `quote`    = wrap value in double quotes (text patterns need it for multi-word)
-- `sep`      = place a virtual separator line below this field
local FIELDS = {
  { label = 'search: ' },
  { label = 'subject: ', keyword = 'subject', quote = true },
  { label = 'body: ',    keyword = 'body',    quote = true },
  { label = 'from: ',    keyword = 'from',    quote = true },
  { label = 'to: ',      keyword = 'to',      quote = true },
  { label = 'date: ',    keyword = 'date' },
  { label = 'before: ',  keyword = 'before' },
  { label = 'after: ',   keyword = 'after' },
  { label = 'flag: ',    keyword = 'flag',    sep = true },
  { label = 'query: ' },
}

local SEARCH_LINE = 0
local QUERY_LINE = #FIELDS - 1

--- Open the search popup. Calls callback(query_string) on submit.
--- @param callback fun(query: string)
function M.open(callback)
  local buf = vim.api.nvim_create_buf(false, true)
  local num_lines = #FIELDS

  -- Reactive state
  local subject_subscribed = true
  local body_subscribed = true
  local query_subscribed = true
  local propagating = false

  local ns = vim.api.nvim_create_namespace('himalaya_search')

  -- Set initial buffer lines (all empty)
  local init_lines = {}
  for _ = 1, num_lines do init_lines[#init_lines + 1] = '' end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, init_lines)

  -- Labels as inline virtual text
  for i, field in ipairs(FIELDS) do
    local opts = {
      virt_text = { { field.label, 'Comment' } },
      virt_text_pos = 'inline',
      right_gravity = false,
    }
    if field.sep then
      opts.virt_lines = { { { string.rep('\u{2500}', 56), 'FloatBorder' } } }
    end
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, opts)
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

  --- Recompose the query line from all filter fields.
  --- Text-search fields (subject, body) are OR-grouped together, then
  --- AND-combined with all other conditions.
  local function recompose_query()
    if not query_subscribed then return end
    -- Collect OR-group (subject, body) and AND-group (everything else)
    local or_parts = {}
    local and_parts = {}
    for i, field in ipairs(FIELDS) do
      if field.keyword then
        local val = get_line(i - 1)
        if val ~= '' then
          local cond = format_condition(field, val)
          if field.keyword == 'subject' or field.keyword == 'body' then
            or_parts[#or_parts + 1] = cond
          else
            and_parts[#and_parts + 1] = cond
          end
        end
      end
    end
    -- Build: (subject X or body Y) and from Z and to W ...
    local result = {}
    if #or_parts > 0 then
      local or_str = table.concat(or_parts, ' or ')
      -- Wrap in parens only when there are both OR-parts and AND-parts
      if #and_parts > 0 and #or_parts > 1 then
        or_str = '(' .. or_str .. ')'
      end
      result[#result + 1] = or_str
    end
    for _, part in ipairs(and_parts) do
      result[#result + 1] = part
    end
    propagating = true
    set_line(QUERY_LINE, table.concat(result, ' and '))
    propagating = false
  end

  -- Attach reactive listener.
  -- Buffer modifications are not allowed inside on_lines, so we defer
  -- all propagation with vim.schedule.
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, first_line)
      if propagating then return end
      if not vim.api.nvim_buf_is_valid(buf) then return true end

      if first_line == SEARCH_LINE then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          local search_val = get_line(SEARCH_LINE)
          propagating = true
          if subject_subscribed then set_line(1, search_val) end
          if body_subscribed then set_line(2, search_val) end
          propagating = false
          recompose_query()
        end)
      elseif first_line == QUERY_LINE then
        query_subscribed = false
      else
        -- Any filter field changed
        if first_line == 1 then subject_subscribed = false end
        if first_line == 2 then body_subscribed = false end
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
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

  vim.keymap.set({ 'n', 'i' }, '<Tab>', next_field, map_opts)
  vim.keymap.set({ 'n', 'i' }, '<S-Tab>', prev_field, map_opts)
  vim.keymap.set({ 'n', 'i' }, '<CR>', submit, map_opts)
  vim.keymap.set('n', '<Esc>', close, map_opts)

  -- Prevent <BS> at column 0 from joining lines
  vim.keymap.set('i', '<BS>', function()
    local col = vim.fn.col('.')
    if col <= 1 then return '' end
    return '<BS>'
  end, { buffer = buf, noremap = true, silent = true, expr = true })

  -- Start in insert mode on line 0
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd('startinsert')
end

return M
