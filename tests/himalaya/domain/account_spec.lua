describe('himalaya.domain.account', function()
  local account
  local pickers_select_args

  before_each(function()
    package.loaded['himalaya.domain.account'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.context'] = nil
    package.loaded['himalaya.pickers'] = nil
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.domain.email.thread_listing'] = nil

    pickers_select_args = {}

    package.loaded['himalaya.pickers'] = {
      select = function(callback, items)
        pickers_select_args = { callback = callback, items = items }
      end,
    }

    vim.b.himalaya_buffer_type = nil
    vim.b.himalaya_account = nil
    vim.b.himalaya_folder = nil
  end)

  describe('open_picker', function()
    it('rotates so next account after current is first', function()
      vim.b.himalaya_account = 'B'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      account = require('himalaya.domain.account')

      account.open_picker(function() end)

      local names = {}
      for _, item in ipairs(pickers_select_args.items) do
        names[#names + 1] = item.name
      end
      assert.are.same({ 'C', 'A', 'B (current)' }, names)
    end)

    it('rotates when current is first account', function()
      vim.b.himalaya_account = 'A'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      account = require('himalaya.domain.account')

      account.open_picker(function() end)

      local names = {}
      for _, item in ipairs(pickers_select_args.items) do
        names[#names + 1] = item.name
      end
      assert.are.same({ 'B', 'C', 'A (current)' }, names)
    end)

    it('wraps around when current is last account', function()
      vim.b.himalaya_account = 'C'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      account = require('himalaya.domain.account')

      account.open_picker(function() end)

      local names = {}
      for _, item in ipairs(pickers_select_args.items) do
        names[#names + 1] = item.name
      end
      assert.are.same({ 'A', 'B', 'C (current)' }, names)
    end)

    it('handles a single account', function()
      vim.b.himalaya_account = 'only'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'only' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      account = require('himalaya.domain.account')

      account.open_picker(function() end)

      assert.are.equal(1, #pickers_select_args.items)
      assert.are.equal('only (current)', pickers_select_args.items[1].name)
    end)

    it('preserves order when current is not in list', function()
      vim.b.himalaya_account = 'D'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      account = require('himalaya.domain.account')

      account.open_picker(function() end)

      local names = {}
      for _, item in ipairs(pickers_select_args.items) do
        names[#names + 1] = item.name
      end
      assert.are.same({ 'A', 'B', 'C' }, names)
    end)

    it('wrapper strips (current) suffix before passing to callback', function()
      vim.b.himalaya_account = 'X'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'X' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      account = require('himalaya.domain.account')

      local received
      account.open_picker(function(name)
        received = name
      end)

      -- Simulate picker returning the annotated name
      pickers_select_args.callback('X (current)')
      assert.are.equal('X', received)
    end)
  end)

  describe('select', function()
    it('dispatches to email.list when buffer type is not thread-listing', function()
      local email_list_arg
      vim.b.himalaya_account = 'acct1'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'acct1' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      package.loaded['himalaya.domain.email'] = {
        list = function(name)
          email_list_arg = name
        end,
      }
      package.loaded['himalaya.domain.email.thread_listing'] = {
        list = function() end,
      }
      account = require('himalaya.domain.account')

      vim.b.himalaya_buffer_type = 'email-listing'
      account.select()

      -- Invoke the callback that select() passed to open_picker
      pickers_select_args.callback('acct1')
      assert.are.equal('acct1', email_list_arg)
    end)

    it('dispatches to thread_listing.list when buffer type is thread-listing', function()
      local thread_list_arg
      vim.b.himalaya_account = 'acct1'
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'acct1' })
        end,
      }
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
        end,
      }
      package.loaded['himalaya.domain.email'] = {
        list = function() end,
      }
      package.loaded['himalaya.domain.email.thread_listing'] = {
        list = function(name)
          thread_list_arg = name
        end,
      }
      account = require('himalaya.domain.account')

      vim.b.himalaya_buffer_type = 'thread-listing'
      account.select()

      pickers_select_args.callback('acct1')
      assert.are.equal('acct1', thread_list_arg)
    end)
  end)
end)
