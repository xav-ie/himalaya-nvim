local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local compose = require('himalaya.domain.email.compose')
local thread = require('himalaya.domain.email.thread')

local M = {}

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
    { 'n', 'gw', compose.write,                   'email-write' },
    { 'n', 'gr', compose.reply,                   'email-reply' },
    { 'n', 'gR', compose.reply_all,               'email-reply-all' },
    { 'n', 'gf', compose.forward,                 'email-forward' },
    { 'n', 'ga', email.download_attachments,     'email-download-attachments' },
    { 'n', 'gC', email.select_folder_then_copy,  'email-select-folder-then-copy' },
    { 'n', 'gM', email.select_folder_then_move,  'email-select-folder-then-move' },
    { 'n', 'gD', email.delete,                   'email-delete' },
    { 'n', 'go', email.open_browser,             'email-open-browser' },
  })
end

return M
