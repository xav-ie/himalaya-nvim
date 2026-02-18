local request = require('himalaya.request')
local log = require('himalaya.log')
local config = require('himalaya.config')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')

local M = {}

-- Module-local state (mirrors s:id, s:draft, s:query in VimScript)
local current_id = ''
local draft = ''
local query = ''
local email_totals = {} -- cache_key -> total email count (positive=exact, negative=at least abs(n))
local last_folder = nil
local last_query = nil
local saved_view = nil

--- Compute total pages string from email_totals and current page_size.
--- @param cache_key string
--- @param page_size number
--- @return string
local function total_pages_str(cache_key, page_size)
  local total = email_totals[cache_key]
  if not total then return '?' end
  if total < 0 then
    return tostring(math.ceil(-total / page_size)) .. '+'
  end
  return tostring(math.ceil(total / page_size))
end

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
  local has_winbar = vim.wo.winbar ~= ''
  return vim.fn.winheight(0) - (has_winbar and 0 or 1)
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

--- Probe subsequent pages in the background to discover total page count.
--- @param account string
--- @param folder string
--- @param page_size number
--- @param probe_page number
--- @param qry string
--- @param bufnr number
local function probe_page_count(account, folder, page_size, probe_page, qry, bufnr)
  request.json({
    cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
    args = {
      folder,
      account_flag(account),
      page_size,
      probe_page,
      qry,
    },
    msg = string.format('Probing page %d', probe_page),
    on_data = function(data)
      local cache_key = folder .. '\0' .. qry
      if #data < page_size then
        email_totals[cache_key] = (probe_page - 1) * page_size + #data
      elseif probe_page >= 10 then
        email_totals[cache_key] = -(probe_page * page_size)
      else
        probe_page_count(account, folder, page_size, probe_page + 1, qry, bufnr)
        return
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        local ok, page = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_page')
        local ok2, cur_page_size = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_page_size')
        if ok and ok2 then
          local display_qry = qry == '' and 'all' or qry
          vim.api.nvim_buf_set_name(bufnr,
            string.format('Himalaya/envelopes [%s] [%s] [page %d⁄%s]', folder, display_qry, page, total_pages_str(cache_key, cur_page_size)))
          vim.cmd('redraw')
        end
      end
    end,
  })
end

--- Internal callback for list_with — populates the envelope listing buffer.
local function on_list_with(account, folder, page, page_size, qry, data)
  if folder ~= last_folder or qry ~= last_query then
    email_totals = {}
    last_folder = folder
    last_query = qry
  end

  local cache_key = folder .. '\0' .. qry
  if not email_totals[cache_key] and #data < page_size then
    email_totals[cache_key] = (page - 1) * page_size + #data
  end
  local total_str = total_pages_str(cache_key, page_size)

  local renderer = require('himalaya.ui.renderer')
  local listing = require('himalaya.ui.listing')
  local buftype = in_listing_buffer() and 'file' or 'edit'
  local display_query = qry == '' and 'all' or qry
  vim.cmd(string.format('silent! %s Himalaya/envelopes [%s] [%s] [page %d⁄%s]', buftype, folder, display_query, page, total_str))
  vim.bo.modifiable = true
  vim.b.himalaya_envelopes = data
  vim.b.himalaya_page = page
  vim.b.himalaya_page_size = page_size
  local bufnr = vim.api.nvim_get_current_buf()
  local result = renderer.render(data, M._bufwidth())
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
  listing.apply_header(bufnr, result.header)
  listing.apply_seen_highlights(bufnr, data)
  vim.b.himalaya_buffer_type = 'listing'
  vim.bo.filetype = 'himalaya-email-listing'
  vim.bo.modified = false
  if saved_view then
    vim.fn.winrestview(saved_view)
    saved_view = nil
  else
    vim.cmd('0')
  end

  if not email_totals[cache_key] then
    probe_page_count(account, folder, page_size, page + 1, qry, bufnr)
  end
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
  local ps = page_size()
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
  current_id = get_email_id_under_cursor()
  if current_id == '' or current_id == 'ID' then
    return
  end
  -- Capture listing window synchronously before the async request,
  -- so the callback can reliably reference it even if focus changes.
  local listing_winid = vim.api.nvim_get_current_win()
  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message read %s --folder %s %s',
    args = { account_flag(account), folder, current_id },
    msg = string.format('Fetching email %s', current_id),
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

--- Handle listing window resize: recalculate page metadata and truncate
--- displayed envelopes to fit the new window height.
function M.resize_listing()
  if not in_listing_buffer() then return end
  local envelopes = vim.b.himalaya_envelopes
  if not envelopes then return end

  local new_page_size = page_size()
  local old_page_size = vim.b.himalaya_page_size

  if old_page_size and new_page_size ~= old_page_size then
    -- Height changed: recalculate page number and update title
    local old_page = vim.b.himalaya_page or 1
    local first_idx = (old_page - 1) * old_page_size
    local new_page = math.floor(first_idx / new_page_size) + 1
    folder_state.set_page(new_page)
    vim.b.himalaya_page = new_page
    vim.b.himalaya_page_size = new_page_size

    local folder = folder_state.current()
    local cache_key = folder .. '\0' .. query
    local total_str = total_pages_str(cache_key, new_page_size)
    local display_query = query == '' and 'all' or query
    vim.cmd(string.format('silent! file Himalaya/envelopes [%s] [%s] [page %d⁄%s]', folder, display_query, new_page, total_str))
  end

  -- Truncate to window height and re-render for new width
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

--- Set the list envelopes query and refresh.
function M.set_list_envelopes_query()
  query = vim.fn.input('Query: ')
  M.list()
end

return M
