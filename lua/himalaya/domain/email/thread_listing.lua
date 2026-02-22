local request = require('himalaya.request')
local config = require('himalaya.config')
local account_state = require('himalaya.state.account')
local tree = require('himalaya.domain.email.tree')
local probe = require('himalaya.domain.email.probe')
local perf = require('himalaya.perf')
local job = require('himalaya.job')
local win = require('himalaya.ui.win')

local M = {}

-- Module-local state
local all_display_rows = nil -- full tree from last fetch
local id_to_index = nil -- email id (string) → 1-based index in all_display_rows
local last_edges = nil -- raw edges from last fetch (for local rebuild)
local thread_query = '' -- search query for thread mode
local current_page = 1
local list_generation = 0 -- incremented on each list(); stale callbacks bail out
local list_job = nil -- in-flight thread fetch job handle
local enrich_job = nil -- in-flight enrich_with_flags job handle

local account_flag = account_state.flag

--- Rebuild the id→index lookup table from all_display_rows.
local function rebuild_id_index()
  id_to_index = {}
  if not all_display_rows then
    return
  end
  for i, row in ipairs(all_display_rows) do
    id_to_index[tostring(row.env.id)] = i
  end
end

--- Kill all in-flight thread listing jobs synchronously.
--- Called before any new CLI command to avoid database lock contention.
function M.cancel_jobs()
  list_generation = list_generation + 1
  if list_job then
    job.kill_and_wait(list_job)
    list_job = nil
  end
  if enrich_job then
    job.kill_and_wait(enrich_job)
    enrich_job = nil
  end
end

--- Render one page of the cached thread display rows into the current buffer.
--- @param page number
--- @param opts? table  Optional: { restore_cursor = {line, col} }
function M.render_page(page, opts)
  if not all_display_rows then
    return
  end
  opts = opts or {}

  local email = require('himalaya.domain.email')
  local thread_renderer = require('himalaya.ui.thread_renderer')
  local listing = require('himalaya.ui.listing')

  local ps = listing.effective_page_size()

  local total_pages = math.max(1, math.ceil(#all_display_rows / ps))
  page = math.max(1, math.min(page, total_pages))
  current_page = page

  local start_idx = (page - 1) * ps + 1
  local end_idx = math.min(#all_display_rows, start_idx + ps - 1)
  local slice = {}
  for i = start_idx, end_idx do
    slice[#slice + 1] = all_display_rows[i]
  end

  local folder = vim.b.himalaya_folder or 'INBOX'
  local display_query = thread_query == '' and 'all' or thread_query
  local buftype = vim.b.himalaya_buffer_type == 'thread-listing' and 'file' or 'edit'
  vim.cmd(
    string.format(
      'silent! %s Himalaya/threads [%s] [%s] [page %d⁄%d]',
      buftype,
      folder,
      display_query,
      page,
      total_pages
    )
  )
  vim.bo.modifiable = true

  local bufnr = vim.api.nvim_get_current_buf()
  local result = thread_renderer.render(slice, email._bufwidth())
  -- Set winbar first so page_size reflects actual visible area
  listing.apply_header(bufnr, result.header)

  -- After winbar is set, visible area may have shrunk — truncate if needed
  local actual_ps = listing.effective_page_size()
  if #slice > actual_ps then
    local trimmed = {}
    for i = 1, actual_ps do
      trimmed[i] = result.lines[i]
    end
    result.lines = trimmed
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)

  -- Apply seen highlights from enriched flag data
  local envs = {}
  for _, row in ipairs(slice) do
    envs[#envs + 1] = row.env
  end
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
--- @param listing_win number  window to render in (avoids E36 if picker has focus)
--- @param gen number  generation at time of request; bail if stale
local function enrich_with_flags(acct, folder, listing_win, gen)
  if not all_display_rows or #all_display_rows == 0 then
    return
  end
  perf.count('enrich_with_flags')

  -- Cap the fetch at 200 envelopes. The flat list returns the most recent
  -- emails by date, which naturally covers the top thread pages. For large
  -- threads (500+), emails beyond the cap show empty flags until the user
  -- pages to them — same as the initial render before enrich completes.
  local fetch_size = math.min(#all_display_rows, 200)
  enrich_job = request.json({
    cmd = 'envelope list --folder %s %s --page-size %d --page 1',
    args = { folder, account_flag(acct), fetch_size },
    msg = 'Fetching flags',
    silent = true,
    is_stale = function()
      return gen ~= list_generation
    end,
    on_error = function()
      enrich_job = nil
    end,
    on_data = function(envs)
      enrich_job = nil
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
      if not vim.api.nvim_win_is_valid(listing_win) then
        return
      end
      vim.api.nvim_win_call(listing_win, function()
        M.render_page(current_page, { restore_cursor = vim.api.nvim_win_get_cursor(listing_win) })
      end)
    end,
  })
end

--- Fetch threads and render.
--- @param account? string
--- @param opts? table  Optional: { restore_email_id = string, restore_cursor_line = number }
function M.list(account, opts)
  opts = opts or {}
  local context = require('himalaya.state.context')
  if account then
    vim.b.himalaya_account = account
    vim.b.himalaya_folder = 'INBOX'
  end
  local acct, folder = context.resolve()
  if acct == '' then
    acct = account_state.default()
  end

  -- Kill all in-flight CLI jobs (ours, flat listing's, and probe) to
  -- avoid database lock contention on rapid mode switches.
  require('himalaya.domain.email')._cancel_jobs()
  probe.cancel_sync()
  M.cancel_jobs()
  list_generation = list_generation + 1
  local my_gen = list_generation

  -- Capture the listing window now so async callbacks render here even
  -- if a picker or other floating window has focus when they fire.
  local listing_win = vim.api.nvim_get_current_win()

  -- Show loading indicator while fetching
  if vim.b.himalaya_buffer_type == 'listing' or vim.b.himalaya_buffer_type == 'thread-listing' then
    vim.wo.winbar = '%#Comment# loading...%*'
  end

  list_job = request.json({
    cmd = 'envelope thread --folder %s %s %s',
    args = { folder, account_flag(acct), thread_query },
    msg = string.format('Fetching %s threads', folder),
    is_stale = function()
      return my_gen ~= list_generation
    end,
    on_error = function()
      list_job = nil
      if vim.api.nvim_win_is_valid(listing_win) and vim.wo[listing_win].winbar:find('loading') then
        vim.wo[listing_win].winbar = ''
      end
    end,
    on_data = function(data)
      list_job = nil
      last_edges = data
      local reverse = config.get().thread_reverse
      local rows = tree.build(data, { reverse = reverse })
      tree.build_prefix(rows, { reverse = reverse })

      -- Pre-populate flags from cached flat listing envelopes so the
      -- initial render shows flags instead of blank columns.
      local ok, cached_envs =
        pcall(vim.api.nvim_buf_get_var, vim.api.nvim_win_get_buf(listing_win), 'himalaya_envelopes')
      if ok and cached_envs then
        local id_map = {}
        for _, env in ipairs(cached_envs) do
          id_map[tostring(env.id)] = env
        end
        for _, row in ipairs(rows) do
          local cached = id_map[tostring(row.env.id)]
          if cached then
            row.env.flags = cached.flags
            row.env.has_attachment = cached.has_attachment
          end
        end
      end

      all_display_rows = rows
      rebuild_id_index()

      if not vim.api.nvim_win_is_valid(listing_win) then
        return
      end
      local listing_bufnr = vim.api.nvim_win_get_buf(listing_win)
      vim.b[listing_bufnr].himalaya_account = acct
      vim.b[listing_bufnr].himalaya_folder = folder
      vim.api.nvim_win_call(listing_win, function()
        local listing_ui = require('himalaya.ui.listing')
        if opts.restore_cursor_line then
          -- Restore cursor to same line position (like dd in normal buffers).
          -- Compute which page that line falls on after re-fetch.
          local ps = listing_ui.effective_page_size()
          local global_idx = math.min(opts.restore_cursor_line + (current_page - 1) * ps, #rows)
          global_idx = math.max(1, global_idx)
          local page = math.floor((global_idx - 1) / ps) + 1
          local cursor_in_page = global_idx - (page - 1) * ps
          M.render_page(page, { restore_cursor = { cursor_in_page, 0 } })
        elseif opts.restore_email_id and opts.restore_email_id ~= '' then
          -- Find the target email and compute its page + line
          local target_idx = 1
          for i, row in ipairs(rows) do
            if tostring(row.env.id) == opts.restore_email_id then
              target_idx = i
              break
            end
          end
          local ps = listing_ui.effective_page_size()
          local page = math.floor((target_idx - 1) / ps) + 1
          local cursor_in_page = target_idx - (page - 1) * ps
          M.render_page(page, { restore_cursor = { cursor_in_page, 0 } })
        else
          M.render_page(1)
        end

        enrich_with_flags(acct, folder, listing_win, my_gen)
      end)
    end,
  })
end

--- Navigate to the next page of threads.
function M.next_page()
  if not all_display_rows then
    return
  end
  local ps = require('himalaya.ui.listing').effective_page_size()
  local total_pages = math.max(1, math.ceil(#all_display_rows / ps))
  if current_page >= total_pages then
    vim.cmd('echohl WarningMsg | echo "Already on last page" | echohl None')
    return
  end
  M.render_page(current_page + 1)
end

--- Navigate to the previous page of threads.
function M.previous_page()
  if not all_display_rows then
    return
  end
  if current_page <= 1 then
    vim.cmd('echohl WarningMsg | echo "Already on first page" | echohl None')
    return
  end
  M.render_page(math.max(1, current_page - 1))
end

--- Read the email under cursor.
function M.read()
  require('himalaya.domain.email').read()
end

--- Switch back to flat listing mode, preserving folder/account context.
function M.toggle_to_flat()
  local listing = require('himalaya.ui.listing')
  local id = listing.get_email_id_from_line(vim.api.nvim_get_current_line())
  all_display_rows = nil
  id_to_index = nil
  last_edges = nil
  vim.api.nvim_create_augroup('HimalayaThreadListing', { clear = true })
  require('himalaya.domain.email').list(nil, { restore_email_id = id })
end

--- Toggle reverse thread order (newest replies first).
--- Rebuilds from cached edges synchronously (no network round-trip).
function M.toggle_reverse()
  local reverse = not config.get().thread_reverse
  config.set('thread_reverse', reverse)
  if last_edges then
    local rows = tree.build(last_edges, { reverse = reverse })
    tree.build_prefix(rows, { reverse = reverse })
    all_display_rows = rows
    rebuild_id_index()
    M.render_page(1)
  else
    M.list()
  end
end

--- Open search popup and re-fetch threads with the resulting query.
function M.set_thread_query()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  local search = require('himalaya.ui.search')
  search.open(function(final_query, new_folder)
    thread_query = final_query
    if new_folder and new_folder ~= '' then
      vim.b.himalaya_folder = new_folder
    end
    M.list()
  end, thread_query, folder, account)
end

--- Re-render on resize: recomputes which page the selected email belongs
--- to at the new window height and places cursor on that email.
function M.resize()
  if not all_display_rows then
    return
  end

  -- Identify the email under cursor
  local listing = require('himalaya.ui.listing')
  local cursor_email_id = listing.get_email_id_from_line(vim.api.nvim_get_current_line())

  -- Find its global (1-based) index in all_display_rows
  local global_idx = (cursor_email_id ~= '' and id_to_index and id_to_index[cursor_email_id]) or 1

  -- Compute page size using the same formula as render_page
  local new_ps = listing.effective_page_size()

  -- Compute which page the email is on and cursor position within that page
  local new_page = math.floor((global_idx - 1) / new_ps) + 1
  local cursor_in_page = global_idx - (new_page - 1) * new_ps

  M.render_page(new_page, { restore_cursor = { cursor_in_page, 0 } })
end

--- Optimistically mark an envelope as Seen in cached thread data.
--- Only updates the data and applies the highlight to the specific line.
--- A full render_page is avoided because _mark_seen runs during
--- email.read() — right after the reading split opens, before WinResized
--- fires.  Calling render_page here would rewrite the buffer at the new
--- (smaller) page size with the old page number, clobbering the cursor
--- position that the WinResized handler needs to compute the correct page.
--- @param email_id string
function M.mark_seen_optimistic(email_id)
  if not all_display_rows then
    return
  end

  local idx = id_to_index and id_to_index[tostring(email_id)]
  if idx then
    local row = all_display_rows[idx]
    local flags = row.env.flags or {}
    for _, f in ipairs(flags) do
      if f == 'Seen' then
        return
      end
    end
    table.insert(flags, 'Seen')
    row.env.flags = flags
  end

  -- Apply the seen highlight to the specific buffer line without
  -- re-rendering.  The WinResized handler will do the full page
  -- recalculation and re-render with correct highlights.
  local listing_mod = require('himalaya.ui.listing')
  local ns_seen = vim.api.nvim_create_namespace('himalaya_seen')
  local eid = tostring(email_id)
  local _, buf = win.find_by_buftype('thread-listing')
  if not buf then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if listing_mod.get_email_id_from_line(line) == eid then
      vim.api.nvim_buf_set_extmark(buf, ns_seen, i - 1, 0, {
        end_row = i,
        hl_eol = true,
        hl_group = 'HimalayaSeen',
        priority = 200,
      })
      break
    end
  end
end

--- Test-only accessor to set module-local state.
function M._set_state(rows, page)
  all_display_rows = rows
  rebuild_id_index()
  current_page = page
end

return M
