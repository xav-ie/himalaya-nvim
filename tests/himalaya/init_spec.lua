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
      list = function()
        return {}
      end,
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
