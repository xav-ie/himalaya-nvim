local request = require('himalaya.request')
local log = require('himalaya.log')
local config = require('himalaya.config')
local account_state = require('himalaya.state.account')
local probe = require('himalaya.domain.email.probe')
local cache = require('himalaya.domain.email.cache')
local paging = require('himalaya.domain.email.paging')
local flags_util = require('himalaya.domain.email.flags')
local perf = require('himalaya.perf')
local job = require('himalaya.job')
local win = require('himalaya.ui.win')

local M = {}

-- Module-local state
local saved_view = nil
local saved_cursor_id = nil -- email ID for cursor restoration after re-fetch
local resize_timer = nil -- vim.uv timer for debounced re-fetch
local resize_job = nil -- in-flight resize re-fetch job handle
local resize_generation = 0 -- incremented on kill; stale callbacks check this
local fetch_generation = 0 -- incremented on each list_with(); stale callbacks bail out
local fetch_job = nil -- in-flight list_with job handle
local contact_cache_base = '' -- base string for cached contact completions
local contact_cache_items = {} -- formatted items from last contact command

local account_flag = account_state.flag

--- Extract numeric email ID from a listing line.
--- Delegates to ui.listing; kept for backward compatibility.
--- @param line string
--- @return string
function M._get_email_id_from_line(line)
  return require('himalaya.ui.listing').get_email_id_from_line(line)
end

--- Get email ID from line under cursor.
--- @return string  empty string when current line has no email ID
local function get_email_id_under_cursor()
  local line = vim.api.nvim_get_current_line()
  return M._get_email_id_from_line(line)
end

--- Get email IDs from a range of lines.
--- @param first_line number
--- @param last_line number
--- @return string space-separated IDs
local function get_email_id_under_cursors(first_line, last_line)
  local ids = {}
  for lnum = first_line, last_line do
    local line = vim.fn.getline(lnum)
    local id = M._get_email_id_from_line(line)
    if id ~= '' then
      table.insert(ids, id)
    end
  end
  return table.concat(ids, ' ')
end

--- Calculate usable buffer width (accounts for number column, fold column, sign column).
--- @return number
function M._bufwidth()
  perf.start('_bufwidth')
  local listing = require('himalaya.ui.listing')
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local width = vim.fn.winwidth(winid) - listing.gutter_width(winid, bufnr)
  perf.stop('_bufwidth')
  return width
end

--- Detect whether current buffer is an envelope listing buffer.
--- @return boolean
local function in_listing_buffer()
  local bt = vim.b.himalaya_buffer_type
  return bt == 'listing' or bt == 'thread-listing'
end

--- Check whether an email reading window is open in the current tab.
--- @return boolean
local function is_reading_email()
  return win.find_by_name('Himalaya/read email') ~= nil
end

--- Render envelopes into a listing buffer: set lines, header, and seen highlights.
--- @param bufnr number
--- @param envelopes table[]
--- @return table  renderer result { header, separator, lines }
local function render_listing_buffer(bufnr, envelopes)
  local renderer = require('himalaya.ui.renderer')
  local listing = require('himalaya.ui.listing')
  local result = renderer.render(envelopes, M._bufwidth())
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
  listing.apply_header(bufnr, result.header)
  listing.apply_highlights(bufnr, envelopes, { flags_compacted = result.flags_compacted })
  vim.bo[bufnr].modifiable = false
  return result
end

local is_unseen = flags_util.is_unseen
local count_unseen = flags_util.count_unseen

--- Update the buffer title with folder, query, page, and total info.
--- @param folder string
--- @param qry string
--- @param pg number
--- @param total_str string
--- @param bufcmd? string  vim command to set name ('file' or 'edit', defaults to 'file')
--- @param unread? number  count of unseen envelopes on the page
--- @param sort? string  current sort clause (e.g. 'date desc')
local function update_listing_title(folder, qry, pg, total_str, bufcmd, unread, sort)
  bufcmd = bufcmd or 'file'
  local display_query = qry == '' and 'all' or qry
  local unread_str = ''
  if unread and unread > 0 then
    unread_str = string.format(' [%d unread]', unread)
  end
  local sort_indicator = ''
  if sort then
    local field, dir = sort:match('^(%S+)%s+(%S+)$')
    local arrow = dir == 'desc' and '↓' or '↑'
    sort_indicator = string.format(' [%s %s]', field or sort, arrow)
  end
  local bufname = string.format(
    'Himalaya/envelopes [%s] [%s] [page %d⁄%s]%s%s',
    folder,
    display_query,
    pg,
    total_str,
    unread_str,
    sort_indicator
  )
  vim.cmd(string.format('silent! %s %s', bufcmd, vim.fn.fnameescape(bufname)))
end

--- Combine a filter query and sort clause into a full CLI query string.
--- @param filter string  filter portion (may be empty)
--- @param sort string  sort clause without 'order by' prefix (may be empty)
--- @return string
local function build_cli_query(filter, sort)
  local parts = {}
  if filter ~= '' then
    parts[#parts + 1] = filter
  end
  if sort ~= '' then
    parts[#parts + 1] = 'order by ' .. sort
  end
  return table.concat(parts, ' ')
end

--- Restore cursor position after a listing re-render.
--- Tries saved_cursor_id first, then saved_view, then goes to line 1.
--- @param display table[]  visible envelopes
local function restore_cursor(display)
  if saved_cursor_id then
    local target = saved_cursor_id
    saved_cursor_id = nil
    saved_view = nil
    local idx = paging.find_envelope_index(display, target)
    if idx then
      pcall(vim.api.nvim_win_set_cursor, 0, { idx, 0 })
    end
  elseif saved_view then
    vim.fn.winrestview(saved_view)
    saved_view = nil
  else
    vim.cmd('0')
  end
end

--- Re-fetch the current listing, dispatching to thread or flat mode as appropriate.
--- @param account string
--- @param folder string
--- @param opts? table  Optional: { restore_cursor_line = number }
local function refresh_listing(account, folder, opts)
  opts = opts or {}
  -- Always read state from the listing buffer, not the current buffer.
  -- When called from the reading buffer (e.g. gD), vim.b.* refers to
  -- the reading buffer which lacks himalaya_buffer_type/page/query/sort.
  local listing_win, listing_bufnr, _ = win.find_by_buftype({ 'listing', 'thread-listing' })
  local bt = (listing_bufnr and vim.b[listing_bufnr].himalaya_buffer_type) or vim.b.himalaya_buffer_type
  if bt == 'thread-listing' then
    if opts.restore_cursor_line then
      require('himalaya.domain.email.thread_listing').list(nil, { restore_cursor_line = opts.restore_cursor_line })
    else
      -- Get cursor email ID from the listing buffer, not the current buffer.
      local cursor_id = ''
      if listing_win then
        local lnum = vim.api.nvim_win_get_cursor(listing_win)[1]
        local line = vim.api.nvim_buf_get_lines(listing_bufnr, lnum - 1, lnum, false)[1] or ''
        cursor_id = require('himalaya.ui.listing').get_email_id_from_line(line)
      end
      require('himalaya.domain.email.thread_listing').list(nil, { restore_email_id = cursor_id })
    end
  else
    local b = listing_bufnr and vim.b[listing_bufnr] or vim.b
    M.list_with(account, folder, b.himalaya_page or 1, b.himalaya_query or '', b.himalaya_sort or 'date desc')
  end
end

--- Compute the page size (visible envelope rows) for the current window.
--- @return number
local function page_size()
  return require('himalaya.ui.listing').effective_page_size()
end

--- Get the relevant email ID depending on context (listing vs read buffer).
--- @return string
function M.context_email_id()
  if in_listing_buffer() then
    return get_email_id_under_cursor()
  else
    return vim.b.himalaya_current_email_id or ''
  end
end

--- Resolve the target email ID(s) for a mutating operation.
--- In listing: uses cursor line (or visual range); in read buffer: uses buffer var.
--- @param first_line? number
--- @param last_line? number
--- @return string space-separated ID(s)
local function resolve_target_ids(first_line, last_line)
  if in_listing_buffer() and first_line and last_line then
    return get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    return get_email_id_under_cursor()
  else
    return vim.b.himalaya_current_email_id or ''
  end
end

--- Internal callback for list_with — populates the envelope listing buffer.
--- @param sort string  sort clause (e.g. 'date desc')
--- @param fetch_offset? number actual CLI data offset (defaults to (page-1)*pg_size)
local function on_list_with(account, folder, page, pg_size, qry, sort, data, fetch_offset)
  local acct_flag = account_flag(account)
  local acct_flag_str = table.concat(acct_flag, ' ')
  local cli_qry = build_cli_query(qry, sort)
  probe.reset_if_changed(acct_flag_str, folder, cli_qry)

  local cache_key = acct_flag_str .. '\0' .. folder .. '\0' .. cli_qry
  probe.set_total_from_data(cache_key, page, pg_size, #data)
  local total_str = probe.total_pages_str(cache_key, pg_size)

  local renderer = require('himalaya.ui.renderer')
  local listing = require('himalaya.ui.listing')
  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local bufcmd = in_listing_buffer() and 'file' or 'edit'
  local new_offset = fetch_offset or ((page - 1) * pg_size)
  local page_data = paging.fetch_page_slice(data, page, pg_size, new_offset)
  update_listing_title(folder, qry, page, total_str, bufcmd, count_unseen(page_data), sort)
  -- Re-read bufnr: when bufcmd was 'edit', the command above created a new
  -- buffer in the window.  All subsequent buffer-variable writes must target
  -- the buffer that is actually displayed, not the one that existed before.
  bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].modifiable = true
  vim.b[bufnr].himalaya_account = account
  vim.b[bufnr].himalaya_folder = folder
  vim.b[bufnr].himalaya_page = page
  vim.b[bufnr].himalaya_page_size = pg_size
  vim.b[bufnr].himalaya_query = qry
  vim.b[bufnr].himalaya_sort = sort

  if vim.b[bufnr].himalaya_cache_key ~= cache_key then
    vim.b[bufnr].himalaya_envelopes = data
    vim.b[bufnr].himalaya_cache_offset = new_offset
  else
    local merged, merged_offset =
      cache.merge(vim.b[bufnr].himalaya_envelopes, vim.b[bufnr].himalaya_cache_offset or 0, data, new_offset)
    vim.b[bufnr].himalaya_envelopes = merged
    vim.b[bufnr].himalaya_cache_offset = merged_offset
  end
  vim.b[bufnr].himalaya_cache_key = cache_key

  local result = renderer.render(page_data, M._bufwidth())
  -- Empty folder: show placeholder and finish early
  if #page_data == 0 then
    listing.apply_header(bufnr, result.header)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '  (no emails)' })
    vim.b[bufnr].himalaya_buffer_type = 'listing'
    vim.bo[bufnr].filetype = 'himalaya-email-listing'
    vim.bo[bufnr].modified = false
    require('himalaya.events').emit('EmailsListed', {
      account = account,
      folder = folder,
      page = page,
      count = 0,
    })
    probe.start(acct_flag_str, folder, pg_size, page, cli_qry, bufnr)
    return
  end
  -- Set winbar first so page_size() reflects actual visible area
  listing.apply_header(bufnr, result.header)
  -- After winbar is set, visible area may have shrunk — truncate if needed
  local actual_ps = listing.effective_page_size()
  local display = page_data
  if #page_data > actual_ps then
    display = {}
    for i = 1, actual_ps do
      display[i] = page_data[i]
    end
    local trimmed = {}
    for i = 1, actual_ps do
      trimmed[i] = result.lines[i]
    end
    result.lines = trimmed
    vim.b[bufnr].himalaya_page_size = actual_ps
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
  listing.apply_highlights(bufnr, display, { flags_compacted = result.flags_compacted })
  vim.b[bufnr].himalaya_buffer_type = 'listing'
  vim.bo[bufnr].filetype = 'himalaya-email-listing'
  vim.bo[bufnr].modified = false
  vim.fn.winrestview({ topline = 1 })
  restore_cursor(display)

  require('himalaya.events').emit('EmailsListed', {
    account = account,
    folder = folder,
    page = page,
    count = #data,
  })

  probe.start(acct_flag_str, folder, pg_size, page, cli_qry, bufnr)
end

--- List envelopes, optionally switching account first.
--- @param account? string
--- @param opts? table  Optional: { restore_email_id = string }
function M.list(account, opts)
  opts = opts or {}
  local context = require('himalaya.state.context')
  if account then
    vim.b.himalaya_account = account
    vim.b.himalaya_folder = 'INBOX'
    vim.b.himalaya_page = 1
    vim.b.himalaya_query = ''
    vim.b.himalaya_sort = 'date desc'
  end
  if opts.restore_email_id then
    saved_cursor_id = opts.restore_email_id
  end
  local acct, folder = context.resolve()
  if acct == '' then
    acct = account_state.default()
  end
  M.list_with(acct, folder, vim.b.himalaya_page or 1, vim.b.himalaya_query or '', vim.b.himalaya_sort or 'date desc')
end

--- Kill all in-flight fetch/resize jobs synchronously.
--- Called before any new CLI command to avoid database lock contention.
function M._cancel_jobs()
  fetch_generation = fetch_generation + 1
  if fetch_job then
    job.kill_and_wait(fetch_job)
    fetch_job = nil
  end
  if resize_timer then
    resize_timer:stop()
    resize_timer = nil
  end
  if resize_job then
    resize_generation = resize_generation + 1
    job.kill_and_wait(resize_job)
    resize_job = nil
  end
end

--- List envelopes with explicit parameters.
--- @param account string
--- @param folder string
--- @param page number
--- @param qry string  filter query (without 'order by')
--- @param sort? string  sort clause (e.g. 'date desc'); defaults to 'date desc'
function M.list_with(account, folder, page, qry, sort)
  sort = sort or 'date desc'
  -- Kill all in-flight CLI jobs (ours, thread listing's, and probe) to
  -- avoid database lock contention on rapid mode switches / page changes.
  require('himalaya.domain.email.thread_listing').cancel_jobs()
  M._cancel_jobs()
  probe.cancel_sync()

  fetch_generation = fetch_generation + 1
  local my_gen = fetch_generation

  -- Show loading indicator while fetching
  if in_listing_buffer() then
    vim.wo.winbar = '%#Comment# loading...%*'
  end

  -- Prefer the existing listing window over the current window.
  -- When called from a reading buffer (e.g. gD), the current window
  -- is the reading window, not the listing window.
  local listing_win = win.find_by_buftype({ 'listing', 'thread-listing' }) or vim.api.nvim_get_current_win()

  local ps = page_size()
  -- On first load the winbar hasn't been set yet, so winheight still
  -- includes that row.  Reserve one line for the header winbar.
  if vim.wo.winbar == '' then
    ps = math.max(1, ps - 1)
  end
  -- Double the fetch size to prime the cache with an extra page of
  -- envelopes.  Adjust the CLI page number so the returned data always
  -- covers the requested display page:
  --   cli_page = ceil(page/2), fetch_ps = ps*2
  -- Odd display pages → first half of CLI data, even → second half.
  local fetch_ps = ps * 2
  local cli_qry = build_cli_query(qry, sort)
  local search_target = saved_cursor_id
  local acct_flag = account_flag(account)

  local function on_error()
    fetch_job = nil
    -- Clear loading indicator on failure
    if vim.api.nvim_win_is_valid(listing_win) then
      vim.api.nvim_win_call(listing_win, function()
        if in_listing_buffer() and vim.wo.winbar:find('loading') then
          vim.wo.winbar = ''
        end
      end)
    end
  end

  -- Normal fetch: doubled page size for cache priming.
  local function do_fetch(cli_page, batch_offset)
    fetch_job = request.json({
      cmd = 'envelope list --folder %q %s --page-size %d --page %d %s',
      args = { folder, acct_flag, fetch_ps, cli_page, cli_qry },
      msg = string.format('Fetching %s envelopes', folder),
      is_stale = function()
        return my_gen ~= fetch_generation
      end,
      on_error = on_error,
      on_data = function(data)
        fetch_job = nil
        if not vim.api.nvim_win_is_valid(listing_win) then
          return
        end
        vim.api.nvim_win_call(listing_win, function()
          on_list_with(account, folder, page, ps, qry, sort, data, batch_offset)
        end)
      end,
    })
  end

  -- Search: page through results with doubled page size (same as normal
  -- fetches) until the target email is found, then render that page.
  if search_target then
    local target_id = search_target
    saved_cursor_id = nil

    local function search_batch(cli_page)
      local batch_offset = (cli_page - 1) * fetch_ps
      fetch_job = request.json({
        cmd = 'envelope list --folder %q %s --page-size %d --page %d %s',
        args = { folder, acct_flag, fetch_ps, cli_page, cli_qry },
        msg = string.format('Fetching %s envelopes', folder),
        is_stale = function()
          return my_gen ~= fetch_generation
        end,
        on_error = function()
          fetch_job = nil
          -- Page beyond data: fall back to page 1.
          page = 1
          do_fetch(1, 0)
        end,
        on_data = function(data)
          fetch_job = nil
          if not vim.api.nvim_win_is_valid(listing_win) then
            return
          end
          for i, env in ipairs(data) do
            if tostring(env.id) == target_id then
              -- Found: compute actual display page and render.
              local actual_page = math.floor((batch_offset + i - 1) / ps) + 1
              saved_cursor_id = target_id
              vim.api.nvim_win_call(listing_win, function()
                on_list_with(account, folder, actual_page, ps, qry, sort, data, batch_offset)
              end)
              return
            end
          end
          if #data >= fetch_ps then
            search_batch(cli_page + 1)
          else
            -- End of data: fall back to page 1.
            page = 1
            do_fetch(1, 0)
          end
        end,
      })
    end
    search_batch(1)
  else
    local cli_page = math.ceil(page / 2)
    do_fetch(cli_page, (cli_page - 1) * fetch_ps)
  end
end

--- Slice cached envelopes to fit the current window height.
--- @param envelopes table[] full cached envelope list
--- @return table[] display subset
local function display_slice(envelopes)
  return paging.cache_slice(envelopes, vim.b.himalaya_page or 1, page_size(), vim.b.himalaya_cache_offset or 0)
end

--- Optimistically mark an envelope as Seen in the listing buffer.
--- Updates the cached envelope data and applies a single extmark,
--- matching the thread listing's approach. The flag column character
--- is corrected on the next full re-render (resize, page change).
--- @param email_id string
local function mark_envelope_seen(email_id)
  local listing_winid, listing_bufnr, listing_type = win.find_by_buftype({ 'listing', 'thread-listing' })
  if not listing_winid then
    return
  end

  if listing_type == 'thread-listing' then
    require('himalaya.domain.email.thread_listing').mark_seen_optimistic(email_id)
    return
  end

  local ok, envelopes = pcall(vim.api.nvim_buf_get_var, listing_bufnr, 'himalaya_envelopes')
  if not (ok and envelopes) then
    return
  end

  -- Update the envelope in cache.
  local eid = tostring(email_id)
  for _, env in ipairs(envelopes) do
    if tostring(env.id) == eid then
      local flags = env.flags or {}
      for _, f in ipairs(flags) do
        if f == 'Seen' then
          return
        end
      end
      table.insert(flags, 'Seen')
      env.flags = flags
      break
    end
  end
  vim.api.nvim_buf_set_var(listing_bufnr, 'himalaya_envelopes', envelopes)

  -- Apply seen highlight (remove column extmarks, keep separators).
  local listing_mod = require('himalaya.ui.listing')
  local lines = vim.api.nvim_buf_get_lines(listing_bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if listing_mod.get_email_id_from_line(line) == eid then
      listing_mod.mark_line_as_seen(listing_bufnr, i - 1)
      break
    end
  end
end

--- Read email under cursor.
function M.read()
  M.cancel_resize()
  local current_id = get_email_id_under_cursor()
  if current_id == '' or current_id == 'ID' then
    return
  end
  -- Capture listing window synchronously before the async request,
  -- so the callback can reliably reference it even if focus changes.
  local listing_winid = vim.api.nvim_get_current_win()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  probe.cancel(function()
    request.plain({
      cmd = 'message read %s --folder %q %s',
      args = { account_flag(account), folder, current_id },
      msg = string.format('Fetching email %s', current_id),
      on_error = function()
        probe.restart()
      end,
      on_data = function(data)
        -- Prepare email content into a buffer before showing it,
        -- so the split appears with content already loaded (no flash).
        local lines = vim.split(data:gsub('\r', ''), '\n')
        if #lines > 1 and lines[#lines] == '' then
          table.remove(lines)
        end

        -- Reuse existing email window in current tab to avoid resize jitter
        local reused = false
        local reading_win = win.find_by_name('Himalaya/read email')
        if reading_win then
          vim.api.nvim_set_current_win(reading_win)
          reused = true
        end

        if not reused then
          -- Create buffer and populate before showing — the split opens
          -- with content already visible, no empty-buffer frame.
          local listing_view
          if vim.api.nvim_win_is_valid(listing_winid) then
            listing_view = vim.api.nvim_win_call(listing_winid, function()
              return vim.fn.winsaveview()
            end)
          end
          local email_buf = vim.api.nvim_create_buf(true, true)
          vim.api.nvim_buf_set_lines(email_buf, 0, -1, false, lines)
          local cfg = require('himalaya.config').get()
          local threshold = cfg.reading_split_threshold or 115
          local listing_width = vim.api.nvim_win_get_width(listing_winid)
          local direction = listing_width >= threshold and 'right' or 'below'
          local ratio = cfg.reading_split_ratio or 0.6
          vim.api.nvim_open_win(email_buf, true, { split = direction, win = listing_winid })
          if direction == 'right' then
            vim.api.nvim_win_set_width(0, math.floor(listing_width * ratio))
          else
            local listing_height = vim.api.nvim_win_get_height(listing_winid)
            vim.api.nvim_win_set_height(0, math.floor((listing_height + vim.api.nvim_win_get_height(0)) * ratio))
          end
          -- Freeze listing viewport — the split shrinks its window and
          -- scrolloff would otherwise scroll it to keep the cursor centered.
          if listing_view and vim.api.nvim_win_is_valid(listing_winid) then
            vim.api.nvim_win_call(listing_winid, function()
              vim.fn.winrestview(listing_view)
            end)
          end
        else
          vim.bo.modifiable = true
          vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        end

        local read_bufname = string.format('Himalaya/read email [%s]', current_id)
        vim.cmd(string.format('silent! file %s', vim.fn.fnameescape(read_bufname)))
        vim.b.himalaya_account = account
        vim.b.himalaya_folder = folder
        vim.b.himalaya_current_email_id = current_id
        vim.bo.filetype = 'himalaya-email-reading'
        vim.bo.modified = false
        vim.cmd('0')
        require('himalaya.events').emit('EmailRead', {
          account = account,
          folder = folder,
          email_id = current_id,
          bufnr = vim.api.nvim_get_current_buf(),
        })
        mark_envelope_seen(current_id)
        -- Wipe stale email reading buffers
        local cur_buf = vim.api.nvim_get_current_buf()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) and bufnr ~= cur_buf then
            local bname = vim.api.nvim_buf_get_name(bufnr)
            if bname:find('Himalaya/read email', 1, true) then
              vim.cmd('silent! bwipeout ' .. bufnr)
            end
          end
        end
        probe.restart()
      end,
    })
  end)
end

--- Delete email(s). Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.delete(first_line, last_line)
  local ids = resolve_target_ids(first_line, last_line)

  local cfg = config.get()
  if cfg.always_confirm then
    local id_count = #vim.split(vim.trim(ids), '%s+')
    local answer = vim.fn.inputdialog(
      string.format('Delete %d %s? [Y/n] ', id_count, id_count == 1 and 'email' or 'emails'),
      '',
      '_cancel_'
    )
    vim.cmd('redraw | echo')
    if answer == '_cancel_' or (answer ~= '' and answer:lower() ~= 'y') then
      return
    end
  end

  -- Capture reading window before the async request so we can close it on success.
  local reading_win = (not in_listing_buffer()) and vim.api.nvim_get_current_win() or nil
  -- Get the cursor line from the listing window (not the reading buffer, which
  -- would give the wrong line when gD is pressed from the reading buffer).
  local listing_win_cur = win.find_by_buftype({ 'listing', 'thread-listing' })
  local cursor_line = listing_win_cur and vim.api.nvim_win_get_cursor(listing_win_cur)[1] or vim.fn.line('.')
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  probe.cancel(function()
    request.plain({
      cmd = 'message delete %s --folder %q %s',
      args = { account_flag(account), folder, ids },
      msg = 'Deleting email',
      on_data = function()
        require('himalaya.events').emit('EmailDeleted', {
          account = account,
          folder = folder,
          ids = ids,
        })
        saved_view = vim.fn.winsaveview()
        refresh_listing(account, folder, { restore_cursor_line = cursor_line })
        if reading_win and vim.api.nvim_win_is_valid(reading_win) then
          pcall(vim.api.nvim_win_close, reading_win, true)
        end
      end,
    })
  end)
end

--- Copy email(s) to target folder. Supports visual range via first_line/last_line.
--- @param target_folder string
--- @param first_line? number
--- @param last_line? number
function M.copy(target_folder, first_line, last_line)
  local ids = resolve_target_ids(first_line, last_line)

  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  probe.cancel(function()
    request.plain({
      cmd = 'message copy %s --folder %q %q %s',
      args = {
        account_flag(account),
        folder,
        target_folder,
        ids,
      },
      msg = 'Copying email',
      on_data = function()
        require('himalaya.events').emit('EmailCopied', {
          account = account,
          folder = folder,
          ids = ids,
          target_folder = target_folder,
        })
        refresh_listing(account, folder)
      end,
    })
  end)
end

--- Move email(s) to target folder (with confirmation prompt). Supports visual range via first_line/last_line.
--- @param target_folder string
--- @param first_line? number
--- @param last_line? number
function M.move(target_folder, first_line, last_line)
  local ids = resolve_target_ids(first_line, last_line)

  local cfg = config.get()
  if cfg.always_confirm then
    local id_count = #vim.split(vim.trim(ids), '%s+')
    local answer = vim.fn.inputdialog(
      string.format('Move %d %s? [Y/n] ', id_count, id_count == 1 and 'email' or 'emails'),
      '',
      '_cancel_'
    )
    vim.cmd('redraw | echo')
    if answer == '_cancel_' or (answer ~= '' and answer:lower() ~= 'y') then
      return
    end
  end

  local reading_win = (not in_listing_buffer()) and vim.api.nvim_get_current_win() or nil
  local listing_win_cur = win.find_by_buftype({ 'listing', 'thread-listing' })
  local cursor_line = listing_win_cur and vim.api.nvim_win_get_cursor(listing_win_cur)[1] or vim.fn.line('.')
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  probe.cancel(function()
    request.plain({
      cmd = 'message move %s --folder %q %q %s',
      args = {
        account_flag(account),
        folder,
        target_folder,
        ids,
      },
      msg = 'Moving email',
      on_data = function()
        require('himalaya.events').emit('EmailMoved', {
          account = account,
          folder = folder,
          ids = ids,
          target_folder = target_folder,
        })
        refresh_listing(account, folder, { restore_cursor_line = cursor_line })
        if reading_win and vim.api.nvim_win_is_valid(reading_win) then
          pcall(vim.api.nvim_win_close, reading_win, true)
        end
      end,
    })
  end)
end

--- Open folder picker then copy email(s) to selected folder. Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.select_folder_then_copy(first_line, last_line)
  local folder_domain = require('himalaya.domain.folder')
  folder_domain.open_picker(function(target_folder)
    M.copy(target_folder, first_line, last_line)
  end)
end

--- Open folder picker then move email(s) to selected folder. Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.select_folder_then_move(first_line, last_line)
  local folder_domain = require('himalaya.domain.folder')
  folder_domain.open_picker(function(target_folder)
    M.move(target_folder, first_line, last_line)
  end)
end

--- Get current flags for the email under cursor from cached envelopes.
--- @return string[]
local function get_current_flags()
  if not in_listing_buffer() then
    return {}
  end
  local ok, envelopes = pcall(vim.api.nvim_buf_get_var, 0, 'himalaya_envelopes')
  if not (ok and envelopes) then
    return {}
  end
  local id = get_email_id_under_cursor()
  for _, env in ipairs(envelopes) do
    if tostring(env.id) == id then
      return env.flags or {}
    end
  end
  return {}
end

--- Add flags to email(s). Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.flag_add(first_line, last_line)
  local ids = resolve_target_ids(first_line, last_line)
  local flags_mod = require('himalaya.domain.email.flags')
  local all_flags = flags_mod.complete_list()

  vim.ui.select(all_flags, { prompt = 'Flag to add' }, function(flag)
    if not flag then
      return
    end
    local context = require('himalaya.state.context')
    local account, folder = context.resolve()
    probe.cancel(function()
      request.plain({
        cmd = 'flag add %s --folder %q %s %s',
        args = { account_flag(account), folder, flag, ids },
        msg = 'Adding flag: ' .. flag,
        on_data = function()
          require('himalaya.events').emit('EmailFlagAdded', {
            account = account,
            folder = folder,
            ids = ids,
            flag = flag,
          })
          refresh_listing(account, folder)
        end,
      })
    end)
  end)
end

--- Remove flags from email(s). Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.flag_remove(first_line, last_line)
  local ids = resolve_target_ids(first_line, last_line)
  local current_flags = get_current_flags()
  local flags_mod = require('himalaya.domain.email.flags')
  local options = #current_flags > 0 and current_flags or flags_mod.complete_list()

  vim.ui.select(options, { prompt = 'Flag to remove' }, function(flag)
    if not flag then
      return
    end
    local context = require('himalaya.state.context')
    local account, folder = context.resolve()
    probe.cancel(function()
      request.plain({
        cmd = 'flag remove %s --folder %q %s %s',
        args = { account_flag(account), folder, flag, ids },
        msg = 'Removing flag: ' .. flag,
        on_data = function()
          require('himalaya.events').emit('EmailFlagRemoved', {
            account = account,
            folder = folder,
            ids = ids,
            flag = flag,
          })
          refresh_listing(account, folder)
        end,
      })
    end)
  end)
end

--- Mark email(s) as seen. Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.mark_seen(first_line, last_line)
  local ids = resolve_target_ids(first_line, last_line)

  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  probe.cancel(function()
    request.plain({
      cmd = 'flag add %s --folder %q Seen %s',
      args = { account_flag(account), folder, ids },
      msg = 'Marking as seen',
      on_data = function()
        require('himalaya.events').emit('EmailMarkedSeen', {
          account = account,
          folder = folder,
          ids = ids,
        })
        saved_view = vim.fn.winsaveview()
        refresh_listing(account, folder)
      end,
    })
  end)
end

--- Mark email(s) as unseen. Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.mark_unseen(first_line, last_line)
  local ids = resolve_target_ids(first_line, last_line)

  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  probe.cancel(function()
    request.plain({
      cmd = 'flag remove %s --folder %q Seen %s',
      args = { account_flag(account), folder, ids },
      msg = 'Marking as unseen',
      on_data = function()
        require('himalaya.events').emit('EmailMarkedUnseen', {
          account = account,
          folder = folder,
          ids = ids,
        })
        saved_view = vim.fn.winsaveview()
        refresh_listing(account, folder)
      end,
    })
  end)
end

--- Download attachments for current email.
function M.download_attachments()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  local id = M.context_email_id()
  request.plain({
    cmd = 'attachment download %s --folder %q %s',
    args = { account_flag(account), folder, id },
    msg = 'Downloading attachments',
    on_data = function(data)
      data = vim.trim(data)
      if data == '' then
        log.info('No attachments found')
      else
        log.info('Attachments downloaded:\n' .. data)
      end
    end,
  })
end

--- Open current email in browser.
function M.open_browser()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  request.plain({
    cmd = 'message export %s --folder %q --open %s',
    args = { account_flag(account), folder, M.context_email_id() },
    msg = 'Opening message in the browser',
    on_data = function(data)
      log.info(data)
    end,
  })
end

--- Contact completion for omnifunc.
--- @param findstart number
--- @param base string
--- @return number|table
function M.complete_contact(findstart, base)
  if findstart == 1 then
    local cfg = config.get()
    if not cfg.complete_contact_cmd then
      vim.api.nvim_err_writeln('You must set "complete_contact_cmd" in config to complete contacts')
      return -3
    end

    -- Search for everything up to the last colon or comma
    local line_to_cursor = vim.fn.getline('.'):sub(1, vim.fn.col('.') - 1)
    local start = line_to_cursor:find('[^:,]*$')
    if not start then
      start = 1
    end

    -- Don't include leading spaces (convert to 0-based index)
    while start <= #line_to_cursor and line_to_cursor:sub(start, start) == ' ' do
      start = start + 1
    end

    return start - 1 -- 0-based for omnifunc
  else
    -- Filter from cache when the query refines a previous one
    if
      #contact_cache_items > 0
      and #base >= #contact_cache_base
      and base:sub(1, #contact_cache_base) == contact_cache_base
    then
      local filtered = {}
      local lower_base = base:lower()
      for _, item in ipairs(contact_cache_items) do
        if item:lower():find(lower_base, 1, true) then
          filtered[#filtered + 1] = item
        end
      end
      return filtered
    end

    local cfg = config.get()
    local cmd = cfg.complete_contact_cmd:gsub('%%s', vim.fn.shellescape(base))
    local output = vim.fn.system(cmd)
    local lines = vim.split(output, '\n', { trimempty = true })
    local items = {}
    for _, line in ipairs(lines) do
      items[#items + 1] = M._line_to_complete_item(line)
    end
    contact_cache_base = base
    contact_cache_items = items
    return items
  end
end

--- Format a contact line into a completion item.
--- @param line string tab-separated "email<TAB>name"
--- @return string
function M._line_to_complete_item(line)
  local fields = vim.split(line, '\t')
  local email_addr = fields[1]
  local name = ''
  if #fields > 1 then
    name = string.format('"%s"', fields[2])
  end
  return name .. string.format('<%s>', email_addr)
end

--- Schedule Phase 2: debounced re-fetch after resize settles.
--- Cancels any pending timer/job, then after 150ms fetches fresh data
--- for the current page to fill any sparse overlap from Phase 1.
--- @param bufnr number  listing buffer number
local function schedule_phase2_refetch(bufnr)
  if resize_timer then
    resize_timer:stop()
  end
  if resize_job then
    resize_generation = resize_generation + 1
    resize_job:kill()
    resize_job = nil
  end

  resize_timer = vim.uv.new_timer()
  resize_timer:start(
    150,
    0,
    vim.schedule_wrap(function()
      resize_timer = nil
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      -- Find the window still showing the listing buffer
      local listing_win = win.find_by_bufnr(bufnr)
      if not listing_win then
        return
      end
      local cursor_ln = vim.api.nvim_win_get_cursor(listing_win)[1]
      local cursor_id =
        M._get_email_id_from_line(vim.api.nvim_buf_get_lines(bufnr, cursor_ln - 1, cursor_ln, false)[1] or '')
      local account = vim.b[bufnr].himalaya_account or ''
      local folder_cur = vim.b[bufnr].himalaya_folder or 'INBOX'
      local cur_query = vim.b[bufnr].himalaya_query or ''
      local cur_sort = vim.b[bufnr].himalaya_sort or 'date desc'
      local cur_page = vim.b[bufnr].himalaya_page or 1
      local ps = vim.b[bufnr].himalaya_page_size
      local resize_cli_qry = build_cli_query(cur_query, cur_sort)
      resize_generation = resize_generation + 1
      local my_gen = resize_generation
      resize_job = request.json({
        cmd = 'envelope list --folder %q %s --page-size %d --page %d %s',
        args = { folder_cur, account_flag(account), ps, cur_page, resize_cli_qry },
        msg = 'Refetching page after resize',
        silent = true,
        is_stale = function()
          return my_gen ~= resize_generation
        end,
        on_data = function(data)
          resize_job = nil
          if not vim.api.nvim_win_is_valid(listing_win) then
            return
          end
          saved_cursor_id = cursor_id
          vim.api.nvim_win_call(listing_win, function()
            on_list_with(account, folder_cur, cur_page, ps, cur_query, cur_sort, data)
          end)
        end,
      })
    end)
  )
end

--- Handle listing window resize: two-phase overlap display + deferred re-fetch.
--- Phase 1 synchronously renders the overlap between old cache and new page
--- boundaries (jitter-free). Phase 2 debounces a full re-fetch after 150ms.
function M.resize_listing()
  if not in_listing_buffer() then
    return
  end
  local envelopes = vim.b.himalaya_envelopes
  if not envelopes then
    return
  end

  -- Guard: if the buffer's cache key doesn't match its own stamped state,
  -- the page data is stale.  This happens when a folder switch (e.g.
  -- INBOX → Drafts) triggers an async fetch and WinResized fires before
  -- the new data arrives.
  local buf_cache_key = vim.b.himalaya_cache_key
  if buf_cache_key then
    local current_key = table.concat(account_flag(vim.b.himalaya_account or ''), ' ')
      .. '\0'
      .. (vim.b.himalaya_folder or 'INBOX')
      .. '\0'
      .. build_cli_query(vim.b.himalaya_query or '', vim.b.himalaya_sort or 'date desc')
    if buf_cache_key ~= current_key then
      return
    end
  end

  perf.reset()
  perf.start('resize_listing_total')

  local reading = is_reading_email()

  local new_page_size = page_size()
  local old_page_size = vim.b.himalaya_page_size

  if not old_page_size then
    vim.b.himalaya_page_size = new_page_size
  elseif reading or new_page_size ~= old_page_size then
    -- Page-boundary logic (shared by reading truncation and Phase 1).
    -- Reading truncation uses the same overlap computation but skips Phase 2.
    local old_page = vim.b.himalaya_page or 1
    local cache_start = vim.b.himalaya_cache_offset or ((old_page - 1) * old_page_size)
    -- Buffer rows may not match cache indices (e.g., after Phase 1
    -- truncation or Phase 2 re-fetch). Map cursor to cache position via email ID.
    local cursor_row = math.max(1, math.min(vim.fn.line('.'), #envelopes))
    local cursor_line_text = vim.api.nvim_buf_get_lines(0, cursor_row - 1, cursor_row, false)[1] or ''
    local cursor_email_id = M._get_email_id_from_line(cursor_line_text)
    if cursor_email_id ~= '' then
      cursor_row = paging.find_envelope_index(envelopes, cursor_email_id) or cursor_row
    end
    local selected_global = cache_start + cursor_row - 1
    local resize_info = paging.resize_page(cache_start, #envelopes, selected_global, new_page_size)
    local new_page = resize_info.page
    local display_envelopes =
      paging.extract_range(envelopes, cache_start, resize_info.overlap_start, resize_info.overlap_end)
    local cursor_line = resize_info.cursor_line

    -- Update buffer state
    vim.b.himalaya_page = new_page
    vim.b.himalaya_page_size = new_page_size

    -- Render
    local bufnr = vim.api.nvim_get_current_buf()
    local folder_name = vim.b.himalaya_folder or 'INBOX'
    local buf_query = vim.b.himalaya_query or ''
    local buf_sort = vim.b.himalaya_sort or 'date desc'
    local acct_flag_str = table.concat(account_flag(vim.b.himalaya_account or ''), ' ')
    local cache_key = acct_flag_str .. '\0' .. folder_name .. '\0' .. build_cli_query(buf_query, buf_sort)
    local total_str = probe.total_pages_str(cache_key, new_page_size)
    update_listing_title(folder_name, buf_query, new_page, total_str, nil, count_unseen(display_envelopes), buf_sort)

    render_listing_buffer(bufnr, display_envelopes)

    -- Position cursor on selected email and ensure line 1 is at the top.
    -- Neovim may have shifted topline during the native resize before our
    -- handler runs; the listing always fits in the window so topline=1.
    vim.fn.winrestview({ topline = 1 })
    pcall(vim.api.nvim_win_set_cursor, 0, { cursor_line, 0 })

    -- When the page is fully covered by cached envelopes, skip Phase 2.
    -- The cache retains its high-water mark from the last server fetch;
    -- Phase 1 only updates page_size/page, never mutates the cache.
    -- When sparse (cursor near cache edge), fall through to Phase 2
    -- so the server fills the rest of the page.
    if #display_envelopes >= new_page_size then
      perf.stop('resize_listing_total')
      perf.report()
      return
    end

    -- Phase 2: deferred re-fetch (debounced 150ms)
    schedule_phase2_refetch(bufnr)
    perf.stop('resize_listing_total')
    perf.report()
    return
  end

  -- Width-only change (or initial page_size set): re-render for new width
  local display_envelopes = display_slice(envelopes)
  local bufnr = vim.api.nvim_get_current_buf()
  render_listing_buffer(bufnr, display_envelopes)
  vim.fn.winrestview({ topline = 1 })
  perf.stop('resize_listing_total')
  perf.report()
end

--- Cancel any pending resize timer and in-flight resize re-fetch job.
function M.cancel_resize()
  if resize_timer then
    resize_timer:stop()
    resize_timer = nil
  end
  if resize_job then
    resize_generation = resize_generation + 1
    resize_job:kill()
    resize_job = nil
  end
end

--- Clean up all module-local state for buffer teardown.
--- Subsumes cancel_resize() since _cancel_jobs() handles the same timer/job teardown.
function M.cleanup()
  M._cancel_jobs()
  saved_view = nil
  saved_cursor_id = nil
  contact_cache_base = ''
  contact_cache_items = {}
end

--- Set the list envelopes query and refresh.
function M.set_list_envelopes_query()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  local search = require('himalaya.ui.search')
  search.open(function(final_query, new_folder)
    vim.b.himalaya_query = final_query
    if new_folder and new_folder ~= '' then
      vim.b.himalaya_folder = new_folder
      vim.b.himalaya_page = 1
    end
    M.list()
  end, vim.b.himalaya_query or '', folder, account)
end

--- Apply a search preset from config and refresh the listing.
function M.apply_search_preset()
  local presets = config.get().search_presets
  if #presets == 0 then
    vim.notify('No search presets configured', vim.log.levels.INFO)
    return
  end
  vim.ui.select(presets, {
    prompt = 'Search preset:',
    format_item = function(item)
      return item.name .. '  —  ' .. item.query
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.b.himalaya_query = choice.query
    vim.b.himalaya_page = 1
    M.list()
  end)
end

--- Check whether any user-initiated CLI job is in-flight.
--- Used by the sync module to avoid database lock contention.
--- @return boolean
function M.is_busy()
  return fetch_job ~= nil or resize_job ~= nil
end

--- Test-only accessor for mark_envelope_seen.
M._mark_envelope_seen = mark_envelope_seen

--- Test-only accessor for build_cli_query.
M._build_cli_query = build_cli_query

--- Test-only accessors for resize generation state.
function M._get_resize_generation()
  return resize_generation
end
function M._set_resize_generation(n)
  resize_generation = n
end
function M._set_resize_job(j)
  resize_job = j
end
function M._get_resize_job()
  return resize_job
end

--- Open a floating picker to choose sort field and direction, then refresh.
function M.toggle_sort()
  local listing_bufnr = vim.api.nvim_get_current_buf()
  local buf_type = vim.b[listing_bufnr].himalaya_buffer_type
  local fields = { 'date', 'from', 'subject', 'to' }
  local directions = { 'desc', 'asc' }
  local choices = {}
  for _, f in ipairs(fields) do
    for _, d in ipairs(directions) do
      choices[#choices + 1] = f .. ' ' .. d
    end
  end

  local lines = {}
  for i, item in ipairs(choices) do
    local field, dir = item:match('^(%S+)%s+(%S+)$')
    local arrow = dir == 'desc' and '↓' or '↑'
    lines[#lines + 1] = string.format(' %d  %s %s', i, field, arrow)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = 16
  local height = #lines
  local float_win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Sort by ',
    title_pos = 'center',
  })
  vim.wo[float_win].cursorline = true

  local function close()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function pick(nr)
    close()
    local choice = choices[nr]
    vim.b[listing_bufnr].himalaya_sort = choice
    vim.b[listing_bufnr].himalaya_page = 1
    if buf_type == 'thread-listing' then
      require('himalaya.domain.email.thread_listing').list()
    else
      M.list()
    end
  end

  local map_opts = { buffer = buf, noremap = true, silent = true }
  for i = 1, #choices do
    vim.keymap.set('n', tostring(i), function()
      pick(i)
    end, map_opts)
  end
  vim.keymap.set('n', '<Esc>', close, map_opts)
  vim.keymap.set('n', 'q', close, map_opts)
  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(float_win)[1]
    pick(row)
  end, map_opts)
end

local is_seen = flags_util.is_seen

--- Generic: search visible page for matching envelope in given direction.
--- @param predicate function(env): boolean
--- @param direction number  +1 for forward, -1 for backward
--- @param no_match_msg string
local function jump_in_listing(predicate, direction, no_match_msg)
  if not in_listing_buffer() then
    return
  end
  local envelopes = vim.b.himalaya_envelopes
  if not envelopes then
    return
  end
  local display = display_slice(envelopes)
  local buf_lines = vim.api.nvim_buf_line_count(0)
  local total = math.min(#display, buf_lines)
  if total == 0 then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  for i = 1, total do
    local idx = ((cursor - 1 + i * direction) % total) + 1
    if predicate(display[idx]) then
      vim.api.nvim_win_set_cursor(0, { idx, 0 })
      return
    end
  end
  log.info(no_match_msg)
end

--- Jump to the next unseen email in the listing, wrapping around.
function M.jump_to_next_unread()
  if vim.b.himalaya_buffer_type == 'thread-listing' then
    require('himalaya.domain.email.thread_listing').jump_to_next_unread()
    return
  end
  jump_in_listing(is_unseen, 1, 'No unread emails on this page')
end

--- Jump to the previous unseen email in the listing, wrapping around.
function M.jump_to_prev_unread()
  if vim.b.himalaya_buffer_type == 'thread-listing' then
    require('himalaya.domain.email.thread_listing').jump_to_prev_unread()
    return
  end
  jump_in_listing(is_unseen, -1, 'No unread emails on this page')
end

--- Jump to the next read email in the listing, wrapping around.
function M.jump_to_next_read()
  if vim.b.himalaya_buffer_type == 'thread-listing' then
    require('himalaya.domain.email.thread_listing').jump_to_next_read()
    return
  end
  jump_in_listing(is_seen, 1, 'No read emails on this page')
end

--- Jump to the previous read email in the listing, wrapping around.
function M.jump_to_prev_read()
  if vim.b.himalaya_buffer_type == 'thread-listing' then
    require('himalaya.domain.email.thread_listing').jump_to_prev_read()
    return
  end
  jump_in_listing(is_seen, -1, 'No read emails on this page')
end

return M
