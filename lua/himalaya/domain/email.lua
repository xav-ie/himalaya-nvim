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
  local bufname = vim.api.nvim_buf_get_name(0)
  return bufname:find('Himalaya envelopes', 1, true) == 1
      or vim.fn.bufname('%'):find('Himalaya envelopes', 1, true) == 1
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

--- Close (wipe) all open buffers whose name matches a pattern.
--- @param name string pattern to match
local function close_open_buffers(name)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local bname = vim.api.nvim_buf_get_name(bufnr)
      if bname:find(name, 1, true) then
        vim.cmd('silent! bwipeout ' .. bufnr)
      end
    end
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
local function on_list_with(folder, page, data)
  local buftype = in_listing_buffer() and 'file' or 'edit'
  local display_query = query == '' and 'all' or query
  vim.cmd(string.format('silent! %s Himalaya envelopes [%s] [%s] [page %d]', buftype, folder, display_query, page))
  set_buffer_content(data)
  vim.bo.filetype = 'himalaya-email-listing'
  vim.bo.modified = false
  vim.cmd('0')
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
  request.plain({
    cmd = 'envelope list --folder %s %s --max-width %d --page-size %d --page %d %s',
    args = {
      folder,
      account_flag(account),
      M._bufwidth(),
      vim.fn.winheight(0) - 1,
      page,
      qry,
    },
    msg = string.format('Fetching %s envelopes', folder),
    on_data = function(data)
      on_list_with(folder, page, data)
    end,
  })
end

--- Read email under cursor.
function M.read()
  current_id = get_email_id_under_cursor()
  if current_id == '' or current_id == 'ID' then
    return
  end
  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message read %s --folder %s %s',
    args = { account_flag(account), folder, current_id },
    msg = string.format('Fetching email %s', current_id),
    on_data = function(data)
      close_open_buffers('Himalaya read email')
      vim.cmd(string.format('silent! botright new Himalaya read email [%s]', current_id))
      set_buffer_content(data)
      vim.bo.filetype = 'himalaya-email-reading'
      vim.bo.modified = false
      vim.cmd('0')
    end,
  })
end

--- Internal: open a write/reply/forward buffer with template content.
--- @param msg string buffer name suffix
--- @param content string template content
local function open_write_buffer(msg, content)
  local bufname = string.format('Himalaya %s', msg)
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
    local choice = vim.fn.input(string.format('Are you sure you want to delete email(s) %s? (y/N) ', ids))
    vim.cmd('redraw | echo')
    if choice ~= 'y' then
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
    local choice = vim.fn.input(string.format('Are you sure you want to move the email %s? (y/N) ', id))
    vim.cmd('redraw | echo')
    if choice ~= 'y' then
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

--- Set the list envelopes query and refresh.
function M.set_list_envelopes_query()
  query = vim.fn.input('Query: ')
  M.list()
end

return M
