local request = require('himalaya.request')
local log = require('himalaya.log')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')

local M = {}

local draft = ''

local function account_flag(account)
  if account == '' then return '' end
  return '--account ' .. account
end

--- Resolve the email ID from context: listing buffer → cursor line, else → current read ID.
local function context_email_id()
  local bt = vim.b.himalaya_buffer_type
  if bt == 'listing' or bt == 'thread-listing' then
    local email = require('himalaya.domain.email')
    return email._get_email_id_from_line(vim.api.nvim_get_current_line())
  end
  return require('himalaya.domain.email')._get_current_id()
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
    local current_id = require('himalaya.domain.email')._get_current_id()

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

return M
