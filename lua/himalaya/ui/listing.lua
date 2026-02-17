local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local folder = require('himalaya.domain.folder')

local M = {}

--- Define highlight groups for the email listing view.
function M.define_highlights()
  vim.api.nvim_set_hl(0, 'HimalayaSeparator', { default = true, link = 'VertSplit' })
  vim.api.nvim_set_hl(0, 'HimalayaId', { default = true, link = 'Identifier' })
  vim.api.nvim_set_hl(0, 'HimalayaFlags', { default = true, link = 'Special' })
  vim.api.nvim_set_hl(0, 'HimalayaSubject', { default = true, link = 'String' })
  vim.api.nvim_set_hl(0, 'HimalayaSender', { default = true, link = 'Structure' })
  vim.api.nvim_set_hl(0, 'HimalayaDate', { default = true, link = 'Constant' })
  vim.api.nvim_set_hl(0, 'HimalayaHead', { bold = true })
end

--- Apply syntax match rules to the given buffer.
--- @param bufnr number
function M.apply_syntax(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd([[
      syntax match HimalayaSeparator /|/
      syntax match HimalayaId        /^|.\{-}/                          contains=HimalayaSeparator
      syntax match HimalayaFlags     /^|.\{-}|.\{-}/                    contains=HimalayaId,HimalayaSeparator
      syntax match HimalayaSubject   /^|.\{-}|.\{-}|.\{-}/              contains=HimalayaId,HimalayaFlags,HimalayaSeparator
      syntax match HimalayaSender    /^|.\{-}|.\{-}|.\{-}|.\{-}/        contains=HimalayaId,HimalayaFlags,HimalayaSubject,HimalayaSeparator
      syntax match HimalayaDate      /^|.\{-}|.\{-}|.\{-}|.\{-}|.\{-}|/ contains=HimalayaId,HimalayaFlags,HimalayaSubject,HimalayaSender,HimalayaSeparator
      syntax match HimalayaHead      /.*\%1l/                           contains=HimalayaSeparator
      syntax match HimalayaUnseen    /^|.\{-}|.*\*.*$/                  contains=HimalayaSeparator
    ]])
  end)
end

--- Set up the listing buffer: options, highlights, syntax, and keybinds.
--- @param bufnr number
function M.setup(bufnr)
  vim.bo[bufnr].buftype = 'nofile'
  vim.api.nvim_buf_call(bufnr, function()
    vim.wo.cursorline = true
    vim.wo.wrap = false
  end)
  vim.bo[bufnr].modifiable = false

  M.define_highlights()
  M.apply_syntax(bufnr)

  keybinds.define(bufnr, {
    { 'n', 'gm',   folder.select,                    'folder-select' },
    { 'n', 'gp',   folder.select_previous_page,      'folder-select-previous-page' },
    { 'n', 'gn',   folder.select_next_page,           'folder-select-next-page' },
    { 'n', '<cr>', email.read,                         'email-read' },
    { 'n', 'gw',   email.write,                        'email-write' },
    { 'n', 'gr',   email.reply,                        'email-reply' },
    { 'n', 'gR',   email.reply_all,                    'email-reply-all' },
    { 'n', 'gf',   email.forward,                      'email-forward' },
    { 'n', 'ga',   email.download_attachments,         'email-download-attachments' },
    { 'n', 'gC',   email.select_folder_then_copy,      'email-select-folder-then-copy' },
    { 'n', 'gM',   email.select_folder_then_move,      'email-select-folder-then-move' },
    { 'n', 'gD',   email.delete,                       'email-delete' },
    { 'v', 'gD',   function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.delete(first, last)
    end, 'email-delete-visual' },
    { 'n', 'gFa',  email.flag_add,                     'email-flag-add' },
    { 'v', 'gFa',  function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.flag_add(first, last)
    end, 'email-flag-add-visual' },
    { 'n', 'gFr',  email.flag_remove,                  'email-flag-remove' },
    { 'v', 'gFr',  function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.flag_remove(first, last)
    end, 'email-flag-remove-visual' },
    { 'n', 'g/',   email.set_list_envelopes_query,     'email-set-list-envelopes-query' },
  })
end

return M
