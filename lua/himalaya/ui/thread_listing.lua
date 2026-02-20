local keybinds = require('himalaya.keybinds')
local thread_listing = require('himalaya.domain.email.thread_listing')
local compose = require('himalaya.domain.email.compose')
local folder = require('himalaya.domain.folder')
local email = require('himalaya.domain.email')
local account

local M = {}

--- Apply full 5-column syntax (same as flat listing) plus tree connector overlay.
--- Per-column coloring is active; read/unread distinction comes from extmark-based
--- seen highlights applied in render_page after flag enrichment.
--- @param bufnr number
local function apply_syntax(bufnr)
  local listing = require('himalaya.ui.listing')
  listing.apply_syntax(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd([[
      syntax match HimalayaTree /\%u251c\%u2500\|\%u2514\%u2500\|\%u2502 / contained containedin=HimalayaSubject
    ]])
  end)
end

--- Set up the thread listing buffer: options, highlights, syntax, and keybinds.
--- @param bufnr number
function M.setup(bufnr)
  vim.bo[bufnr].buftype = 'nofile'
  vim.api.nvim_buf_call(bufnr, function()
    vim.wo.cursorline = true
    vim.wo.wrap = true
    vim.wo.scrolloff = 0
  end)
  vim.bo[bufnr].modifiable = false

  local listing = require('himalaya.ui.listing')
  listing.define_highlights()
  vim.api.nvim_set_hl(0, 'HimalayaTree', { default = true, link = 'Comment' })

  apply_syntax(bufnr)

  keybinds.define(bufnr, {
    { 'n', '<cr>', thread_listing.read,              'thread-email-read' },
    { 'n', 'gp',   thread_listing.previous_page,     'thread-previous-page' },
    { 'n', 'gn',   thread_listing.next_page,          'thread-next-page' },
    { 'n', 'gm',   folder.select,                     'folder-select' },
    { 'n', 'g/',   thread_listing.set_thread_query,   'thread-search' },
    { 'n', 'gt',   thread_listing.toggle_to_flat,     'thread-toggle-flat' },
    { 'n', 'gw',   compose.write,                     'email-write' },
    { 'n', 'gr',   compose.reply,                     'email-reply' },
    { 'n', 'gR',   compose.reply_all,                 'email-reply-all' },
    { 'n', 'gf',   compose.forward,                   'email-forward' },
    { 'n', 'ga',   function()
      account = account or require('himalaya.domain.account')
      account.select()
    end, 'account-select' },
    { 'n', 'gA',   email.download_attachments,         'email-download-attachments' },
    { 'n', 'gC',   email.select_folder_then_copy,      'email-select-folder-then-copy' },
    { 'v', 'gC',   function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.select_folder_then_copy(first, last)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end, 'email-select-folder-then-copy-visual' },
    { 'n', 'gM',   email.select_folder_then_move,      'email-select-folder-then-move' },
    { 'v', 'gM',   function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.select_folder_then_move(first, last)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end, 'email-select-folder-then-move-visual' },
    { 'n', 'dd',   email.delete,                       'email-delete' },
    { 'v', 'd',    function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.delete(first, last)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end, 'email-delete-visual' },
    { 'n', 'gs',   email.mark_seen,                     'email-mark-seen' },
    { 'v', 'gs',   function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.mark_seen(first, last)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end, 'email-mark-seen-visual' },
    { 'n', 'gS',   email.mark_unseen,                   'email-mark-unseen' },
    { 'v', 'gS',   function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.mark_unseen(first, last)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end, 'email-mark-unseen-visual' },
    { 'n', 'gFa',  email.flag_add,                     'email-flag-add' },
    { 'v', 'gFa',  function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.flag_add(first, last)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end, 'email-flag-add-visual' },
    { 'n', 'gFr',  email.flag_remove,                  'email-flag-remove' },
    { 'v', 'gFr',  function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.flag_remove(first, last)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end, 'email-flag-remove-visual' },
  })

  local augroup = vim.api.nvim_create_augroup('HimalayaThreadListing', { clear = true })
  local function on_resize()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
        vim.api.nvim_win_call(winid, function()
          thread_listing.resize()
        end)
        break
      end
    end
  end
  vim.api.nvim_create_autocmd('VimResized', {
    group = augroup,
    callback = on_resize,
  })
  vim.api.nvim_create_autocmd('WinResized', {
    group = augroup,
    callback = on_resize,
  })
end

return M
