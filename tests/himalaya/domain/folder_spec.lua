describe('himalaya.domain.folder', function()
  local folder_domain

  before_each(function()
    package.loaded['himalaya.domain.folder'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.context'] = nil
    package.loaded['himalaya.config'] = nil
    require('himalaya.config')._reset()
    folder_domain = require('himalaya.domain.folder')

    vim.b.himalaya_folder = nil
    vim.b.himalaya_page = nil
    vim.b.himalaya_page_size = nil
  end)

  it('exposes open_picker, select, and set functions', function()
    assert.is_function(folder_domain.open_picker)
    assert.is_function(folder_domain.select)
    assert.is_function(folder_domain.set)
  end)

  it('set updates buffer folder and resets page', function()
    vim.b.himalaya_page = 3
    -- stub email.list to avoid actual request
    package.loaded['himalaya.domain.email'] = { list = function() end }
    folder_domain.set('Sent')
    assert.are.equal('Sent', vim.b.himalaya_folder)
    assert.are.equal(1, vim.b.himalaya_page)
  end)

  describe('select_previous_page', function()
    it('shows warning on first page', function()
      local notifications = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      folder_domain.select_previous_page()
      vim.notify = orig_notify
      assert.are.equal(1, #notifications)
      assert.is_truthy(notifications[1].msg:find('Already on first page'))
      assert.are.equal(vim.log.levels.WARN, notifications[1].level)
    end)
  end)

  describe('select_next_page', function()
    it('shows warning when page is partial', function()
      -- Simulate a listing buffer with page_size set and fewer lines than page_size
      vim.b.himalaya_page_size = 20
      local orig_count = vim.api.nvim_buf_line_count
      vim.api.nvim_buf_line_count = function()
        return 10
      end

      local notifications = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      folder_domain.select_next_page()
      vim.notify = orig_notify
      vim.api.nvim_buf_line_count = orig_count
      vim.b.himalaya_page_size = nil

      assert.are.equal(1, #notifications)
      assert.is_truthy(notifications[1].msg:find('Already on last page'))
      assert.are.equal(vim.log.levels.WARN, notifications[1].level)
    end)

    it('does nothing without page_size', function()
      vim.b.himalaya_page_size = nil
      local cmds = {}
      local orig_cmd = vim.cmd
      vim.cmd = function(s)
        table.insert(cmds, s)
      end
      folder_domain.select_next_page()
      vim.cmd = orig_cmd
      assert.are.equal(0, #cmds)
    end)
  end)
end)

describe('himalaya.domain.folder (extended)', function()
  local folder_domain
  local captured_json
  local picker_items
  local email_list_calls
  local thread_listing_calls
  local orig_notify

  before_each(function()
    package.loaded['himalaya.domain.folder'] = nil
    package.loaded['himalaya.request'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.context'] = nil
    package.loaded['himalaya.pickers'] = nil
    package.loaded['himalaya.log'] = nil
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.domain.email.thread_listing'] = nil
    package.loaded['himalaya.domain.email.probe'] = nil
    package.loaded['himalaya.events'] = nil

    captured_json = nil
    picker_items = nil
    email_list_calls = {}
    thread_listing_calls = {}

    package.loaded['himalaya.request'] = {
      json = function(opts)
        captured_json = opts
      end,
      plain = function() end,
    }
    package.loaded['himalaya.state.account'] = {
      flag = function(acct)
        if acct == '' then
          return ''
        end
        return '--account ' .. acct
      end,
    }
    package.loaded['himalaya.state.context'] = {
      resolve = function()
        return 'test-acct', 'INBOX'
      end,
    }
    package.loaded['himalaya.pickers'] = {
      select = function(cb, items)
        picker_items = items
        -- Auto-select the first item
        if items and #items > 0 then
          cb(items[1].name or items[1])
        end
      end,
    }
    package.loaded['himalaya.log'] = {
      info = function(msg)
        vim.notify(msg, vim.log.levels.INFO)
      end,
      warn = function(msg)
        vim.notify(msg, vim.log.levels.WARN)
      end,
      err = function(msg)
        vim.notify(msg, vim.log.levels.ERROR)
      end,
      debug = function() end,
    }
    package.loaded['himalaya.domain.email'] = {
      list = function(...)
        table.insert(email_list_calls, { ... })
      end,
    }
    package.loaded['himalaya.domain.email.thread_listing'] = {
      list = function()
        table.insert(thread_listing_calls, 'list')
      end,
      next_page = function()
        table.insert(thread_listing_calls, 'next_page')
      end,
      previous_page = function()
        table.insert(thread_listing_calls, 'previous_page')
      end,
    }
    package.loaded['himalaya.events'] = {
      emit = function() end,
      _reset = function() end,
    }

    orig_notify = vim.notify
    vim.notify = function() end

    folder_domain = require('himalaya.domain.folder')
    vim.b.himalaya_folder = nil
    vim.b.himalaya_page = nil
    vim.b.himalaya_page_size = nil
    vim.b.himalaya_buffer_type = nil
    vim.b.himalaya_cache_key = nil
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.b.himalaya_folder = nil
    vim.b.himalaya_page = nil
    vim.b.himalaya_page_size = nil
    vim.b.himalaya_buffer_type = nil
    vim.b.himalaya_cache_key = nil
  end)

  describe('open_picker', function()
    it('fetches folders via request.json on cache miss', function()
      folder_domain.open_picker(function() end)
      assert.is_not_nil(captured_json)
      assert.is_truthy(captured_json.cmd:find('folder list'))

      -- Simulate server response
      captured_json.on_data({
        { name = 'INBOX' },
        { name = 'Sent' },
        { name = 'Drafts' },
      })
      -- Picker should have been called with rotated folders
      assert.is_not_nil(picker_items)
      assert.are.equal(3, #picker_items)
    end)

    it('uses cache on second call', function()
      -- First call: cache miss
      folder_domain.open_picker(function() end)
      assert.is_not_nil(captured_json)
      captured_json.on_data({
        { name = 'INBOX' },
        { name = 'Sent' },
      })

      -- Second call: should use cache (no new json request)
      captured_json = nil
      folder_domain.open_picker(function() end)
      assert.is_nil(captured_json)
      assert.is_not_nil(picker_items)
    end)

    it('rotates folders placing current last and marking it', function()
      folder_domain.open_picker(function() end)
      captured_json.on_data({
        { name = 'Drafts' },
        { name = 'INBOX' },
        { name = 'Sent' },
      })
      -- After sorting alphabetically: Drafts, INBOX, Sent
      -- Current is INBOX, so rotation starts after INBOX: Sent, Drafts, INBOX (current)
      -- Check that one item has " (current)" suffix
      local found_current = false
      for _, f in ipairs(picker_items) do
        if f.name:find('%(current%)') then
          found_current = true
        end
      end
      assert.is_true(found_current)
    end)

    it('strips (current) suffix before passing to callback', function()
      local chosen
      -- Make picker select the item with (current) suffix
      package.loaded['himalaya.pickers'].select = function(cb, items)
        picker_items = items
        for _, f in ipairs(items) do
          if f.name:find('%(current%)') then
            cb(f.name)
            return
          end
        end
        cb(items[1].name)
      end
      -- Re-require to pick up new picker stub
      package.loaded['himalaya.domain.folder'] = nil
      folder_domain = require('himalaya.domain.folder')

      folder_domain.open_picker(function(f)
        chosen = f
      end)
      captured_json.on_data({
        { name = 'INBOX' },
        { name = 'Sent' },
      })
      -- chosen should NOT have " (current)" suffix
      assert.is_not_nil(chosen)
      assert.is_falsy(chosen:find('%(current%)'))
    end)
  end)

  describe('select', function()
    it('calls set for non-thread buffer', function()
      vim.b.himalaya_buffer_type = nil
      folder_domain.select()
      assert.is_not_nil(captured_json)
      captured_json.on_data({
        { name = 'Archive' },
        { name = 'INBOX' },
      })
      -- set() should have been called which triggers email.list
      assert.are.equal(1, #email_list_calls)
    end)

    it('updates folder and calls thread_listing.list for thread buffer', function()
      vim.b.himalaya_buffer_type = 'thread-listing'
      folder_domain.select()
      assert.is_not_nil(captured_json)
      captured_json.on_data({
        { name = 'Archive' },
        { name = 'INBOX' },
      })
      assert.are.equal(1, #thread_listing_calls)
      assert.are.equal('list', thread_listing_calls[1])
      assert.are.equal(1, vim.b.himalaya_page)
    end)
  end)

  describe('select_next_page extended', function()
    it('delegates to thread_listing for thread buffer', function()
      vim.b.himalaya_buffer_type = 'thread-listing'
      folder_domain.select_next_page()
      assert.are.equal(1, #thread_listing_calls)
      assert.are.equal('next_page', thread_listing_calls[1])
    end)

    it('advances page when buffer is full', function()
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_page = 1
      -- Need line count >= page_size
      local lines = {}
      for i = 1, 10 do
        lines[i] = string.format('line %d', i)
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      folder_domain.select_next_page()
      assert.are.equal(2, vim.b.himalaya_page)
      assert.are.equal(1, #email_list_calls)
    end)

    it('warns on last page when probe knows total', function()
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_page = 2
      vim.b.himalaya_cache_key = 'test-key'
      -- Need line count >= page_size to pass partial-page check
      local lines = {}
      for i = 1, 10 do
        lines[i] = string.format('line %d', i)
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      -- Stub probe.total_count to return total that means page 2 is last
      package.loaded['himalaya.domain.email.probe'] = {
        total_count = function()
          return 20
        end,
      }

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      folder_domain.select_next_page()
      assert.are.equal(1, #notifications)
      assert.is_truthy(notifications[1].msg:find('Already on last page'))
      -- Page should NOT have advanced
      assert.are.equal(2, vim.b.himalaya_page)
    end)

    it('advances when probe total allows more pages', function()
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_page = 1
      vim.b.himalaya_cache_key = 'test-key'
      local lines = {}
      for i = 1, 10 do
        lines[i] = string.format('line %d', i)
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      package.loaded['himalaya.domain.email.probe'] = {
        total_count = function()
          return 30
        end,
      }

      folder_domain.select_next_page()
      assert.are.equal(2, vim.b.himalaya_page)
      assert.are.equal(1, #email_list_calls)
    end)

    it('advances when probe total is nil (unknown)', function()
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_page = 1
      vim.b.himalaya_cache_key = 'test-key'
      local lines = {}
      for i = 1, 10 do
        lines[i] = string.format('line %d', i)
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      package.loaded['himalaya.domain.email.probe'] = {
        total_count = function()
          return nil
        end,
      }

      folder_domain.select_next_page()
      assert.are.equal(2, vim.b.himalaya_page)
    end)
  end)

  describe('select_previous_page extended', function()
    it('delegates to thread_listing for thread buffer', function()
      vim.b.himalaya_buffer_type = 'thread-listing'
      folder_domain.select_previous_page()
      assert.are.equal(1, #thread_listing_calls)
      assert.are.equal('previous_page', thread_listing_calls[1])
    end)

    it('goes to previous page when page > 1', function()
      vim.b.himalaya_page = 3
      folder_domain.select_previous_page()
      assert.are.equal(2, vim.b.himalaya_page)
      assert.are.equal(1, #email_list_calls)
    end)

    it('does not go below page 1', function()
      vim.b.himalaya_page = 1
      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      folder_domain.select_previous_page()
      assert.are.equal(1, #notifications)
      assert.is_truthy(notifications[1].msg:find('Already on first page'))
    end)
  end)

  describe('set', function()
    it('emits FolderChanged event and calls email.list', function()
      local emitted = {}
      package.loaded['himalaya.events'].emit = function(event, data)
        table.insert(emitted, { event = event, data = data })
      end
      vim.b.himalaya_account = 'my-acct'
      folder_domain.set('Sent')
      assert.are.equal('Sent', vim.b.himalaya_folder)
      assert.are.equal(1, vim.b.himalaya_page)
      assert.are.equal(1, #emitted)
      assert.are.equal('FolderChanged', emitted[1].event)
      assert.are.equal('Sent', emitted[1].data.folder)
      assert.are.equal('my-acct', emitted[1].data.account)
      assert.are.equal(1, #email_list_calls)
    end)
  end)
end)
