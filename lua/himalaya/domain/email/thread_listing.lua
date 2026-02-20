local request = require('himalaya.request')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local tree = require('himalaya.domain.email.tree')

local M = {}

-- Module-local state
local all_display_rows = nil   -- full tree from last fetch
local thread_query = ''        -- search query for thread mode
local current_page = 1

--- Return '--account <name>' when account is set, or '' to let CLI use its default.
--- @param account string
--- @return string
local function account_flag(account)
  if account == '' then return '' end
  return '--account ' .. account
end

--- Render one page of the cached thread display rows into the current buffer.
--- @param page number
--- @param opts? table  Optional: { restore_cursor = {line, col} }
function M.render_page(page, opts)
  if not all_display_rows then return end
  opts = opts or {}

  local email = require('himalaya.domain.email')
  local thread_renderer = require('himalaya.ui.thread_renderer')
  local listing = require('himalaya.ui.listing')

  local ps = math.max(1, vim.fn.winheight(0))
  -- On first load the winbar hasn't been set yet, so winheight still
  -- includes that row.  Reserve one line for the header winbar.
  if vim.wo.winbar == '' then
    ps = math.max(1, ps - 1)
  end

  local total_pages = math.max(1, math.ceil(#all_display_rows / ps))
  page = math.max(1, math.min(page, total_pages))
  current_page = page

  local start_idx = (page - 1) * ps + 1
  local end_idx = math.min(#all_display_rows, start_idx + ps - 1)
  local slice = {}
  for i = start_idx, end_idx do
    slice[#slice + 1] = all_display_rows[i]
  end

  local folder = folder_state.current()
  local display_query = thread_query == '' and 'all' or thread_query
  local buftype = vim.b.himalaya_buffer_type == 'thread-listing' and 'file' or 'edit'
  vim.cmd(string.format('silent! %s Himalaya/threads [%s] [%s] [page %d⁄%d]',
    buftype, folder, display_query, page, total_pages))
  vim.bo.modifiable = true

  local bufnr = vim.api.nvim_get_current_buf()
  local result = thread_renderer.render(slice, email._bufwidth())
  -- Set winbar first so page_size reflects actual visible area
  listing.apply_header(bufnr, result.header)

  -- After winbar is set, visible area may have shrunk — truncate if needed
  local actual_ps = math.max(1, vim.fn.winheight(0))
  if #slice > actual_ps then
    local trimmed = {}
    for i = 1, actual_ps do trimmed[i] = result.lines[i] end
    result.lines = trimmed
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)

  -- Apply seen highlights from enriched flag data
  local envs = {}
  for _, row in ipairs(slice) do envs[#envs + 1] = row.env end
  listing.apply_seen_highlights(bufnr, envs)

  vim.b.himalaya_buffer_type = 'thread-listing'
  vim.bo.filetype = 'himalaya-thread-listing'
  vim.bo.modified = false

  -- Cursor positioning: restore_cursor preserves selection across
  -- resize/enrich re-renders; default goes to first line.
  vim.fn.winrestview({ topline = 1 })
  if opts.restore_cursor then
    local lnum = math.min(opts.restore_cursor[1], vim.api.nvim_buf_line_count(bufnr))
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, opts.restore_cursor[2] or 0 })
  else
    vim.cmd('0')
  end
end

--- Enrich display rows with flags from a secondary envelope list fetch.
--- Renders immediately, then re-renders when flag data arrives.
--- @param acct string
--- @param folder string
local function enrich_with_flags(acct, folder)
  if not all_display_rows or #all_display_rows == 0 then return end

  request.json({
    cmd = 'envelope list --folder %s %s --page-size %d --page 1',
    args = { folder, account_flag(acct), #all_display_rows },
    msg = 'Fetching flags',
    silent = true,
    on_data = function(envs)
      local id_map = {}
      for _, env in ipairs(envs) do
        id_map[tostring(env.id)] = env
      end
      for _, row in ipairs(all_display_rows) do
        local rich = id_map[tostring(row.env.id)]
        if rich then
          row.env.flags = rich.flags
          row.env.has_attachment = rich.has_attachment
        end
      end
      M.render_page(current_page, { restore_cursor = vim.api.nvim_win_get_cursor(0) })
    end,
  })
end

--- Fetch threads and render the first page.
--- @param account? string
function M.list(account)
  if account then
    account_state.select(account)
  end
  local acct = account_state.current()
  local folder = folder_state.current()

  request.json({
    cmd = 'envelope thread --folder %s %s %s',
    args = { folder, account_flag(acct), thread_query },
    msg = string.format('Fetching %s threads', folder),
    on_data = function(data)
      local rows = tree.build(data)
      tree.build_prefix(rows)
      all_display_rows = rows
      M.render_page(1)
      enrich_with_flags(acct, folder)
    end,
  })
end

--- Navigate to the next page of threads.
function M.next_page()
  if not all_display_rows then return end
  M.render_page(current_page + 1)
end

--- Navigate to the previous page of threads.
function M.previous_page()
  if not all_display_rows then return end
  M.render_page(math.max(1, current_page - 1))
end

--- Read the email under cursor.
function M.read()
  require('himalaya.domain.email').read()
end

--- Switch back to flat listing mode, preserving folder/account context.
function M.toggle_to_flat()
  require('himalaya.domain.email').list()
end

--- Open search popup and re-fetch threads with the resulting query.
function M.set_thread_query()
  local search = require('himalaya.ui.search')
  search.open(function(final_query, folder)
    thread_query = final_query
    if folder and folder ~= '' then
      folder_state.set(folder)
    end
    M.list()
  end, thread_query, folder_state.current())
end

--- Re-render the current page (used for resize handling).
--- Preserves cursor position so the selected email stays highlighted.
function M.resize()
  if not all_display_rows then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  M.render_page(current_page, { restore_cursor = cursor })
end

--- Test-only accessor to set module-local state.
function M._set_state(rows, page)
  all_display_rows = rows
  current_page = page
end

return M
