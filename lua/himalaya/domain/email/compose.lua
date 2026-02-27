local request = require('himalaya.request')
local log = require('himalaya.log')
local account_state = require('himalaya.state.account')
local win = require('himalaya.ui.win')

local M = {}

local account_flag = account_state.flag

local function context_email_id()
  return require('himalaya.domain.email').context_email_id()
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

--- Append a signature to the given buffer (blank line + signature lines).
--- @param bufnr number
--- @param sig string
local function append_signature(bufnr, sig)
  local lines = vim.split(sig, '\n')
  local last = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, last, last, false, { '' })
  vim.api.nvim_buf_set_lines(bufnr, last + 1, last + 1, false, lines)
end

--- Internal: open a write/reply/forward buffer with template content.
--- @param msg string buffer name suffix
--- @param content string template content
--- @param account? string account to stamp on buffer
--- @param folder? string folder to stamp on buffer
--- @param reply_id? string email ID being replied to
--- @param mode? string compose mode ('write', 'reply', 'reply_all', 'forward')
local function open_write_buffer(msg, content, account, folder, reply_id, mode)
  local bufname = string.format('Himalaya/%s', msg)
  if vim.fn.winnr('$') == 1 then
    vim.cmd(string.format('silent! botright split %s', vim.fn.fnameescape(bufname)))
  else
    -- Prefer the reading window so the listing stays visible
    local reading_win = win.find_by_name('Himalaya/read email')
    if reading_win then
      vim.api.nvim_set_current_win(reading_win)
    end
    vim.cmd(string.format('silent! edit %s', vim.fn.fnameescape(bufname)))
  end
  if account then
    vim.b.himalaya_account = account
  end
  if folder then
    vim.b.himalaya_folder = folder
  end
  if reply_id then
    vim.b.himalaya_reply_id = reply_id
  end
  set_buffer_content(content)
  local cfg = require('himalaya.config').get()
  local sig = cfg.signature
  if type(sig) == 'table' then
    sig = sig[account]
  end
  if type(sig) == 'string' and sig ~= '' then
    append_signature(vim.api.nvim_get_current_buf(), sig)
  end
  vim.bo.filetype = 'himalaya-email-writing'
  vim.bo.modified = false
  require('himalaya.events').emit('ComposeOpened', {
    account = account,
    folder = folder,
    mode = mode or 'write',
    bufnr = vim.api.nvim_get_current_buf(),
    reply_id = reply_id,
  })
end

--- Compose a new email. If template is provided, use it; otherwise fetch from CLI.
--- @param template? string
function M.write(template)
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  if template then
    open_write_buffer('edit', template, account, folder, nil, 'write')
  else
    request.plain({
      cmd = 'template write %s',
      args = { account_flag(account) },
      msg = 'Fetching new template',
      on_data = function(data)
        open_write_buffer('write', data, account, folder, nil, 'write')
      end,
    })
  end
end

--- Reply to current email.
function M.reply()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  local id = context_email_id()
  request.plain({
    cmd = 'template reply %s --folder %q %s',
    args = { account_flag(account), folder, id },
    msg = 'Fetching reply template',
    on_data = function(data)
      open_write_buffer(string.format('reply [%s]', id), data, account, folder, id, 'reply')
    end,
  })
end

--- Reply-all to current email.
function M.reply_all()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  local id = context_email_id()
  request.plain({
    cmd = 'template reply %s --folder %q --all %s',
    args = { account_flag(account), folder, id },
    msg = 'Fetching reply all template',
    on_data = function(data)
      open_write_buffer(string.format('reply all [%s]', id), data, account, folder, id, 'reply_all')
    end,
  })
end

--- Forward current email.
function M.forward()
  local context = require('himalaya.state.context')
  local account, folder = context.resolve()
  local id = context_email_id()
  request.plain({
    cmd = 'template forward %s --folder %q %s',
    args = { account_flag(account), folder, id },
    msg = 'Fetching forward template',
    on_data = function(data)
      open_write_buffer(string.format('forward [%s]', id), data, account, folder, nil, 'forward')
    end,
  })
end

--- Save current buffer content as draft.
--- Skipped if the email was already sent via :w.
--- @param bufnr? number  buffer handle (defaults to current buffer)
function M.save_draft(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].himalaya_sent then
    return
  end
  vim.cmd('redraw')
  log.info('Save draft [OK]')
  vim.bo.modified = false
end

--- Send the current compose buffer (triggered by :w).
--- @param bufnr? number  buffer handle (defaults to current buffer)
function M.send(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].himalaya_sent then
    log.info('Email already sent from this buffer')
    return
  end

  local account = vim.b[bufnr].himalaya_account or ''
  local folder = vim.b[bufnr].himalaya_folder or 'INBOX'
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n'
  local reply_id = vim.b[bufnr].himalaya_reply_id

  request.plain({
    cmd = 'template send %s',
    args = { account_flag(account) },
    stdin = content,
    msg = 'Sending email',
    on_data = function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.b[bufnr].himalaya_sent = true
        vim.bo[bufnr].modified = false
      end
      log.info('Send [OK]')
      require('himalaya.events').emit('EmailSent', {
        account = account,
        folder = folder,
        reply_id = reply_id,
      })

      -- Add "answered" flag only for replies
      if reply_id and reply_id ~= '' then
        request.plain({
          cmd = 'flag add %s --folder %q answered %s',
          args = { account_flag(account), folder, reply_id },
          msg = 'Adding answered flag',
        })
      end
    end,
  })
end

--- Process draft: prompt for (d)raft, (q)uit, (c)ancel.
--- Called from BufHidden so the compose buffer may already be hidden.
--- Skips the prompt if the email was already sent via :w.
--- @param bufnr? number  buffer handle (defaults to current buffer)
function M.process_draft(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].himalaya_sent then
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.b[bufnr].himalaya_sent = false
    end
    return
  end
  local ok, err = pcall(function()
    local account = vim.b[bufnr].himalaya_account or ''

    while true do
      local choice = vim.fn.input('(d)raft, (q)uit or (c)ancel? ')
      choice = choice:lower():sub(1, 1)
      vim.cmd('redraw | echo')

      if choice == 'd' then
        local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n'
        request.plain({
          cmd = 'template save %s --folder drafts',
          args = { account_flag(account) },
          stdin = content,
          msg = 'Saving draft',
        })
        require('himalaya.events').emit('DraftSaved', { account = account })
        return
      elseif choice == 'q' or choice == '' then
        return
      elseif choice == 'c' then
        -- Re-display the hidden compose buffer instead of creating a new one
        vim.cmd('botright split')
        vim.api.nvim_win_set_buf(0, bufnr)
        return
      end
    end
  end)

  if not ok then
    log.err(tostring(err))
  end
end

return M
