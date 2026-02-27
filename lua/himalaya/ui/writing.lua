local config = require('himalaya.config')
local compose = require('himalaya.domain.email.compose')
local win = require('himalaya.ui.win')

local M = {}

--- Scan buffer to find header region and compute label widths.
--- Returns a table mapping 0-based line index to label byte width (up to ": ").
--- Header region ends at the first blank line.
--- @param bufnr number
--- @return table<number, number> label_widths
--- @return number body_line 0-based line index of the body start
local function scan_headers(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local label_widths = {}
  local body_line = #lines
  for i, line in ipairs(lines) do
    if line == '' then
      body_line = i -- 1-based → 0-based is i-1, but body content is the next line
      break
    end
    local _, label_end = line:find(': ')
    if label_end then
      label_widths[i - 1] = label_end + 1 -- first column after ": "
    end
  end
  return label_widths, body_line
end

--- Set up the writing buffer: options, completefunc, and autocmds.
--- @param bufnr number
function M.setup(bufnr)
  vim.bo[bufnr].filetype = 'mail'

  vim.api.nvim_buf_call(bufnr, function()
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = "v:lua.require'himalaya.domain.email.thread'.foldexpr(v:lnum)"
    vim.opt_local.startofline = true
  end)

  local cfg = config.get()
  if cfg.complete_contact_cmd then
    vim.bo[bufnr].completefunc = "v:lua.require'himalaya.domain.email'.complete_contact"
  end

  -- Protect header labels from accidental editing
  local label_widths, body_line = scan_headers(bufnr)

  local group = vim.api.nvim_create_augroup('himalaya_write_' .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd('CursorMovedI', {
    group = group,
    buffer = bufnr,
    callback = function()
      local row = vim.fn.line('.') - 1
      local col = vim.fn.col('.')
      local min_col = label_widths[row]
      if min_col and col < min_col then
        vim.fn.cursor(row + 1, min_col)
      end
    end,
  })

  -- Place cursor at first empty header value, or at body if all filled.
  vim.api.nvim_buf_call(bufnr, function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, body_line, false)
    for i, line in ipairs(lines) do
      local _, label_end = line:find(': ')
      if label_end and #line == label_end then
        -- Empty value: position cursor after ": " and enter insert mode
        vim.fn.cursor(i, label_end + 1)
        vim.cmd('startinsert')
        return
      end
    end
    vim.fn.cursor(body_line + 1, 1)
  end)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = bufnr,
    callback = function()
      compose.send(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    buffer = bufnr,
    callback = function()
      compose.save_draft(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd('BufHidden', {
    group = group,
    buffer = bufnr,
    callback = function(ev)
      compose.process_draft(ev.buf)
    end,
  })

  local account = vim.b[bufnr].himalaya_account or ''
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local kind = 'compose'
  if bufname:find('reply') then
    kind = 'reply'
  elseif bufname:find('forward') then
    kind = 'forward'
  end
  local label = string.format('[%s] %s', account, kind)
  local winid = win.find_by_bufnr(bufnr)
  if winid then
    vim.wo[winid].winbar = '%#HimalayaHead#' .. label:gsub('%%', '%%%%')
  end
end

return M
