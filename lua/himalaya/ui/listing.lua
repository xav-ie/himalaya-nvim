local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local folder = require('himalaya.domain.folder')
local account

local M = {}

local ns = vim.api.nvim_create_namespace('himalaya_seen')

--- Define highlight groups for the email listing view.
function M.define_highlights()
  vim.api.nvim_set_hl(0, 'HimalayaSeparator', { default = true, link = 'VertSplit' })
  vim.api.nvim_set_hl(0, 'HimalayaId', { default = true, link = 'Identifier' })
  vim.api.nvim_set_hl(0, 'HimalayaFlags', { default = true, link = 'Special' })
  vim.api.nvim_set_hl(0, 'HimalayaSubject', { default = true, link = 'String' })
  vim.api.nvim_set_hl(0, 'HimalayaSender', { default = true, link = 'Structure' })
  vim.api.nvim_set_hl(0, 'HimalayaDate', { default = true, link = 'Constant' })
  vim.api.nvim_set_hl(0, 'HimalayaHead', { default = true, bold = true, underline = true })
  vim.api.nvim_set_hl(0, 'HimalayaSeen', { default = true, link = 'Normal' })
end

--- Apply syntax match rules to the given buffer.
--- @param bufnr number
function M.apply_syntax(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    -- Use \%u2502 (│), \%u2500 (─), \%u253c (┼) for box-drawing chars
    vim.cmd([[
      syntax match HimalayaSeparator /\%u2502\|\%u2500\|\%u253c/
      syntax match HimalayaId        /^.\{-}\%u2502/                                                             contains=HimalayaSeparator
      syntax match HimalayaFlags     /^.\{-}\%u2502.\{-}\%u2502/                                                 contains=HimalayaId,HimalayaSeparator
      syntax match HimalayaSubject   /^.\{-}\%u2502.\{-}\%u2502.\{-}\%u2502/                                     contains=HimalayaId,HimalayaFlags,HimalayaSeparator
      syntax match HimalayaSender    /^.\{-}\%u2502.\{-}\%u2502.\{-}\%u2502.\{-}\%u2502/                         contains=HimalayaId,HimalayaFlags,HimalayaSubject,HimalayaSeparator
      syntax match HimalayaDate      /^.\{-}\%u2502.\{-}\%u2502.\{-}\%u2502.\{-}\%u2502.\{-}$/                   contains=HimalayaId,HimalayaFlags,HimalayaSubject,HimalayaSender,HimalayaSeparator
    ]])
  end)
end

--- Compute the gutter width (number column, fold column, sign column) for a window.
--- @param winid number
--- @param bufnr number
--- @return number
local function gutter_width(winid, bufnr)
  local wo = vim.wo[winid]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local numberwidth = math.max(wo.numberwidth, #tostring(line_count) + 1)
  local numwidth = (wo.number or wo.relativenumber) and numberwidth or 0
  local foldwidth = tonumber(wo.foldcolumn) or 0

  local signwidth = 0
  if wo.signcolumn == 'yes' then
    signwidth = 2
  elseif wo.signcolumn == 'auto' then
    local signs = vim.fn.execute(string.format('sign place buffer=%d', bufnr))
    local sign_lines = vim.split(signs, '\n')
    signwidth = #sign_lines > 2 and 2 or 0
  end

  return numwidth + foldwidth + signwidth
end

--- Set the header as a sticky winbar at the top of the listing window.
--- @param bufnr number
--- @param header string
function M.apply_header(bufnr, header)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      local pad = string.rep(' ', gutter_width(winid, bufnr))
      -- Escape percent signs and other statusline special chars
      local escaped = header:gsub('%%', '%%%%')
      vim.wo[winid].winbar = '%#HimalayaHead#' .. pad .. escaped
    end
  end
end

--- Apply extmark-based highlights to dim seen (read) envelope lines.
--- Unseen lines keep per-column syntax coloring; seen lines get reset to Normal.
--- @param bufnr number
--- @param envelopes table[]
function M.apply_seen_highlights(bufnr, envelopes)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for i, env in ipairs(envelopes) do
    local flags = env.flags or {}
    local seen = false
    for _, f in ipairs(flags) do
      if f == 'Seen' then seen = true; break end
    end
    if seen then
      local line = i - 1  -- 0-based, no header offset
      vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
        end_row = line,
        end_col = #vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1],
        hl_group = 'HimalayaSeen',
        priority = 200,
      })
    end
  end
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
    { 'n', 'ga',   function()
      account = account or require('himalaya.domain.account')
      account.select()
    end, 'account-select' },
    { 'n', 'gA',   email.download_attachments,         'email-download-attachments' },
    { 'n', 'gC',   email.select_folder_then_copy,      'email-select-folder-then-copy' },
    { 'n', 'gM',   email.select_folder_then_move,      'email-select-folder-then-move' },
    { 'n', 'dd',   email.delete,                       'email-delete' },
    { 'v', 'd',    function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.delete(first, last)
    end, 'email-delete-visual' },
    { 'n', 'gs',   email.mark_seen,                     'email-mark-seen' },
    { 'v', 'gs',   function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.mark_seen(first, last)
    end, 'email-mark-seen-visual' },
    { 'n', 'gS',   email.mark_unseen,                   'email-mark-unseen' },
    { 'v', 'gS',   function()
      local first = vim.fn.line('v')
      local last = vim.fn.line('.')
      if first > last then first, last = last, first end
      email.mark_unseen(first, last)
    end, 'email-mark-unseen-visual' },
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

  local augroup = vim.api.nvim_create_augroup('HimalayaListing', { clear = true })
  vim.api.nvim_create_autocmd('VimResized', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      email.rerender_listing()
      M.apply_syntax(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd('WinResized', {
    group = augroup,
    callback = function()
      if vim.api.nvim_get_current_buf() == bufnr then
        email.rerender_listing()
        M.apply_syntax(bufnr)
      end
    end,
  })
end

return M
