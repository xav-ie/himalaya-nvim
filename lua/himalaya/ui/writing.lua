local config = require('himalaya.config')
local email = require('himalaya.domain.email')
local compose = require('himalaya.domain.email.compose')

local M = {}

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

  local group = vim.api.nvim_create_augroup('himalaya_write_' .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = bufnr,
    callback = function()
      compose.save_draft()
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    buffer = bufnr,
    callback = function()
      compose.save_draft()
    end,
  })

  vim.api.nvim_create_autocmd('BufHidden', {
    group = group,
    buffer = bufnr,
    callback = function(ev)
      compose.process_draft(ev.buf)
    end,
  })
end

return M
