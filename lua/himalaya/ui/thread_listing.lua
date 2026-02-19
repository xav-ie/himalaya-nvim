local keybinds = require('himalaya.keybinds')
local thread_listing = require('himalaya.domain.email.thread_listing')
local compose = require('himalaya.domain.email.compose')
local folder = require('himalaya.domain.folder')
local email = require('himalaya.domain.email')
local account

local M = {}

--- Apply 4-column syntax rules (ID │ SUBJECT │ FROM │ DATE) plus tree highlights.
--- @param bufnr number
local function apply_syntax(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    -- Use \%u for box-drawing and tree-drawing chars
    vim.cmd([[
      syntax match HimalayaSeparator /\%u2502\|\%u2500\|\%u253c/
      syntax match HimalayaId        /^.\{-}\%u2502/                                     contains=HimalayaSeparator
      syntax match HimalayaSubject   /^.\{-}\%u2502.\{-}\%u2502/                         contains=HimalayaId,HimalayaSeparator
      syntax match HimalayaSender    /^.\{-}\%u2502.\{-}\%u2502.\{-}\%u2502/             contains=HimalayaId,HimalayaSubject,HimalayaSeparator
      syntax match HimalayaDate      /^.\{-}\%u2502.\{-}\%u2502.\{-}\%u2502.\{-}$/       contains=HimalayaId,HimalayaSubject,HimalayaSender,HimalayaSeparator
      syntax match HimalayaTree      /\%u251c\%u2500\|\%u2514\%u2500\|\%u2502 / contained containedin=HimalayaSubject
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
    { 'n', 'dd',   email.delete,                      'email-delete' },
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
