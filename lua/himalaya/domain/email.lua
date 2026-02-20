local request = require('himalaya.request')
local log = require('himalaya.log')
local config = require('himalaya.config')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local probe = require('himalaya.domain.email.probe')
local cache = require('himalaya.domain.email.cache')
local paging = require('himalaya.domain.email.paging')
local perf = require('himalaya.perf')
local job = require('himalaya.job')
local win = require('himalaya.ui.win')

local M = {}

-- Module-local state (mirrors s:id, s:draft, s:query in VimScript)
local current_id = ''
local query = ''
local saved_view = nil
local saved_cursor_id = nil   -- email ID for cursor restoration after re-fetch
local resize_timer = nil      -- vim.uv timer for debounced re-fetch
local resize_job = nil        -- in-flight resize re-fetch job handle
local resize_generation = 0   -- incremented on kill; stale callbacks check this
local fetch_generation = 0    -- incremented on each list_with(); stale callbacks bail out
local fetch_job = nil         -- in-flight list_with job handle
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
--- @return string
local function get_email_id_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local id = M._get_email_id_from_line(line)
  if id == '' then
    error('email not found')
  end
  return id
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
  if #ids == 0 then
    error('no emails selected')
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
  listing.apply_seen_highlights(bufnr, envelopes)
  vim.bo[bufnr].modifiable = false
  return result
end

--- Update the buffer title with folder, query, page, and total info.
--- @param folder string
--- @param qry string
--- @param pg number
--- @param total_str string
--- @param bufcmd? string  vim command to set name ('file' or 'edit', defaults to 'file')
local function update_listing_title(folder, qry, pg, total_str, bufcmd)
  bufcmd = bufcmd or 'file'
  local display_query = qry == '' and 'all' or qry
  vim.cmd(string.format('silent! %s Himalaya/envelopes [%s] [%s] [page %d⁄%s]', bufcmd, folder, display_query, pg, total_str))
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
      pcall(vim.api.nvim_win_set_cursor, 0, {idx, 0})
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
  if vim.b.himalaya_buffer_type == 'thread-listing' then
    if opts.restore_cursor_line then
      require('himalaya.domain.email.thread_listing').list(nil, { restore_cursor_line = opts.restore_cursor_line })
    else
      local cursor_id = get_email_id_under_cursor()
      require('himalaya.domain.email.thread_listing').list(nil, { restore_email_id = cursor_id })
    end
  else
    M.list_with(account, folder, folder_state.current_page(), query)
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
    return current_id
  end
end

--- Resolve the target email ID(s) for a mutating operation.
--- In listing: uses cursor line (or visual range); in read buffer: uses current_id.
--- @param first_line? number
--- @param last_line? number
--- @return string space-separated ID(s)
local function resolve_target_ids(first_line, last_line)
  if in_listing_buffer() and first_line and last_line then
    return get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    return get_email_id_under_cursor()
  else
    return current_id
  end
end

--- Internal callback for list_with — populates the envelope listing buffer.
--- @param fetch_offset? number actual CLI data offset (defaults to (page-1)*page_size)
local function on_list_with(account, folder, page, page_size, qry, data, fetch_offset)
  local acct_flag = account_flag(account)
  probe.reset_if_changed(acct_flag, folder, qry)

  local cache_key = acct_flag .. '\0' .. folder .. '\0' .. qry
  probe.set_total_from_data(cache_key, page, page_size, #data)
  local total_str = probe.total_pages_str(cache_key, page_size)

  local renderer = require('himalaya.ui.renderer')
  local listing = require('himalaya.ui.listing')
  local bufnr = vim.api.nvim_get_current_buf()
  local bufcmd = in_listing_buffer() and 'file' or 'edit'
  update_listing_title(folder, qry, page, total_str, bufcmd)
  vim.bo[bufnr].modifiable = true
  vim.b[bufnr].himalaya_page = page
  vim.b[bufnr].himalaya_page_size = page_size
  vim.b[bufnr].himalaya_query = qry

  local new_offset = fetch_offset or ((page - 1) * page_size)
  if vim.b[bufnr].himalaya_cache_key ~= cache_key then
    vim.b[bufnr].himalaya_envelopes = data
    vim.b[bufnr].himalaya_cache_offset = new_offset
  else
    local merged, merged_offset = cache.merge(
      vim.b[bufnr].himalaya_envelopes, vim.b[bufnr].himalaya_cache_offset or 0,
      data, new_offset)
    vim.b[bufnr].himalaya_envelopes = merged
    vim.b[bufnr].himalaya_cache_offset = merged_offset
  end
  vim.b[bufnr].himalaya_cache_key = cache_key

  local page_data = paging.fetch_page_slice(data, page, page_size, new_offset)

  local result = renderer.render(page_data, M._bufwidth())
  -- Set winbar first so page_size() reflects actual visible area
  listing.apply_header(bufnr, result.header)
  -- After winbar is set, visible area may have shrunk — truncate if needed
  local actual_ps = listing.effective_page_size()
  local display = page_data
  if #page_data > actual_ps then
    display = {}
    for i = 1, actual_ps do display[i] = page_data[i] end
    local trimmed = {}
    for i = 1, actual_ps do trimmed[i] = result.lines[i] end
    result.lines = trimmed
    vim.b[bufnr].himalaya_page_size = actual_ps
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
  listing.apply_seen_highlights(bufnr, display)
  vim.b[bufnr].himalaya_buffer_type = 'listing'
  vim.bo[bufnr].filetype = 'himalaya-email-listing'
  vim.bo[bufnr].modified = false
  vim.fn.winrestview({ topline = 1 })
  restore_cursor(display)

  probe.start(acct_flag, folder, page_size, page, qry, bufnr)
end

--- List envelopes, optionally switching account first.
--- @param account? string
--- @param opts? table  Optional: { restore_email_id = string }
function M.list(account, opts)
  opts = opts or {}
  if account then
    account_state.select(account)
    folder_state.set_page(1)
  end
  if opts.restore_email_id then
    saved_cursor_id = opts.restore_email_id
  end
  local acct = account_state.current()
  local folder = folder_state.current()
  local page = folder_state.current_page()
  M.list_with(acct, folder, page, query)
end

--- Kill all in-flight fetch/resize jobs synchronously.
--- Called before any new CLI command to avoid database lock contention.
function M._cancel_jobs()
  fetch_generation = fetch_generation + 1
  if fetch_job then job.kill_and_wait(fetch_job); fetch_job = nil end
  if resize_timer then resize_timer:stop(); resize_timer = nil end
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
--- @param qry string
function M.list_with(account, folder, page, qry)
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
  local cli_page = math.ceil(page / 2)
  local fetch_offset = (cli_page - 1) * fetch_ps
  fetch_job = request.json({
    cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
    args = {
      folder,
      account_flag(account),
      fetch_ps,
      cli_page,
      qry,
    },
    msg = string.format('Fetching %s envelopes', folder),
    is_stale = function() return my_gen ~= fetch_generation end,
    on_error = function()
      fetch_job = nil
      -- Clear loading indicator on failure
      if in_listing_buffer() and vim.wo.winbar:find('loading') then
        vim.wo.winbar = ''
      end
    end,
    on_data = function(data)
      fetch_job = nil
      on_list_with(account, folder, page, ps, qry, data, fetch_offset)
    end,
  })
end

--- Slice cached envelopes to fit the current window height.
--- @param envelopes table[] full cached envelope list
--- @return table[] display subset
local function display_slice(envelopes)
  return paging.cache_slice(envelopes, vim.b.himalaya_page or 1, page_size(), vim.b.himalaya_cache_offset or 0)
end

--- Optimistically mark an envelope as Seen in the listing buffer.
--- Updates the cached envelope data, re-renders the line, and re-applies highlights.
--- @param email_id string
local function mark_envelope_seen(email_id)
  -- Find the visible listing buffer in the current tab.  Searching windows
  -- instead of all buffers avoids picking up a stale flat-listing buffer
  -- left behind when the user switched to thread mode.
  local listing_winid, listing_bufnr, listing_type = win.find_by_buftype({ 'listing', 'thread-listing' })
  if not listing_winid then return end

  if listing_type == 'thread-listing' then
    local tl = require('himalaya.domain.email.thread_listing')
    tl.mark_seen_optimistic(email_id)
    return
  end

  local ok, envelopes = pcall(vim.api.nvim_buf_get_var, listing_bufnr, 'himalaya_envelopes')
  if not (ok and envelopes) then return end

  for _, env in ipairs(envelopes) do
    if tostring(env.id) == tostring(email_id) then
      local flags = env.flags or {}
      for _, f in ipairs(flags) do
        if f == 'Seen' then return end
      end
      table.insert(flags, 'Seen')
      env.flags = flags
      break
    end
  end

  vim.api.nvim_buf_set_var(listing_bufnr, 'himalaya_envelopes', envelopes)

  if listing_winid then
    vim.api.nvim_win_call(listing_winid, function()
      local line_count = vim.api.nvim_buf_line_count(listing_bufnr)
      local cur_page = vim.b.himalaya_page or 1
      local ps = vim.b.himalaya_page_size or line_count
      local cache_offset = vim.b.himalaya_cache_offset or 0
      local visible = paging.cache_slice(envelopes, cur_page, ps, cache_offset, line_count)
      render_listing_buffer(listing_bufnr, visible)
    end)
  end
end

--- Read email under cursor.
function M.read()
  M.cancel_resize()
  current_id = get_email_id_under_cursor()
  if current_id == '' or current_id == 'ID' then
    return
  end
  -- Capture listing window synchronously before the async request,
  -- so the callback can reliably reference it even if focus changes.
  local listing_winid = vim.api.nvim_get_current_win()
  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel(function()
    request.plain({
      cmd = 'message read %s --folder %s %s',
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
        vim.api.nvim_open_win(email_buf, true, { split = 'below' })
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

      vim.cmd(string.format('silent! file Himalaya/read email [%s]', current_id))
      vim.bo.filetype = 'himalaya-email-reading'
      vim.bo.modified = false
      vim.cmd('0')
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
    local answer = vim.fn.inputdialog(string.format('Delete %d %s? [Y/n] ', id_count, id_count == 1 and 'email' or 'emails'), '', '_cancel_')
    vim.cmd('redraw | echo')
    if answer == '_cancel_' or (answer ~= '' and answer:lower() ~= 'y') then
      return
    end
  end

  local cursor_line = vim.fn.line('.')
  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel(function()
    request.plain({
      cmd = 'message delete %s --folder %s %s',
      args = { account_flag(account), folder, ids },
      msg = 'Deleting email',
      on_data = function()
        saved_view = vim.fn.winsaveview()
        refresh_listing(account, folder, { restore_cursor_line = cursor_line })
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

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel(function()
    request.plain({
      cmd = 'message copy %s --folder %s %s %s',
      args = {
        account_flag(account),
        folder,
        target_folder,
        ids,
      },
      msg = 'Copying email',
      on_data = function()
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
    local answer = vim.fn.inputdialog(string.format('Move %d %s? [Y/n] ', id_count, id_count == 1 and 'email' or 'emails'), '', '_cancel_')
    vim.cmd('redraw | echo')
    if answer == '_cancel_' or (answer ~= '' and answer:lower() ~= 'y') then
      return
    end
  end

  local cursor_line = vim.fn.line('.')
  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel(function()
    request.plain({
      cmd = 'message move %s --folder %s %s %s',
      args = {
        account_flag(account),
        folder,
        target_folder,
        ids,
      },
      msg = 'Moving email',
      on_data = function()
        refresh_listing(account, folder, { restore_cursor_line = cursor_line })
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
  if not in_listing_buffer() then return {} end
  local ok, envelopes = pcall(vim.api.nvim_buf_get_var, 0, 'himalaya_envelopes')
  if not (ok and envelopes) then return {} end
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
    if not flag then return end
    local account = account_state.current()
    local folder = folder_state.current()
    probe.cancel(function()
      request.plain({
        cmd = 'flag add %s --folder %s %s %s',
        args = { account_flag(account), folder, flag, ids },
        msg = 'Adding flag: ' .. flag,
        on_data = function()
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
    if not flag then return end
    local account = account_state.current()
    local folder = folder_state.current()
    probe.cancel(function()
      request.plain({
        cmd = 'flag remove %s --folder %s %s %s',
        args = { account_flag(account), folder, flag, ids },
        msg = 'Removing flag: ' .. flag,
        on_data = function()
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

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel(function()
    request.plain({
      cmd = 'flag add %s --folder %s Seen %s',
      args = { account_flag(account), folder, ids },
      msg = 'Marking as seen',
      on_data = function()
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

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel(function()
    request.plain({
      cmd = 'flag remove %s --folder %s Seen %s',
      args = { account_flag(account), folder, ids },
      msg = 'Marking as unseen',
      on_data = function()
        saved_view = vim.fn.winsaveview()
        refresh_listing(account, folder)
      end,
    })
  end)
end

--- Download attachments for current email.
function M.download_attachments()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = M.context_email_id()
  request.plain({
    cmd = 'attachment download %s --folder %s %s',
    args = { account_flag(account), folder, id },
    msg = 'Downloading attachments',
    on_data = function(data)
      log.info(data)
    end,
  })
end

--- Open current email in browser.
function M.open_browser()
  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message export %s --folder %s --open %s',
    args = { account_flag(account), folder, current_id },
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
    if #contact_cache_items > 0 and #base >= #contact_cache_base
        and base:sub(1, #contact_cache_base) == contact_cache_base then
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
    local cmd = cfg.complete_contact_cmd:gsub('%%s', base)
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
  if resize_timer then resize_timer:stop() end
  if resize_job then resize_generation = resize_generation + 1; resize_job:kill(); resize_job = nil end

  resize_timer = vim.uv.new_timer()
  resize_timer:start(150, 0, vim.schedule_wrap(function()
    resize_timer = nil
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    -- Find the window still showing the listing buffer
    local listing_win = win.find_by_bufnr(bufnr)
    if not listing_win then return end
    local cursor_ln = vim.api.nvim_win_get_cursor(listing_win)[1]
    local cursor_id = M._get_email_id_from_line(
      vim.api.nvim_buf_get_lines(bufnr, cursor_ln - 1, cursor_ln, false)[1] or '')
    local account = account_state.current()
    local folder_cur = folder_state.current()
    local cur_query = vim.b[bufnr].himalaya_query or ''
    local cur_page = vim.b[bufnr].himalaya_page or 1
    local ps = vim.b[bufnr].himalaya_page_size
    resize_generation = resize_generation + 1
    local my_gen = resize_generation
    resize_job = request.json({
      cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
      args = { folder_cur, account_flag(account), ps, cur_page, cur_query },
      msg = 'Refetching page after resize',
      silent = true,
      is_stale = function() return my_gen ~= resize_generation end,
      on_data = function(data)
        resize_job = nil
        if not vim.api.nvim_win_is_valid(listing_win) then return end
        saved_cursor_id = cursor_id
        vim.api.nvim_win_call(listing_win, function()
          on_list_with(account, folder_cur, cur_page, ps, cur_query, data)
        end)
      end,
    })
  end))
end

--- Handle listing window resize: two-phase overlap display + deferred re-fetch.
--- Phase 1 synchronously renders the overlap between old cache and new page
--- boundaries (jitter-free). Phase 2 debounces a full re-fetch after 150ms.
function M.resize_listing()
  if not in_listing_buffer() then return end
  local envelopes = vim.b.himalaya_envelopes
  if not envelopes then return end

  -- Guard: if the buffer belongs to a different folder/account/query than the
  -- current state, its page data is stale.  This happens when a folder switch
  -- (e.g. INBOX → Drafts) triggers an async fetch and WinResized fires before
  -- the new data arrives.  Without this guard, resize_listing() would compute
  -- a page number from the old folder's buffer vars and clobber
  -- folder_state.current_page(), causing "page N out of bounds" on the next
  -- navigation action.
  local buf_cache_key = vim.b.himalaya_cache_key
  if buf_cache_key then
    local current_key = account_flag(account_state.current())
      .. '\0' .. folder_state.current()
      .. '\0' .. (vim.b.himalaya_query or '')
    if buf_cache_key ~= current_key then
      return
    end
  end

  perf.reset()
  perf.start("resize_listing_total")

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
    local display_envelopes = paging.extract_range(envelopes, cache_start, resize_info.overlap_start, resize_info.overlap_end)
    local cursor_line = resize_info.cursor_line

    -- Update buffer state
    folder_state.set_page(new_page)
    vim.b.himalaya_page = new_page
    vim.b.himalaya_page_size = new_page_size

    -- Render
    local bufnr = vim.api.nvim_get_current_buf()
    local folder_name = folder_state.current()
    local buf_query = vim.b.himalaya_query or ''
    local acct_flag = account_flag(account_state.current())
    local cache_key = acct_flag .. '\0' .. folder_name .. '\0' .. buf_query
    local total_str = probe.total_pages_str(cache_key, new_page_size)
    update_listing_title(folder_name, buf_query, new_page, total_str)

    render_listing_buffer(bufnr, display_envelopes)

    -- Position cursor on selected email and ensure line 1 is at the top.
    -- Neovim may have shifted topline during the native resize before our
    -- handler runs; the listing always fits in the window so topline=1.
    vim.fn.winrestview({ topline = 1 })
    pcall(vim.api.nvim_win_set_cursor, 0, {cursor_line, 0})

    -- When the page is fully covered by cached envelopes, skip Phase 2.
    -- The cache retains its high-water mark from the last server fetch;
    -- Phase 1 only updates page_size/page, never mutates the cache.
    -- When sparse (cursor near cache edge), fall through to Phase 2
    -- so the server fills the rest of the page.
    if #display_envelopes >= new_page_size then
      perf.stop("resize_listing_total")
      perf.report()
      return
    end

    -- Phase 2: deferred re-fetch (debounced 150ms)
    schedule_phase2_refetch(bufnr)
    perf.stop("resize_listing_total")
    perf.report()
    return
  end

  -- Width-only change (or initial page_size set): re-render for new width
  local display_envelopes = display_slice(envelopes)
  local bufnr = vim.api.nvim_get_current_buf()
  render_listing_buffer(bufnr, display_envelopes)
  vim.fn.winrestview({ topline = 1 })
  perf.stop("resize_listing_total")
  perf.report()
end

--- Cancel any pending resize timer and in-flight resize re-fetch job.
function M.cancel_resize()
  if resize_timer then resize_timer:stop(); resize_timer = nil end
  if resize_job then resize_generation = resize_generation + 1; resize_job:kill(); resize_job = nil end
end

--- Set the list envelopes query and refresh.
function M.set_list_envelopes_query()
  local search = require('himalaya.ui.search')
  search.open(function(final_query, folder)
    query = final_query
    if folder and folder ~= '' then
      folder_state.set(folder)
    end
    M.list()
  end, query, folder_state.current())
end

--- Accessor for current_id (used by compose module).
function M._get_current_id() return current_id end

--- Test-only accessor for mark_envelope_seen.
M._mark_envelope_seen = mark_envelope_seen

--- Test-only accessors for resize generation state.
function M._get_resize_generation() return resize_generation end
function M._set_resize_generation(n) resize_generation = n end
function M._set_resize_job(j) resize_job = j end
function M._get_resize_job() return resize_job end

return M
