local config = require('himalaya.config')
local log = require('himalaya.log')

local M = {}

function M.setup(opts)
  config.setup(opts)

  local cfg = config.get()
  if vim.fn.executable(cfg.executable) == 0 then
    log.err('Himalaya CLI not found, see https://pimalaya.org/himalaya/cli/latest/installation/')
    return
  end
end

function M._register_commands()
  local email = require('himalaya.domain.email')
  local compose = require('himalaya.domain.email.compose')
  local folder = require('himalaya.domain.folder')

  local account_state = require('himalaya.state.account')

  vim.api.nvim_create_user_command('Himalaya', function(opts)
    if config.get().thread_view then
      require('himalaya.domain.email.thread_listing').list(opts.fargs[1])
    else
      email.list(opts.fargs[1])
    end
  end, {
    nargs = '*',
    complete = function(arg_lead)
      local accounts = account_state.list()
      if arg_lead == '' then
        return accounts
      end
      return vim.tbl_filter(function(name)
        return vim.startswith(name, arg_lead)
      end, accounts)
    end,
  })

  vim.api.nvim_create_user_command('HimalayaCopy', function()
    email.select_folder_then_copy()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaMove', function()
    email.select_folder_then_move()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaDelete', function(opts)
    email.delete(opts.line1, opts.line2)
  end, { nargs = '*', range = true })

  vim.api.nvim_create_user_command('HimalayaWrite', function()
    compose.write()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaReply', function()
    compose.reply()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaReplyAll', function()
    compose.reply_all()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaForward', function()
    compose.forward()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaFolders', function()
    folder.select()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaFolder', function(opts)
    folder.set(opts.fargs[1])
  end, { nargs = 1 })

  vim.api.nvim_create_user_command('HimalayaNextPage', function()
    folder.select_next_page()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaPreviousPage', function()
    folder.select_previous_page()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaAttachments', function()
    email.download_attachments()
  end, { nargs = '0' })

  vim.api.nvim_create_user_command('HimalayaFlagAdd', function(opts)
    email.flag_add(opts.line1, opts.line2)
  end, { nargs = '*', range = true })

  vim.api.nvim_create_user_command('HimalayaFlagRemove', function(opts)
    email.flag_remove(opts.line1, opts.line2)
  end, { nargs = '*', range = true })
end

function M._register_filetypes()
  local group = vim.api.nvim_create_augroup('himalaya', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'himalaya-email-listing',
    callback = function(ev)
      require('himalaya.ui.listing').setup(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'himalaya-email-reading',
    callback = function(ev)
      require('himalaya.ui.reading').setup(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'himalaya-email-writing',
    callback = function(ev)
      require('himalaya.ui.writing').setup(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'himalaya-thread-listing',
    callback = function(ev)
      require('himalaya.ui.thread_listing').setup(ev.buf)
    end,
  })
end

return M
