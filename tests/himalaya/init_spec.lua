local spy = require('luassert.spy')

describe('himalaya', function()
  local himalaya

  -- Stub all domain modules before requiring init.lua
  local function stub_dependencies()
    for key, _ in pairs(package.loaded) do
      if key:find('^himalaya%.') then
        package.loaded[key] = nil
      end
    end

    package.loaded['himalaya.config'] = {
      setup = spy.new(function() end),
      get = function()
        return { executable = 'himalaya', thread_view = false }
      end,
    }

    package.loaded['himalaya.log'] = {
      err = spy.new(function() end),
    }

    package.loaded['himalaya.domain.email'] = {
      list = function() end,
      select_folder_then_copy = function() end,
      select_folder_then_move = function() end,
      delete = function() end,
      download_attachments = function() end,
      flag_add = function() end,
      flag_remove = function() end,
    }

    package.loaded['himalaya.domain.email.compose'] = {
      write = function() end,
      reply = function() end,
      reply_all = function() end,
      forward = function() end,
    }

    package.loaded['himalaya.domain.folder'] = {
      select = function() end,
      set = function() end,
      select_next_page = function() end,
      select_previous_page = function() end,
    }

    package.loaded['himalaya.state.account'] = {
      default = function()
        return ''
      end,
      list = function()
        return {}
      end,
      warmup = spy.new(function() end),
    }

    package.loaded['himalaya.domain.email.thread_listing'] = {
      list = function() end,
    }

    package.loaded['himalaya.ui.listing'] = { setup = function() end }
    package.loaded['himalaya.ui.reading'] = { setup = function() end }
    package.loaded['himalaya.ui.writing'] = { setup = function() end }
    package.loaded['himalaya.ui.thread_listing'] = { setup = function() end }
  end

  before_each(function()
    stub_dependencies()
    himalaya = require('himalaya')
  end)

  describe('setup', function()
    it('passes options to config.setup', function()
      local opts = { executable = '/usr/bin/himalaya' }
      himalaya.setup(opts)
      assert.spy(package.loaded['himalaya.config'].setup).was_called_with(opts)
    end)

    it('logs error when executable is not found', function()
      package.loaded['himalaya.config'].get = function()
        return { executable = 'nonexistent-binary-that-will-never-exist' }
      end
      -- Reload to pick up the new config stub
      package.loaded['himalaya'] = nil
      himalaya = require('himalaya')

      himalaya.setup({})
      assert.spy(package.loaded['himalaya.log'].err).was_called(1)
    end)

    it('does not log error when executable is present', function()
      -- vim.fn.executable returns 1 for things like 'ls' or 'sh'
      package.loaded['himalaya.config'].get = function()
        return { executable = 'sh' }
      end
      package.loaded['himalaya'] = nil
      himalaya = require('himalaya')

      himalaya.setup({})
      assert.spy(package.loaded['himalaya.log'].err).was_not_called()
    end)

    it('calls account warmup when executable is found', function()
      package.loaded['himalaya.config'].get = function()
        return { executable = 'sh' }
      end
      package.loaded['himalaya'] = nil
      himalaya = require('himalaya')

      himalaya.setup({})
      assert.spy(package.loaded['himalaya.state.account'].warmup).was_called(1)
    end)

    it('does not call account warmup when executable is not found', function()
      package.loaded['himalaya.config'].get = function()
        return { executable = 'nonexistent-binary-that-will-never-exist' }
      end
      package.loaded['himalaya'] = nil
      himalaya = require('himalaya')

      himalaya.setup({})
      assert.spy(package.loaded['himalaya.state.account'].warmup).was_not_called()
    end)
  end)

  describe('register_commands', function()
    local expected_commands = {
      'Himalaya',
      'HimalayaCopy',
      'HimalayaMove',
      'HimalayaDelete',
      'HimalayaWrite',
      'HimalayaReply',
      'HimalayaReplyAll',
      'HimalayaForward',
      'HimalayaFolders',
      'HimalayaFolder',
      'HimalayaNextPage',
      'HimalayaPreviousPage',
      'HimalayaAttachments',
      'HimalayaFlagAdd',
      'HimalayaFlagRemove',
    }

    after_each(function()
      -- Clean up created commands
      for _, name in ipairs(expected_commands) do
        pcall(vim.api.nvim_del_user_command, name)
      end
    end)

    it('creates all expected user commands', function()
      himalaya.register_commands()
      local cmds = vim.api.nvim_get_commands({})
      for _, name in ipairs(expected_commands) do
        assert.is_truthy(cmds[name], 'missing command: ' .. name)
      end
    end)

    it('creates exactly the right number of commands', function()
      himalaya.register_commands()
      local cmds = vim.api.nvim_get_commands({})
      local count = 0
      for name, _ in pairs(cmds) do
        if name:match('^Himalaya') then
          count = count + 1
        end
      end
      assert.are.equal(#expected_commands, count)
    end)
  end)

  describe('register_filetypes', function()
    local expected_patterns = {
      'himalaya-email-listing',
      'himalaya-email-reading',
      'himalaya-email-writing',
      'himalaya-thread-listing',
    }

    after_each(function()
      pcall(vim.api.nvim_del_augroup_by_name, 'himalaya')
    end)

    it('creates FileType autocmds for all himalaya filetypes', function()
      himalaya.register_filetypes()
      local autocmds = vim.api.nvim_get_autocmds({
        group = 'himalaya',
        event = 'FileType',
      })
      local patterns = {}
      for _, ac in ipairs(autocmds) do
        patterns[ac.pattern] = true
      end
      for _, pat in ipairs(expected_patterns) do
        assert.is_true(patterns[pat] or false, 'missing autocmd for: ' .. pat)
      end
    end)

    it('creates exactly 4 FileType autocmds', function()
      himalaya.register_filetypes()
      local autocmds = vim.api.nvim_get_autocmds({
        group = 'himalaya',
        event = 'FileType',
      })
      assert.are.equal(4, #autocmds)
    end)
  end)
end)

describe('himalaya command callbacks', function()
  local himalaya
  local email_calls, compose_calls, folder_calls, thread_calls

  local all_commands = {
    'Himalaya',
    'HimalayaCopy',
    'HimalayaMove',
    'HimalayaDelete',
    'HimalayaWrite',
    'HimalayaReply',
    'HimalayaReplyAll',
    'HimalayaForward',
    'HimalayaFolders',
    'HimalayaFolder',
    'HimalayaNextPage',
    'HimalayaPreviousPage',
    'HimalayaAttachments',
    'HimalayaFlagAdd',
    'HimalayaFlagRemove',
  }

  local function stub_all()
    package.loaded['himalaya'] = nil
    for key, _ in pairs(package.loaded) do
      if key:find('^himalaya%.') then
        package.loaded[key] = nil
      end
    end

    email_calls = {}
    compose_calls = {}
    folder_calls = {}
    thread_calls = {}

    package.loaded['himalaya.config'] = {
      setup = function() end,
      get = function()
        return { executable = 'sh', thread_view = false }
      end,
    }
    package.loaded['himalaya.log'] = { err = function() end }
    package.loaded['himalaya.domain.email'] = {
      list = function(acct)
        table.insert(email_calls, { 'list', acct })
      end,
      select_folder_then_copy = function()
        table.insert(email_calls, { 'select_folder_then_copy' })
      end,
      select_folder_then_move = function()
        table.insert(email_calls, { 'select_folder_then_move' })
      end,
      delete = function(l1, l2)
        table.insert(email_calls, { 'delete', l1, l2 })
      end,
      download_attachments = function()
        table.insert(email_calls, { 'download_attachments' })
      end,
      flag_add = function(l1, l2)
        table.insert(email_calls, { 'flag_add', l1, l2 })
      end,
      flag_remove = function(l1, l2)
        table.insert(email_calls, { 'flag_remove', l1, l2 })
      end,
    }
    package.loaded['himalaya.domain.email.compose'] = {
      write = function()
        table.insert(compose_calls, { 'write' })
      end,
      reply = function()
        table.insert(compose_calls, { 'reply' })
      end,
      reply_all = function()
        table.insert(compose_calls, { 'reply_all' })
      end,
      forward = function()
        table.insert(compose_calls, { 'forward' })
      end,
    }
    package.loaded['himalaya.domain.folder'] = {
      select = function()
        table.insert(folder_calls, { 'select' })
      end,
      set = function(name)
        table.insert(folder_calls, { 'set', name })
      end,
      select_next_page = function()
        table.insert(folder_calls, { 'select_next_page' })
      end,
      select_previous_page = function()
        table.insert(folder_calls, { 'select_previous_page' })
      end,
    }
    package.loaded['himalaya.state.account'] = {
      default = function()
        return ''
      end,
      list = function()
        return { 'acct1', 'acct2' }
      end,
      warmup = function() end,
    }
    package.loaded['himalaya.domain.email.thread_listing'] = {
      list = function(acct)
        table.insert(thread_calls, { 'list', acct })
      end,
    }
    package.loaded['himalaya.ui.listing'] = { setup = function() end }
    package.loaded['himalaya.ui.reading'] = { setup = function() end }
    package.loaded['himalaya.ui.writing'] = { setup = function() end }
    package.loaded['himalaya.ui.thread_listing'] = { setup = function() end }
  end

  before_each(function()
    stub_all()
    himalaya = require('himalaya')
    himalaya.register_commands()
  end)

  after_each(function()
    for _, name in ipairs(all_commands) do
      pcall(vim.api.nvim_del_user_command, name)
    end
  end)

  it('Himalaya command calls email.list in flat mode', function()
    vim.cmd('Himalaya')
    assert.are.equal(1, #email_calls)
    assert.are.equal('list', email_calls[1][1])
  end)

  it('Himalaya command calls thread_listing.list in thread mode', function()
    package.loaded['himalaya.config'].get = function()
      return { executable = 'sh', thread_view = true }
    end
    package.loaded['himalaya'] = nil
    himalaya = require('himalaya')
    -- Re-register to pick up new config
    for _, name in ipairs(all_commands) do
      pcall(vim.api.nvim_del_user_command, name)
    end
    himalaya.register_commands()

    vim.cmd('Himalaya')
    assert.are.equal(1, #thread_calls)
    assert.are.equal('list', thread_calls[1][1])
  end)

  it('Himalaya command passes account argument', function()
    vim.cmd('Himalaya acct1')
    assert.are.equal('acct1', email_calls[1][2])
  end)

  it('HimalayaCopy calls select_folder_then_copy', function()
    vim.cmd('HimalayaCopy')
    assert.are.equal(1, #email_calls)
    assert.are.equal('select_folder_then_copy', email_calls[1][1])
  end)

  it('HimalayaMove calls select_folder_then_move', function()
    vim.cmd('HimalayaMove')
    assert.are.equal(1, #email_calls)
    assert.are.equal('select_folder_then_move', email_calls[1][1])
  end)

  it('HimalayaDelete calls email.delete', function()
    vim.cmd('HimalayaDelete')
    assert.are.equal(1, #email_calls)
    assert.are.equal('delete', email_calls[1][1])
  end)

  it('HimalayaWrite calls compose.write', function()
    vim.cmd('HimalayaWrite')
    assert.are.equal(1, #compose_calls)
    assert.are.equal('write', compose_calls[1][1])
  end)

  it('HimalayaReply calls compose.reply', function()
    vim.cmd('HimalayaReply')
    assert.are.equal(1, #compose_calls)
    assert.are.equal('reply', compose_calls[1][1])
  end)

  it('HimalayaReplyAll calls compose.reply_all', function()
    vim.cmd('HimalayaReplyAll')
    assert.are.equal(1, #compose_calls)
    assert.are.equal('reply_all', compose_calls[1][1])
  end)

  it('HimalayaForward calls compose.forward', function()
    vim.cmd('HimalayaForward')
    assert.are.equal(1, #compose_calls)
    assert.are.equal('forward', compose_calls[1][1])
  end)

  it('HimalayaFolders calls folder.select', function()
    vim.cmd('HimalayaFolders')
    assert.are.equal(1, #folder_calls)
    assert.are.equal('select', folder_calls[1][1])
  end)

  it('HimalayaFolder calls folder.set with argument', function()
    vim.cmd('HimalayaFolder Sent')
    assert.are.equal(1, #folder_calls)
    assert.are.equal('set', folder_calls[1][1])
    assert.are.equal('Sent', folder_calls[1][2])
  end)

  it('HimalayaNextPage calls folder.select_next_page', function()
    vim.cmd('HimalayaNextPage')
    assert.are.equal(1, #folder_calls)
    assert.are.equal('select_next_page', folder_calls[1][1])
  end)

  it('HimalayaPreviousPage calls folder.select_previous_page', function()
    vim.cmd('HimalayaPreviousPage')
    assert.are.equal(1, #folder_calls)
    assert.are.equal('select_previous_page', folder_calls[1][1])
  end)

  it('HimalayaAttachments calls email.download_attachments', function()
    vim.cmd('HimalayaAttachments')
    assert.are.equal(1, #email_calls)
    assert.are.equal('download_attachments', email_calls[1][1])
  end)

  it('HimalayaFlagAdd calls email.flag_add', function()
    vim.cmd('HimalayaFlagAdd')
    assert.are.equal(1, #email_calls)
    assert.are.equal('flag_add', email_calls[1][1])
  end)

  it('HimalayaFlagRemove calls email.flag_remove', function()
    vim.cmd('HimalayaFlagRemove')
    assert.are.equal(1, #email_calls)
    assert.are.equal('flag_remove', email_calls[1][1])
  end)

  describe('Himalaya command completion', function()
    it('returns all accounts for empty arg_lead', function()
      local completions = vim.fn.getcompletion('Himalaya ', 'cmdline')
      assert.is_true(#completions >= 2)
    end)

    it('filters accounts by prefix', function()
      local completions = vim.fn.getcompletion('Himalaya acct1', 'cmdline')
      assert.is_true(#completions >= 1)
    end)
  end)
end)

describe('himalaya filetype autocmd callbacks', function()
  local himalaya
  local setup_calls

  local all_commands = {
    'Himalaya',
    'HimalayaCopy',
    'HimalayaMove',
    'HimalayaDelete',
    'HimalayaWrite',
    'HimalayaReply',
    'HimalayaReplyAll',
    'HimalayaForward',
    'HimalayaFolders',
    'HimalayaFolder',
    'HimalayaNextPage',
    'HimalayaPreviousPage',
    'HimalayaAttachments',
    'HimalayaFlagAdd',
    'HimalayaFlagRemove',
  }

  before_each(function()
    for key, _ in pairs(package.loaded) do
      if key:find('^himalaya%.') then
        package.loaded[key] = nil
      end
    end

    setup_calls = {}

    package.loaded['himalaya.config'] = {
      setup = function() end,
      get = function()
        return { executable = 'sh', thread_view = false }
      end,
    }
    package.loaded['himalaya.log'] = { err = function() end }
    package.loaded['himalaya.domain.email'] = {
      list = function() end,
      select_folder_then_copy = function() end,
      select_folder_then_move = function() end,
      delete = function() end,
      download_attachments = function() end,
      flag_add = function() end,
      flag_remove = function() end,
    }
    package.loaded['himalaya.domain.email.compose'] = {
      write = function() end,
      reply = function() end,
      reply_all = function() end,
      forward = function() end,
    }
    package.loaded['himalaya.domain.folder'] = {
      select = function() end,
      set = function() end,
      select_next_page = function() end,
      select_previous_page = function() end,
    }
    package.loaded['himalaya.state.account'] = {
      default = function()
        return ''
      end,
      list = function()
        return {}
      end,
      warmup = function() end,
    }
    package.loaded['himalaya.domain.email.thread_listing'] = {
      list = function() end,
    }
    package.loaded['himalaya.ui.listing'] = {
      setup = function(buf)
        table.insert(setup_calls, { 'listing', buf })
      end,
    }
    package.loaded['himalaya.ui.reading'] = {
      setup = function(buf)
        table.insert(setup_calls, { 'reading', buf })
      end,
    }
    package.loaded['himalaya.ui.writing'] = {
      setup = function(buf)
        table.insert(setup_calls, { 'writing', buf })
      end,
    }
    package.loaded['himalaya.ui.thread_listing'] = {
      setup = function(buf)
        table.insert(setup_calls, { 'thread_listing', buf })
      end,
    }

    himalaya = require('himalaya')
    himalaya.register_filetypes()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, 'himalaya')
    for _, name in ipairs(all_commands) do
      pcall(vim.api.nvim_del_user_command, name)
    end
  end)

  it('triggers listing setup on himalaya-email-listing filetype', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'himalaya-email-listing'
    local found = false
    for _, call in ipairs(setup_calls) do
      if call[1] == 'listing' and call[2] == buf then
        found = true
      end
    end
    assert.is_true(found)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('triggers reading setup on himalaya-email-reading filetype', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'himalaya-email-reading'
    local found = false
    for _, call in ipairs(setup_calls) do
      if call[1] == 'reading' and call[2] == buf then
        found = true
      end
    end
    assert.is_true(found)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('triggers writing setup on himalaya-email-writing filetype', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'himalaya-email-writing'
    local found = false
    for _, call in ipairs(setup_calls) do
      if call[1] == 'writing' and call[2] == buf then
        found = true
      end
    end
    assert.is_true(found)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('triggers thread_listing setup on himalaya-thread-listing filetype', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'himalaya-thread-listing'
    local found = false
    for _, call in ipairs(setup_calls) do
      if call[1] == 'thread_listing' and call[2] == buf then
        found = true
      end
    end
    assert.is_true(found)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
