local request = require('himalaya.request')
local log = require('himalaya.log')
local config = require('himalaya.config')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local probe = require('himalaya.domain.email.probe')

local M = {}

-- Module-local state (mirrors s:id, s:draft, s:query in VimScript)
local current_id = ''
local draft = ''
local query = ''
local saved_view = nil
local saved_cursor_id = nil   -- email ID for cursor restoration after re-fetch
local resize_timer = nil      -- vim.uv timer for debounced re-fetch
local resize_job = nil        -- in-flight resize re-fetch job handle

--- Return '--account <name>' when account is set, or '' to let CLI use its default.
--- @param account string
--- @return string
local function account_flag(account)
  if account == '' then
    return ''
  end
  return '--account ' .. (account)
end

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
  return vim.b.himalaya_buffer_type == 'listing'
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

--- Set buffer content, replacing carriage returns and trailing blank line.
--- @param content string
local function set_buffer_content(content)
  vim.bo.modifiable = true
  vim.cmd('silent! %d')
  local lines = vim.split(content:gsub('\r', ''), '\n')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  -- Remove trailing empty line (matches VimScript `$d`)
  local last = vim.api.nvim_buf_line_count(0)
  if last > 1 and vim.api.nvim_buf_get_lines(0, last - 1, last, false)[1] == '' then
    vim.api.nvim_buf_set_lines(0, last - 1, last, false, {})
  end
end

--- Internal callback for list_with — populates the envelope listing buffer.
local function on_list_with(account, folder, page, page_size, qry, data)
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
  vim.b.himalaya_envelopes = data
  vim.b.himalaya_page = page
  vim.b.himalaya_page_size = page_size
  vim.b.himalaya_query = qry
  vim.b.himalaya_cache_offset = (page - 1) * page_size
  local bufnr = vim.api.nvim_get_current_buf()
  local result = renderer.render(data, M._bufwidth())
  -- Set winbar first so page_size() reflects actual visible area
  listing.apply_header(bufnr, result.header)
  -- After winbar is set, visible area may have shrunk — truncate if needed
  local actual_ps = math.max(1, vim.fn.winheight(0))
  local display = data
  if #data > actual_ps then
    display = {}
    for i = 1, actual_ps do display[i] = data[i] end
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
    resize_job:kill()
    resize_job = nil
  end
  local ps = page_size()
  -- On first load the winbar hasn't been set yet, so winheight still
  -- includes that row.  Reserve one line for the header winbar.
  if vim.wo.winbar == '' then
    ps = math.max(1, ps - 1)
  end
  request.json({
    cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
    args = {
      folder,
      account_flag(account),
      ps,
      page,
      qry,
    },
    msg = string.format('Fetching %s envelopes', folder),
    on_data = function(data)
      on_list_with(account, folder, page, ps, qry, data)
    end,
  })
end

--- Slice cached envelopes to fit the current window height.
--- @param envelopes table[] full cached envelope list
--- @return table[] display subset
local function display_slice(envelopes)
  local ps = page_size()
  if #envelopes <= ps then
    return envelopes
  end
  local sliced = {}
  for i = 1, ps do
    sliced[i] = envelopes[i]
  end
  return sliced
end

--- Optimistically mark an envelope as Seen in the listing buffer.
--- Updates the cached envelope data, re-renders the line, and re-applies highlights.
--- @param email_id string
local function mark_envelope_seen(email_id)
  local listing_bufnr
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local ok, bt = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_buffer_type')
      if ok and bt == 'listing' then
        listing_bufnr = bufnr
        break
      end
    end
  end
  if not listing_bufnr then return end

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
        local visible = {}
        for i = 1, math.min(line_count, #envelopes) do
          visible[i] = envelopes[i]
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

--- Internal: open a write/reply/forward buffer with template content.
--- @param msg string buffer name suffix
--- @param content string template content
local function open_write_buffer(msg, content)
  local bufname = string.format('Himalaya/%s', msg)
  if msg == 'write' then
    vim.cmd(string.format('silent! botright new %s', bufname))
  end
  if vim.fn.winnr('$') == 1 then
    vim.cmd(string.format('silent! botright split %s', bufname))
  else
    vim.cmd(string.format('silent! edit %s', bufname))
  end
  set_buffer_content(content)
  vim.bo.filetype = 'himalaya-email-writing'
  vim.bo.modified = false
  vim.cmd('0')
end

--- Compose a new email. If template is provided, use it; otherwise fetch from CLI.
--- @param template? string
function M.write(template)
  local account = account_state.current()
  if template then
    open_write_buffer('edit', template)
  else
    request.plain({
      cmd = 'template write %s',
      args = { account_flag(account) },
      msg = 'Fetching new template',
      on_data = function(data)
        open_write_buffer('write', data)
      end,
    })
  end
end

--- Reply to current email.
function M.reply()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = context_email_id()
  request.plain({
    cmd = 'template reply %s --folder %s %s',
    args = { account_flag(account), folder, id },
    msg = 'Fetching reply template',
    on_data = function(data)
      open_write_buffer(string.format('reply [%s]', id), data)
    end,
  })
end

--- Reply-all to current email.
function M.reply_all()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = context_email_id()
  request.plain({
    cmd = 'template reply %s --folder %s --all %s',
    args = { account_flag(account), folder, id },
    msg = 'Fetching reply all template',
    on_data = function(data)
      open_write_buffer(string.format('reply all [%s]', id), data)
    end,
  })
end

--- Forward current email.
function M.forward()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = context_email_id()
  request.plain({
    cmd = 'template forward %s --folder %s %s',
    args = { account_flag(account), folder, id },
    msg = 'Fetching forward template',
    on_data = function(data)
      open_write_buffer(string.format('forward [%s]', id), data)
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
    local saved_cmdheight = vim.o.cmdheight
    vim.o.cmdheight = math.max(saved_cmdheight, 2)
    local choice = vim.fn.confirm(string.format('Delete email(s) %s?', ids), '&Yes\n&No', 1)
    vim.o.cmdheight = saved_cmdheight
    if choice ~= 1 then
      return
    end
  end

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'message delete %s --folder %s %s',
    args = { account_flag(account), folder, ids },
    msg = 'Deleting email',
    on_data = function()
      saved_view = vim.fn.winsaveview()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Copy email to target folder.
--- @param target_folder string
function M.copy(target_folder)
  local id = context_email_id()
  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'message copy %s --folder %s %s %s',
    args = {
      account_flag(account),
      folder,
      target_folder,
      id,
    },
    msg = 'Copying email',
    on_data = function()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Move email to target folder (with confirmation prompt).
--- @param target_folder string
function M.move(target_folder)
  local id = context_email_id()

  local cfg = config.get()
  if cfg.always_confirm then
    local saved_cmdheight = vim.o.cmdheight
    vim.o.cmdheight = math.max(saved_cmdheight, 2)
    local choice = vim.fn.confirm(string.format('Move email %s?', id), '&Yes\n&No', 1)
    vim.o.cmdheight = saved_cmdheight
    if choice ~= 1 then
      return
    end
  end

  local account = account_state.current()
  local folder = folder_state.current()
  probe.cancel()
  request.plain({
    cmd = 'message move %s --folder %s %s %s',
    args = {
      account_flag(account),
      folder,
      target_folder,
      id,
    },
    msg = 'Moving email',
    on_data = function()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Open folder picker then copy email to selected folder.
function M.select_folder_then_copy()
  local folder_domain = require('himalaya.domain.folder')
  folder_domain.open_picker(M.copy)
end

--- Open folder picker then move email to selected folder.
function M.select_folder_then_move()
  local folder_domain = require('himalaya.domain.folder')
  folder_domain.open_picker(M.move)
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
      M.list_with(account, folder, folder_state.current_page(), query)
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
      M.list_with(account, folder, folder_state.current_page(), query)
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
      M.list_with(account, folder, folder_state.current_page(), query)
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
      M.list_with(account, folder, folder_state.current_page(), query)
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

--- Save current buffer content as draft.
function M.save_draft()
  draft = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n'
  vim.cmd('redraw')
  log.info('Save draft [OK]')
  vim.bo.modified = false
end

--- Process draft: prompt for (s)end, (d)raft, (q)uit, (c)ancel.
function M.process_draft()
  local ok, err = pcall(function()
    local account = account_state.current()
    local folder = folder_state.current()

    while true do
      local choice = vim.fn.input('(s)end, (d)raft, (q)uit or (c)ancel? ')
      choice = choice:lower():sub(1, 1)
      vim.cmd('redraw | echo')

      if choice == 's' then
        local draft_file = vim.fn.tempname()
        vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), draft_file)

        request.plain({
          cmd = 'template send %s < %s',
          args = { account_flag(account), draft_file },
          msg = 'Sending email',
          on_data = function()
            vim.fn.delete(draft)
          end,
        })

        request.plain({
          cmd = 'flag add %s --folder %s answered %s',
          args = { account_flag(account), folder, current_id },
          msg = 'Adding answered flag',
          on_data = function()
            vim.fn.delete(draft_file)
          end,
        })
        return
      elseif choice == 'd' then
        local draft_file = vim.fn.tempname()
        vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), draft_file)
        request.plain({
          cmd = 'template save %s --folder drafts < %s',
          args = { account_flag(account), draft_file },
          msg = 'Saving draft',
          on_data = function()
            vim.fn.delete(draft_file)
          end,
        })
        return
      elseif choice == 'q' then
        return
      elseif choice == 'c' then
        local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n'
        M.write(content)
        error('Prompt:Interrupt')
      end
    end
  end)

  if not ok then
    if type(err) == 'string' and err:find(':Interrupt$') then
      -- Interrupted — this is expected for cancel
    else
      log.err(tostring(err))
    end
  end
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
    -- After reading truncation, buffer rows don't match cache indices.
    -- Use saved envelope ID to find the correct cursor position.
    local saved_reading_id = vim.b.himalaya_reading_cursor_id
    if saved_reading_id then
      vim.b.himalaya_reading_cursor_id = nil
      for i, env in ipairs(envelopes) do
        if tostring(env.id) == saved_reading_id then cursor_row = i; break end
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

    -- Position cursor on selected email
    pcall(vim.api.nvim_win_set_cursor, 0, {cursor_line, 0})

    if reading then
      -- Save envelope ID for cursor restoration on grow.
      vim.b.himalaya_reading_cursor_id = display_envelopes[cursor_line]
        and tostring(display_envelopes[cursor_line].id) or nil
      -- When the page is fully covered by cached envelopes, skip Phase 2.
      -- When sparse (cursor near cache edge), fall through to Phase 2
      -- so the server fills the rest of the page.
      if #display_envelopes >= new_page_size then
        return
      end
    end

    -- Phase 2: deferred re-fetch (debounced 150ms)
    if resize_timer then resize_timer:stop() end
    if resize_job then resize_job:kill(); resize_job = nil end

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
      saved_cursor_id = M._get_email_id_from_line(
        vim.api.nvim_buf_get_lines(bufnr, cursor_ln - 1, cursor_ln, false)[1] or '')
      local account = account_state.current()
      local folder_cur = folder_state.current()
      local cur_query = vim.b[bufnr].himalaya_query or ''
      local cur_page = vim.b[bufnr].himalaya_page or 1
      local ps = vim.b[bufnr].himalaya_page_size
      resize_job = request.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { folder_cur, account_flag(account), ps, cur_page, cur_query },
        msg = 'Refetching page after resize',
        on_data = function(data)
          resize_job = nil
          if not vim.api.nvim_win_is_valid(listing_win) then return end
          vim.api.nvim_win_call(listing_win, function()
            on_list_with(account, folder_cur, cur_page, ps, cur_query, data)
          end)
        end,
      })
    end))
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
end

--- Cancel any pending resize timer and in-flight resize re-fetch job.
function M.cancel_resize()
  if resize_timer then resize_timer:stop(); resize_timer = nil end
  if resize_job then resize_job:kill(); resize_job = nil end
end

--- Set the list envelopes query and refresh.
function M.set_list_envelopes_query()
  query = vim.fn.input('Query: ')
  M.list()
end

return M
