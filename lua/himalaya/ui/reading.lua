local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local compose = require('himalaya.domain.email.compose')
local win = require('himalaya.ui.win')

local M = {}

--- Navigate to the next or previous email in the listing and read it.
--- @param direction number  +1 for next, -1 for previous
local function navigate_email(direction)
  local winid, bufnr = win.find_by_buftype({ 'listing', 'thread-listing' })
  if not winid then
    return
  end
  vim.api.nvim_win_call(winid, function()
    local row = vim.api.nvim_win_get_cursor(winid)[1]
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local new_row = row + direction
    if new_row >= 1 and new_row <= line_count then
      vim.api.nvim_win_set_cursor(winid, { new_row, 0 })
      email.read()
    end
  end)
end

--- Set up the reading buffer: options, syntax, and keybinds.
--- @param bufnr number
function M.setup(bufnr)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].filetype = 'mail'
  vim.bo[bufnr].modifiable = false

  vim.api.nvim_buf_call(bufnr, function()
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = "v:lua.require'himalaya.domain.email.thread'.foldexpr(v:lnum)"
  end)

  keybinds.define(bufnr, {
    { 'n', 'gw', compose.write, 'email-write' },
    { 'n', 'gr', compose.reply, 'email-reply' },
    { 'n', 'gR', compose.reply_all, 'email-reply-all' },
    { 'n', 'gf', compose.forward, 'email-forward' },
    {
      'n',
      'ga',
      function()
        require('himalaya.domain.account').select()
      end,
      'account-select',
    },
    { 'n', 'gA', email.download_attachments, 'email-download-attachments' },
    { 'n', 'gC', email.select_folder_then_copy, 'email-select-folder-then-copy' },
    { 'n', 'gM', email.select_folder_then_move, 'email-select-folder-then-move' },
    { 'n', 'gD', email.delete, 'email-delete' },
    { 'n', 'go', email.open_browser, 'email-open-browser' },
    {
      'n',
      'gn',
      function()
        navigate_email(1)
      end,
      'email-next',
    },
    {
      'n',
      'gp',
      function()
        navigate_email(-1)
      end,
      'email-previous',
    },
    { 'n', '?', keybinds.show_help, 'help' },
  })
end

return M
