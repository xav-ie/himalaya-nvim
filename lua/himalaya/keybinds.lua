local M = {}

function M.define(bufnr, bindings)
  for _, binding in ipairs(bindings) do
    local mode, key, callback, name = binding[1], binding[2], binding[3], binding[4]
    local plug = '<Plug>(himalaya-' .. name .. ')'

    vim.keymap.set(mode, plug, callback, { silent = true, desc = 'Himalaya: ' .. name })

    if vim.fn.hasmapto(plug, mode) == 0 then
      vim.keymap.set(mode, key, plug, { buffer = bufnr, nowait = true })
    end
  end
end

--- Wrap a function that takes (first_line, last_line) for use in visual mode.
--- Gets the visual range, calls fn(first, last), and exits visual mode.
--- @param fn function(first: number, last: number)
--- @return function
function M.visual_range(fn)
  return function()
    local first = vim.fn.line('v')
    local last = vim.fn.line('.')
    if first > last then first, last = last, first end
    fn(first, last)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  end
end

--- Define keybinds shared between flat listing and thread listing.
--- Both modes share compose, account, attachment, copy/move, delete,
--- seen/unseen, and flag add/remove bindings.
--- @param bufnr number
function M.shared_listing_keybinds(bufnr)
  local compose = require('himalaya.domain.email.compose')
  local email = require('himalaya.domain.email')
  local account

  M.define(bufnr, {
    { 'n', 'gw',   compose.write,                       'email-write' },
    { 'n', 'gr',   compose.reply,                        'email-reply' },
    { 'n', 'gR',   compose.reply_all,                    'email-reply-all' },
    { 'n', 'gf',   compose.forward,                      'email-forward' },
    { 'n', 'ga',   function()
      account = account or require('himalaya.domain.account')
      account.select()
    end, 'account-select' },
    { 'n', 'gA',   email.download_attachments,           'email-download-attachments' },
    { 'n', 'gC',   email.select_folder_then_copy,        'email-select-folder-then-copy' },
    { 'v', 'gC',   M.visual_range(email.select_folder_then_copy), 'email-select-folder-then-copy-visual' },
    { 'n', 'gM',   email.select_folder_then_move,        'email-select-folder-then-move' },
    { 'v', 'gM',   M.visual_range(email.select_folder_then_move), 'email-select-folder-then-move-visual' },
    { 'n', 'dd',   email.delete,                         'email-delete' },
    { 'v', 'd',    M.visual_range(email.delete),         'email-delete-visual' },
    { 'n', 'gs',   email.mark_seen,                      'email-mark-seen' },
    { 'v', 'gs',   M.visual_range(email.mark_seen),      'email-mark-seen-visual' },
    { 'n', 'gS',   email.mark_unseen,                    'email-mark-unseen' },
    { 'v', 'gS',   M.visual_range(email.mark_unseen),    'email-mark-unseen-visual' },
    { 'n', 'gFa',  email.flag_add,                       'email-flag-add' },
    { 'v', 'gFa',  M.visual_range(email.flag_add),       'email-flag-add-visual' },
    { 'n', 'gFr',  email.flag_remove,                    'email-flag-remove' },
    { 'v', 'gFr',  M.visual_range(email.flag_remove),    'email-flag-remove-visual' },
    { 'n', 'gm',   function() require('himalaya.domain.folder').select() end, 'folder-select' },
  })
end

return M
