describe('himalaya.domain.account', function()
  local account
  local pickers_select_args

  before_each(function()
    package.loaded['himalaya.domain.account'] = nil
    package.loaded['himalaya.state.account'] = nil
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
  end)

  describe('open_picker', function()
    it('rotates so next account after current is first', function()
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
        current = function()
          return 'B'
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
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
        current = function()
          return 'A'
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
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
        current = function()
          return 'C'
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
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'only' })
        end,
        current = function()
          return 'only'
        end,
      }
      account = require('himalaya.domain.account')

      account.open_picker(function() end)

      assert.are.equal(1, #pickers_select_args.items)
      assert.are.equal('only (current)', pickers_select_args.items[1].name)
    end)

    it('preserves order when current is not in list', function()
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'A', 'B', 'C' })
        end,
        current = function()
          return 'D'
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
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'X' })
        end,
        current = function()
          return 'X'
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
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'acct1' })
        end,
        current = function()
          return 'acct1'
        end,
        select = function() end,
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
      local thread_list_called = false
      local account_select_arg
      package.loaded['himalaya.state.account'] = {
        list_async = function(cb)
          cb({ 'acct1' })
        end,
        current = function()
          return 'acct1'
        end,
        select = function(name)
          account_select_arg = name
        end,
      }
      package.loaded['himalaya.domain.email'] = {
        list = function() end,
      }
      package.loaded['himalaya.domain.email.thread_listing'] = {
        list = function()
          thread_list_called = true
        end,
      }
      account = require('himalaya.domain.account')

      vim.b.himalaya_buffer_type = 'thread-listing'
      account.select()

      pickers_select_args.callback('acct1')
      assert.are.equal('acct1', account_select_arg)
      assert.is_true(thread_list_called)
    end)
  end)
end)
