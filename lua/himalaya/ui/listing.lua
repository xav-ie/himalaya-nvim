local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local folder = require('himalaya.domain.folder')
local probe = require('himalaya.domain.email.probe')
local perf = require('himalaya.perf')
local win = require('himalaya.ui.win')

local M = {}

local ns = vim.api.nvim_create_namespace('himalaya_seen')

--- Extract numeric email ID from a listing line.
--- @param line string
--- @return string
function M.get_email_id_from_line(line)
  return line:match('%d+') or ''
end

--- Compute the effective page size (visible rows) for the current window.
--- Accounts for winbar: if not yet set, reserves one line for it.
--- @return number
function M.effective_page_size()
  local ps = math.max(1, vim.fn.winheight(0))
  if vim.wo.winbar == '' then
    ps = math.max(1, ps - 1)
  end
  return ps
end

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
  perf.start('apply_syntax')
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
  perf.stop('apply_syntax')
end

--- Compute the gutter width (number column, fold column, sign column) for a window.
--- @param winid number
--- @param bufnr number
--- @return number
function M.gutter_width(winid, bufnr)
  local wo = vim.wo[winid]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local numberwidth = math.max(wo.numberwidth, #tostring(line_count) + 1)
  local numwidth = (wo.number or wo.relativenumber) and numberwidth or 0
  local foldwidth = tonumber(wo.foldcolumn) or 0

  local signwidth = 0
  if wo.signcolumn == 'yes' then
    signwidth = 2
  elseif wo.signcolumn == 'auto' then
    local placed = vim.fn.sign_getplaced(bufnr)
    signwidth = (placed[1] and #placed[1].signs > 0) and 2 or 0
  end

  return numwidth + foldwidth + signwidth
end

--- Set the header as a sticky winbar at the top of the listing window.
--- @param bufnr number
--- @param header string
function M.apply_header(bufnr, header)
  local winid = win.find_by_bufnr(bufnr)
  if not winid then
    return
  end
  local pad = string.rep(' ', M.gutter_width(winid, bufnr))
  local escaped = header:gsub('%%', '%%%%')
  vim.wo[winid].winbar = '%#HimalayaHead#' .. pad .. escaped
end

--- Apply extmark-based highlights to dim seen (read) envelope lines.
--- Unseen lines keep per-column syntax coloring; seen lines get reset to Normal.
--- @param bufnr number
--- @param envelopes table[]
function M.apply_seen_highlights(bufnr, envelopes)
  perf.start('apply_seen_highlights')
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for i, env in ipairs(envelopes) do
    local flags = env.flags or {}
    local seen = false
    for _, f in ipairs(flags) do
      if f == 'Seen' then
        seen = true
        break
      end
    end
    if seen then
      local line = i - 1 -- 0-based, no header offset
      vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
        end_row = line + 1,
        hl_eol = true,
        hl_group = 'HimalayaSeen',
        priority = 200,
      })
    end
  end
  perf.stop('apply_seen_highlights')
end

--- Set up the listing buffer: options, highlights, syntax, and keybinds.
--- @param bufnr number
function M.setup(bufnr)
  vim.bo[bufnr].buftype = 'nofile'
  vim.api.nvim_buf_call(bufnr, function()
    vim.wo.cursorline = true
    vim.wo.wrap = true
    vim.wo.scrolloff = 0
  end)
  vim.bo[bufnr].modifiable = false

  M.define_highlights()
  M.apply_syntax(bufnr)

  keybinds.shared_listing_keybinds(bufnr)
  keybinds.define(bufnr, {
    { 'n', 'gp', folder.select_previous_page, 'folder-select-previous-page' },
    { 'n', 'gn', folder.select_next_page, 'folder-select-next-page' },
    { 'n', '<cr>', email.read, 'email-read' },
    { 'n', 'g/', email.set_list_envelopes_query, 'email-set-list-envelopes-query' },
    {
      'n',
      'gt',
      function()
        local id = M.get_email_id_from_line(vim.api.nvim_get_current_line())
        require('himalaya.domain.email.thread_listing').list(nil, { restore_email_id = id })
      end,
      'thread-listing-toggle',
    },
  })

  local augroup = vim.api.nvim_create_augroup('HimalayaListing', { clear = true })
  local function on_resize()
    local winid = win.find_by_bufnr(bufnr)
    if winid then
      vim.api.nvim_win_call(winid, function()
        email.resize_listing()
      end)
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
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      email.cleanup()
      probe.cleanup()
    end,
  })
end

return M
