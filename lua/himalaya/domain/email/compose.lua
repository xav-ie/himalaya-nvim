local request = require('himalaya.request')
local log = require('himalaya.log')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local win = require('himalaya.ui.win')

local M = {}

local draft = ''
local sent = false

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

--- Internal: open a write/reply/forward buffer with template content.
--- @param msg string buffer name suffix
--- @param content string template content
local function open_write_buffer(msg, content)
  local bufname = string.format('Himalaya/%s', msg)
  if vim.fn.winnr('$') == 1 then
    vim.cmd(string.format('silent! botright split %s', bufname))
  else
    -- Prefer the reading window so the listing stays visible
    local reading_win = win.find_by_name('Himalaya/read email')
    if reading_win then
      vim.api.nvim_set_current_win(reading_win)
    end
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

--- Save current buffer content as draft.
function M.save_draft()
  draft = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n'
  vim.cmd('redraw')
  log.info('Save draft [OK]')
  vim.bo.modified = false
end

--- Send the current compose buffer (triggered by :w).
--- @param bufnr? number  buffer handle (defaults to current buffer)
function M.send(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if sent then
    log.info('Email already sent from this buffer')
    return
  end

  local account = account_state.current()
  local folder = folder_state.current()
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n'

  request.plain({
    cmd = 'template send %s',
    args = { account_flag(account) },
    stdin = content,
    msg = 'Sending email',
    on_data = function()
      sent = true
      vim.bo[bufnr].modified = false
      log.info('Send [OK]')

      -- Add "answered" flag only for replies (not new compose or forwards)
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname:find('reply', 1, true) then
        local current_id = require('himalaya.domain.email')._get_current_id()
        if current_id ~= '' then
          request.plain({
            cmd = 'flag add %s --folder %s answered %s',
            args = { account_flag(account), folder, current_id },
            msg = 'Adding answered flag',
          })
        end
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
  if sent then
    sent = false
    return
  end
  local ok, err = pcall(function()
    local account = account_state.current()

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
