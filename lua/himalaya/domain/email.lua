local request = require('himalaya.request')
local log = require('himalaya.log')
local config = require('himalaya.config')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local probe = require('himalaya.domain.email.probe')
local cache = require('himalaya.domain.email.cache')
local perf = require('himalaya.perf')

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

local account_flag = account_state.flag

--- Extract numeric email ID from a listing line.
--- @param line string
--- @return string
function M._get_email_id_from_line(line)
  return line:match('%d+') or ''
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
    table.insert(ids, id)
  end
  return table.concat(ids, ' ')
end

--- Calculate usable buffer width (accounts for number column, fold column, sign column).
--- @return number
function M._bufwidth()
  local width = vim.fn.winwidth(0)
  local numberwidth = math.max(vim.wo.numberwidth, #tostring(vim.fn.line('$')) + 1)
  local numwidth = (vim.wo.number or vim.wo.relativenumber) and numberwidth or 0
  local foldwidth = tonumber(vim.wo.foldcolumn) or 0

  local signwidth = 0
  if vim.wo.signcolumn == 'yes' then
    signwidth = 2
  elseif vim.wo.signcolumn == 'auto' then
    local signs = vim.fn.execute(string.format('sign place buffer=%d', vim.fn.bufnr('')))
    local sign_lines = vim.split(signs, '\n')
    signwidth = #sign_lines > 2 and 2 or 0
  end

  return width - numwidth - foldwidth - signwidth
end

--- Detect whether current buffer is an envelope listing buffer.
--- @return boolean
local function in_listing_buffer()
  local bt = vim.b.himalaya_buffer_type
  return bt == 'listing' or bt == 'thread-listing'
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
  return math.max(1, vim.fn.winheight(0))
end

--- Get the relevant email ID depending on context (listing vs read buffer).
--- @return string
local function context_email_id()
  if in_listing_buffer() then
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
  local buftype = in_listing_buffer() and 'file' or 'edit'
  local display_query = qry == '' and 'all' or qry
  vim.cmd(string.format('silent! %s Himalaya/envelopes [%s] [%s] [page %d⁄%s]', buftype, folder, display_query, page, total_str))
  vim.bo.modifiable = true
  vim.b.himalaya_page = page
  vim.b.himalaya_page_size = page_size
  vim.b.himalaya_query = qry

  local new_offset = fetch_offset or ((page - 1) * page_size)
  if vim.b.himalaya_cache_key ~= cache_key then
    vim.b.himalaya_envelopes = data
    vim.b.himalaya_cache_offset = new_offset
  else
    local merged, merged_offset = cache.merge(
      vim.b.himalaya_envelopes, vim.b.himalaya_cache_offset or 0,
      data, new_offset)
    vim.b.himalaya_envelopes = merged
    vim.b.himalaya_cache_offset = merged_offset
  end
  vim.b.himalaya_cache_key = cache_key

  -- Extract the display page's slice from (possibly larger) fetched data.
  local display_page_start = (page - 1) * page_size
  local data_idx_start = display_page_start - new_offset
  local page_data = data
  if data_idx_start > 0 or #data > page_size then
    page_data = {}
    for i = data_idx_start + 1, math.min(#data, data_idx_start + page_size) do
      page_data[#page_data + 1] = data[i]
    end
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local result = renderer.render(page_data, M._bufwidth())
  -- Set winbar first so page_size() reflects actual visible area
  listing.apply_header(bufnr, result.header)
  -- After winbar is set, visible area may have shrunk — truncate if needed
  local actual_ps = math.max(1, vim.fn.winheight(0))
  local display = page_data
  if #page_data > actual_ps then
    display = {}
    for i = 1, actual_ps do display[i] = page_data[i] end
    local trimmed = {}
    for i = 1, actual_ps do trimmed[i] = result.lines[i] end
    result.lines = trimmed
    vim.b.himalaya_page_size = actual_ps
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
  listing.apply_seen_highlights(bufnr, display)
  vim.b.himalaya_buffer_type = 'listing'
  vim.bo.filetype = 'himalaya-email-listing'
  vim.bo.modified = false
  vim.fn.winrestview({ topline = 1 })
  if saved_cursor_id then
    local target = saved_cursor_id
    saved_cursor_id = nil
    saved_view = nil
    for i, env in ipairs(display) do
      if tostring(env.id) == target then
        pcall(vim.api.nvim_win_set_cursor, 0, {i, 0})
        break
      end
    end
  elseif saved_view then
    vim.fn.winrestview(saved_view)
    saved_view = nil
  else
    vim.cmd('0')
  end

  probe.start(acct_flag, folder, page_size, page, qry, bufnr)
end

--- List envelopes, optionally switching account first.
--- @param account? string
function M.list(account)
  if account then
    account_state.select(account)
    folder_state.set_page(1)
  end
  local acct = account_state.current()
  local folder = folder_state.current()
  local page = folder_state.current_page()
  M.list_with(acct, folder, page, query)
end

--- List envelopes with explicit parameters.
--- @param account string
--- @param folder string
--- @param page number
--- @param qry string
function M.list_with(account, folder, page, qry)
  if resize_timer then
    resize_timer:stop()
    resize_timer = nil
  end
  if resize_job then
    resize_generation = resize_generation + 1
    resize_job:kill()
    resize_job = nil
  end
  -- Kill any in-flight list fetch so its callback never fires.
  fetch_generation = fetch_generation + 1
  local my_gen = fetch_generation
  if fetch_job then fetch_job:kill(); fetch_job = nil end
  -- Cancel any running probe so its database lock is released before the
  -- new CLI fetch.  Without this, rapid page navigation (e.g. gn right
  -- after opening the inbox) hits "could not acquire lock" errors.
  probe.cancel()
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
    on_error = function() fetch_job = nil end,
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
  local ps = page_size()
  local cur_page = vim.b.himalaya_page or 1
  local cache_offset = vim.b.himalaya_cache_offset or 0
  local page_start = (cur_page - 1) * ps
  local idx = math.max(1, page_start - cache_offset + 1)
  local last = math.min(#envelopes, idx + ps - 1)
  if idx == 1 and last == #envelopes then return envelopes end
  local sliced = {}
  for i = idx, last do sliced[#sliced + 1] = envelopes[i] end
  return sliced
end

--- Optimistically mark an envelope as Seen in the listing buffer.
--- Updates the cached envelope data, re-renders the line, and re-applies highlights.
--- @param email_id string
local function mark_envelope_seen(email_id)
  -- Find the visible listing buffer in the current tab.  Searching windows
  -- instead of all buffers avoids picking up a stale flat-listing buffer
  -- left behind when the user switched to thread mode.
  local listing_bufnr, listing_type
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local ok, bt = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_buffer_type')
      if ok and (bt == 'listing' or bt == 'thread-listing') then
        listing_bufnr = bufnr
        listing_type = bt
        break
      end
    end
  end
  if not listing_bufnr then return end

  if listing_type == 'thread-listing' then
    local tl = require('himalaya.domain.email.thread_listing')
    tl._mark_seen(email_id)
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

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(winid) == listing_bufnr then
      vim.api.nvim_win_call(winid, function()
        local renderer = require('himalaya.ui.renderer')
        local listing = require('himalaya.ui.listing')
        local line_count = vim.api.nvim_buf_line_count(listing_bufnr)
        local cur_page = vim.b.himalaya_page or 1
        local ps = vim.b.himalaya_page_size or line_count
        local cache_offset = vim.b.himalaya_cache_offset or 0
        local page_start = (cur_page - 1) * ps
        local idx = math.max(1, page_start - cache_offset + 1)
        local last_idx = math.min(#envelopes, idx + line_count - 1)
        local visible = {}
        for i = idx, last_idx do
          visible[#visible + 1] = envelopes[i]
        end
        local result = renderer.render(visible, M._bufwidth())
        vim.bo[listing_bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(listing_bufnr, 0, -1, false, result.lines)
        listing.apply_header(listing_bufnr, result.header)
        listing.apply_seen_highlights(listing_bufnr, visible)
        vim.bo[listing_bufnr].modifiable = false
      end)
      break
    end
  end
end

--- Read email under cursor.
function M.read()
  M.cancel_resize()
  current_id = get_email_id_under_cursor()
  if current_id == '' or current_id == 'ID' then
    return
  end
  probe.cancel()
  -- Capture listing window synchronously before the async request,
  -- so the callback can reliably reference it even if focus changes.
  local listing_winid = vim.api.nvim_get_current_win()
  local account = account_state.current()
  local folder = folder_state.current()
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
      for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(winid) then
          local buf = vim.api.nvim_win_get_buf(winid)
          local bname = vim.api.nvim_buf_get_name(buf)
          if bname:find('Himalaya/read email', 1, true) then
            vim.api.nvim_set_current_win(winid)
            reused = true
            break
          end
        end
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
end

--- Delete email(s). Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.delete(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = get_email_id_under_cursor()
  else
    ids = current_id
  end

  local cfg = config.get()
  if cfg.always_confirm then
    local answer = vim.fn.inputdialog(string.format('Delete email(s) %s? [Y/n] ', ids), '', '_cancel_')
    vim.cmd('redraw | echo')
    if answer == '_cancel_' or (answer ~= '' and answer:lower() ~= 'y') then
      return
    end
  end

  local cursor_line = vim.fn.line('.')
  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'message delete %s --folder %s %s',
    args = { account_flag(account), folder, ids },
    msg = 'Deleting email',
    on_data = function()
      saved_view = vim.fn.winsaveview()
      refresh_listing(account, folder, { restore_cursor_line = cursor_line })
    end,
  })
end

--- Copy email(s) to target folder. Supports visual range via first_line/last_line.
--- @param target_folder string
--- @param first_line? number
--- @param last_line? number
function M.copy(target_folder, first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = get_email_id_under_cursor()
  else
    ids = current_id
  end

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
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
end

--- Move email(s) to target folder (with confirmation prompt). Supports visual range via first_line/last_line.
--- @param target_folder string
--- @param first_line? number
--- @param last_line? number
function M.move(target_folder, first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = get_email_id_under_cursor()
  else
    ids = current_id
  end

  local cfg = config.get()
  if cfg.always_confirm then
    local answer = vim.fn.inputdialog(string.format('Move email(s) %s? [Y/n] ', ids), '', '_cancel_')
    vim.cmd('redraw | echo')
    if answer == '_cancel_' or (answer ~= '' and answer:lower() ~= 'y') then
      return
    end
  end

  local cursor_line = vim.fn.line('.')
  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
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

--- Add flags to email(s). Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.flag_add(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = get_email_id_under_cursor()
  else
    ids = current_id
  end

  local flags = vim.fn.input('Flag to add: ', '', 'custom,himalaya#domain#email#flags#complete')
  vim.cmd('redraw | echo')

  local flagsarr = vim.split(vim.trim(flags), '%s+')
  if #flagsarr == 0 or (#flagsarr == 1 and flagsarr[1] == '') then
    return
  end

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'flag add %s --folder %s %s %s',
    args = { account_flag(account), folder, flags, ids },
    msg = 'Adding flags: ' .. flags .. ' to email',
    on_data = function()
      refresh_listing(account, folder)
    end,
  })
end

--- Remove flags from email(s). Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.flag_remove(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = get_email_id_under_cursor()
  else
    ids = current_id
  end

  local flags = vim.fn.input('Flag to remove: ', '', 'custom,himalaya#domain#email#flags#complete')
  vim.cmd('redraw | echo')

  local flagsarr = vim.split(vim.trim(flags), '%s+')
  if #flagsarr == 0 or (#flagsarr == 1 and flagsarr[1] == '') then
    return
  end

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'flag remove %s --folder %s %s %s',
    args = { account_flag(account), folder, flags, ids },
    msg = 'Removing flags:' .. flags .. ' from email',
    on_data = function()
      refresh_listing(account, folder)
    end,
  })
end

--- Mark email(s) as seen. Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.mark_seen(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = get_email_id_under_cursor()
  else
    ids = current_id
  end

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'flag add %s --folder %s Seen %s',
    args = { account_flag(account), folder, ids },
    msg = 'Marking as seen',
    on_data = function()
      saved_view = vim.fn.winsaveview()
      refresh_listing(account, folder)
    end,
  })
end

--- Mark email(s) as unseen. Supports visual range via first_line/last_line.
--- @param first_line? number
--- @param last_line? number
function M.mark_unseen(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = get_email_id_under_cursor()
  else
    ids = current_id
  end

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'flag remove %s --folder %s Seen %s',
    args = { account_flag(account), folder, ids },
    msg = 'Marking as unseen',
    on_data = function()
      saved_view = vim.fn.winsaveview()
      refresh_listing(account, folder)
    end,
  })
end

--- Download attachments for current email.
function M.download_attachments()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = context_email_id()
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
    local cfg = config.get()
    local cmd = cfg.complete_contact_cmd:gsub('%%s', base)
    local output = vim.fn.system(cmd)
    local lines = vim.split(output, '\n', { trimempty = true })
    local items = {}
    for _, line in ipairs(lines) do
      table.insert(items, M._line_to_complete_item(line))
    end
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

  -- Check if listing is background (email being read).
  local reading = false
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) then
      local bname = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid))
      if bname:find('Himalaya/read email', 1, true) then
        reading = true
        break
      end
    end
  end

  local new_page_size = page_size()
  local old_page_size = vim.b.himalaya_page_size

  if not old_page_size then
    vim.b.himalaya_page_size = new_page_size
  elseif reading or new_page_size ~= old_page_size then
    -- Page-boundary logic (shared by reading truncation and Phase 1).
    -- Reading truncation uses the same overlap computation but skips Phase 2.
    local old_page = vim.b.himalaya_page or 1
    local cache_start = vim.b.himalaya_cache_offset or ((old_page - 1) * old_page_size)
    local cursor_row = math.max(1, math.min(vim.fn.line('.'), #envelopes))
    -- Buffer rows may not match cache indices (e.g., after Phase 1
    -- truncation or Phase 2 re-fetch). Extract the email ID from the
    -- current buffer line and find its position in the cache.
    local cursor_line_text = vim.api.nvim_buf_get_lines(0, cursor_row - 1, cursor_row, false)[1] or ''
    local cursor_email_id = M._get_email_id_from_line(cursor_line_text)
    if cursor_email_id ~= '' then
      for i, env in ipairs(envelopes) do
        if tostring(env.id) == cursor_email_id then cursor_row = i; break end
      end
    end
    local selected_global = cache_start + cursor_row - 1
    local new_page = math.floor(selected_global / new_page_size) + 1
    local new_page_start = (new_page - 1) * new_page_size
    local new_page_end = new_page_start + new_page_size

    local overlap_start = math.max(cache_start, new_page_start)
    local overlap_end = math.min(cache_start + #envelopes, new_page_end)

    local display_envelopes = {}
    for i = overlap_start - cache_start + 1, overlap_end - cache_start do
      table.insert(display_envelopes, envelopes[i])
    end
    local cursor_line = selected_global - overlap_start + 1

    -- Update buffer state
    folder_state.set_page(new_page)
    vim.b.himalaya_page = new_page
    vim.b.himalaya_page_size = new_page_size

    -- Render
    local renderer = require('himalaya.ui.renderer')
    local listing = require('himalaya.ui.listing')
    local bufnr = vim.api.nvim_get_current_buf()
    local folder_name = folder_state.current()
    local buf_query = vim.b.himalaya_query or ''
    local acct_flag = account_flag(account_state.current())
    local cache_key = acct_flag .. '\0' .. folder_name .. '\0' .. buf_query
    local total_str = probe.total_pages_str(cache_key, new_page_size)
    local display_query = buf_query == '' and 'all' or buf_query
    vim.cmd(string.format('silent! file Himalaya/envelopes [%s] [%s] [page %d⁄%s]', folder_name, display_query, new_page, total_str))

    local result = renderer.render(display_envelopes, M._bufwidth())
    vim.bo.modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
    listing.apply_header(bufnr, result.header)
    listing.apply_seen_highlights(bufnr, display_envelopes)
    vim.bo.modifiable = false

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
    if resize_timer then resize_timer:stop() end
    if resize_job then resize_generation = resize_generation + 1; resize_job:kill(); resize_job = nil end

    resize_timer = vim.uv.new_timer()
    resize_timer:start(150, 0, vim.schedule_wrap(function()
      resize_timer = nil
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      -- Find the window still showing the listing buffer
      local listing_win = nil
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
          listing_win = winid
          break
        end
      end
      if not listing_win then return end
      -- Read cursor and page size from the listing buffer (not the window,
      -- since nvim_win_get_height may include the winbar row while
      -- page_size()/winheight(0) used in Phase 1 excludes it).
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
    perf.stop("resize_listing_total")
    perf.report()
    return
  end

  -- Width-only change (or initial page_size set): re-render for new width
  local display_envelopes = display_slice(envelopes)
  local renderer = require('himalaya.ui.renderer')
  local listing = require('himalaya.ui.listing')
  local bufnr = vim.api.nvim_get_current_buf()
  local result = renderer.render(display_envelopes, M._bufwidth())
  vim.bo.modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
  listing.apply_header(bufnr, result.header)
  listing.apply_seen_highlights(bufnr, display_envelopes)
  vim.bo.modifiable = false
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
