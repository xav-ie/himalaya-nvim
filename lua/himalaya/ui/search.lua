local M = {}

--- Open the search popup. Calls callback(query_string) on submit.
--- @param callback fun(query: string)
function M.open(callback)
  local buf = vim.api.nvim_create_buf(false, true)

  -- Reactive state
  local subject_subscribed = true
  local body_subscribed = true
  local query_subscribed = true
  local propagating = false

  local ns = vim.api.nvim_create_namespace('himalaya_search')

  -- Set initial buffer lines (5 fields, all empty)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', '', '', '', '' })

  -- Labels as inline virtual text
  local labels = { 'search: ', 'subject: ', 'body: ', 'from: ', 'query: ' }
  for i, label in ipairs(labels) do
    local opts = {
      virt_text = { { label, 'Comment' } },
      virt_text_pos = 'inline',
    }
    -- Add separator line below "from" field (line 3)
    if i == 4 then
      local sep_width = 56
      opts.virt_lines = { { { string.rep('\u{2500}', sep_width), 'FloatBorder' } } }
    end
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, opts)
  end

  -- Open floating window
  local width = 60
  local height = 6
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
  --- @param line_idx number
  --- @return string
  local function get_line(line_idx)
    return vim.api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)[1] or ''
  end

  --- Set a single buffer line by 0-based index.
  --- @param line_idx number
  --- @param text string
  local function set_line(line_idx, text)
    vim.api.nvim_buf_set_lines(buf, line_idx, line_idx + 1, false, { text })
  end

  --- Recompose the query line from subject/body/from fields.
  local function recompose_query()
    if not query_subscribed then return end
    local parts = {}
    local subject = get_line(1)
    local body = get_line(2)
    local from = get_line(3)
    if subject ~= '' then parts[#parts + 1] = 'subject ' .. subject end
    if body ~= '' then parts[#parts + 1] = 'body ' .. body end
    if from ~= '' then parts[#parts + 1] = 'from ' .. from end
    propagating = true
    set_line(4, table.concat(parts, ' or '))
    propagating = false
  end

  -- Attach reactive listener.
  -- Buffer modifications are not allowed inside on_lines, so we defer
  -- all propagation with vim.schedule.
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, first_line)
      if propagating then return end
      if not vim.api.nvim_buf_is_valid(buf) then return true end

      if first_line == 0 then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          local search_val = get_line(0)
          propagating = true
          if subject_subscribed then set_line(1, search_val) end
          if body_subscribed then set_line(2, search_val) end
          propagating = false
          recompose_query()
        end)
      elseif first_line == 1 then
        subject_subscribed = false
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          recompose_query()
        end)
      elseif first_line == 2 then
        body_subscribed = false
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          recompose_query()
        end)
      elseif first_line == 3 then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          recompose_query()
        end)
      elseif first_line == 4 then
        query_subscribed = false
      end
    end,
  })

  --- Close the popup window and clean up.
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  --- Submit the query.
  local function submit()
    local final_query = get_line(4)
    close()
    callback(final_query)
  end

  --- Move to the next field line, wrapping around.
  local function next_field()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local next_row = (row % 5) + 1
    vim.api.nvim_win_set_cursor(win, { next_row, 0 })
    vim.cmd('startinsert!')
  end

  --- Move to the previous field line, wrapping around.
  local function prev_field()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local prev_row = ((row - 2) % 5) + 1
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
