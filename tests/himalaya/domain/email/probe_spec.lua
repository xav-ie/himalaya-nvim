describe('himalaya.domain.email.probe', function()
  local probe

  before_each(function()
    package.loaded['himalaya.domain.email.probe'] = nil
    package.loaded['himalaya.request'] = nil
    -- Stub request module (probe requires it at load time)
    package.loaded['himalaya.request'] = { json = function() end }
    probe = require('himalaya.domain.email.probe')
  end)

  describe('set_total_from_data', function()
    it('sets exact total from partial page', function()
      local key = 'acct\0folder\0'
      probe.set_total_from_data(key, 1, 50, 30)
      assert.are.equal(30, probe.total_count(key))
    end)

    it('sets exact total from partial page on page 2', function()
      local key = 'acct\0folder\0'
      probe.set_total_from_data(key, 2, 50, 20)
      assert.are.equal(70, probe.total_count(key))
    end)

    it('does not set total from full page (unknown)', function()
      local key = 'acct\0folder\0'
      probe.set_total_from_data(key, 1, 50, 50)
      assert.is_nil(probe.total_count(key))
    end)

    it('overwrites stale total with fresh partial page', function()
      local key = 'acct\0folder\0'
      -- Old visit: 30 emails
      probe.set_total_from_data(key, 1, 50, 30)
      assert.are.equal(30, probe.total_count(key))
      -- New visit: 45 emails (partial page again)
      probe.set_total_from_data(key, 1, 50, 45)
      assert.are.equal(45, probe.total_count(key))
    end)

    it('invalidates stale total when full page exceeds cached count', function()
      local key = 'acct\0folder\0'
      -- Previous visit determined total = 30
      probe.set_total_from_data(key, 1, 50, 30)
      assert.are.equal(30, probe.total_count(key))
      -- New visit: full page of 50 returned → at least 50 emails, but cache says 30
      probe.set_total_from_data(key, 1, 50, 50)
      assert.is_nil(probe.total_count(key))
    end)

    it('keeps valid total when full page is within cached count', function()
      local key = 'acct\0folder\0'
      -- Previous probe determined total = 75
      probe.set_total_from_data(key, 1, 50, 25) -- simulate partial
      -- Actually set it to 75 as if probe found it
      -- Use set_total_from_data on page 2 partial
      probe.set_total_from_data(key, 2, 50, 25)
      assert.are.equal(75, probe.total_count(key))
      -- Revisit: full page of 50 → at least 50, cache says 75 → valid
      probe.set_total_from_data(key, 1, 50, 50)
      assert.are.equal(75, probe.total_count(key))
    end)
  end)

  describe('reset_if_changed', function()
    it('preserves totals across folder changes', function()
      local key1 = 'acct\0inbox\0'
      local key2 = 'acct\0drafts\0'
      probe.set_total_from_data(key1, 1, 50, 30)
      probe.reset_if_changed('acct', 'drafts', '')
      probe.set_total_from_data(key2, 1, 50, 5)
      -- Both totals should still exist
      assert.are.equal(30, probe.total_count(key1))
      assert.are.equal(5, probe.total_count(key2))
    end)

    it('preserves totals across account changes', function()
      local key1 = 'acct1\0inbox\0'
      local key2 = 'acct2\0inbox\0'
      probe.set_total_from_data(key1, 1, 50, 30)
      probe.reset_if_changed('acct2', 'inbox', '')
      probe.set_total_from_data(key2, 1, 50, 10)
      assert.are.equal(30, probe.total_count(key1))
      assert.are.equal(10, probe.total_count(key2))
    end)
  end)

  describe('probe sequence', function()
    local probed_pages

    local function setup_mock(partial_at)
      probed_pages = {}
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          local probe_page = opts.args[4]
          local page_size = opts.args[3]
          table.insert(probed_pages, probe_page)
          if partial_at and probe_page == partial_at then
            opts.on_data({ {}, {}, {} })
          else
            local full = {}
            for i = 1, page_size do
              full[i] = {}
            end
            opts.on_data(full)
          end
          return {}
        end,
      }
      return require('himalaya.domain.email.probe')
    end

    it('uses exponential doubling from page 1', function()
      local p = setup_mock()
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.are.same({ 2, 4, 8, 10 }, probed_pages)
    end)

    it('uses exponential doubling from page 3', function()
      local p = setup_mock()
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 3, '', bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.are.same({ 4, 8, 10 }, probed_pages)
    end)

    it('stops on partial page during doubling', function()
      local p = setup_mock(4)
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.are.same({ 2, 4 }, probed_pages)
      assert.are.equal(153, p.total_count('acct\0inbox\0'))
    end)
  end)

  describe('stale-job handling', function()
    it('bails out and calls cancel callback when generation changes', function()
      local captured_on_data
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          captured_on_data = opts.on_data
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)

      -- cancel() increments generation, making the captured callback stale
      local cancel_called = false
      p.cancel(function()
        cancel_called = true
      end)

      -- Invoke the now-stale on_data — should bail out
      local full_page = {}
      for i = 1, 50 do
        full_page[i] = {}
      end
      captured_on_data(full_page)

      assert.is_true(cancel_called)
      assert.is_nil(p.total_count('acct\0inbox\0'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does not bail out when generation is current', function()
      local captured_on_data
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          captured_on_data = opts.on_data
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)

      -- Invoke on_data without cancelling — should process normally
      -- Return partial page (3 items) to set exact total
      captured_on_data({ {}, {}, {} })

      -- Total should be (2-1)*50 + 3 = 53
      assert.are.equal(53, p.total_count('acct\0inbox\0'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('cleanup', function()
    it('clears the totals cache', function()
      local key = 'acct\0folder\0'
      probe.set_total_from_data(key, 1, 50, 30)
      assert.are.equal(30, probe.total_count(key))
      probe.cleanup()
      assert.is_nil(probe.total_count(key))
    end)
  end)

  describe('total_pages_str', function()
    it('returns ? when unknown', function()
      assert.are.equal('?', probe.total_pages_str('unknown\0key\0', 50))
    end)

    it('returns correct page count', function()
      probe.set_total_from_data('k\0f\0', 1, 50, 30)
      assert.are.equal('1', probe.total_pages_str('k\0f\0', 50))
    end)

    it('rounds up partial pages', function()
      probe.set_total_from_data('k\0f\0', 2, 50, 20)
      assert.are.equal('2', probe.total_pages_str('k\0f\0', 50))
    end)

    it('returns page count with + suffix for negative (approximate) totals', function()
      -- Simulate hitting page 10 cap which sets negative total
      local probed_pages = {}
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          local probe_page = opts.args[4]
          local page_size = opts.args[3]
          table.insert(probed_pages, probe_page)
          -- Always return full pages to hit the cap
          local full = {}
          for i = 1, page_size do
            full[i] = {}
          end
          opts.on_data(full)
          return {}
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'folder', 50, 1, '', bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })

      local key = 'acct\0folder\0'
      -- Should return "10+" (500 items / 50 per page = 10, with + suffix)
      assert.are.equal('10+', p.total_pages_str(key, 50))
      -- total_count returns nil for negative totals
      assert.is_nil(p.total_count(key))
    end)
  end)

  describe('cancel without job', function()
    it('calls callback immediately when no job is running', function()
      local called = false
      probe.cancel(function()
        called = true
      end)
      assert.is_true(called)
    end)

    it('returns without error when no job and no callback', function()
      probe.cancel()
    end)
  end)

  describe('cancel with existing on_cancel_cb', function()
    it('fires old callback before setting new one', function()
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(_opts)
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)

      -- First cancel sets on_cancel_cb
      local first_called = false
      p.cancel(function()
        first_called = true
      end)

      -- Second cancel should fire the first callback before setting new one
      local second_called = false
      p.cancel(function()
        second_called = true
      end)

      assert.is_true(first_called)
      -- The second callback is now queued, not yet fired
      assert.is_false(second_called)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('cancel_sync with active job', function()
    it('kills the job synchronously', function()
      local kill_called = false
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.job'] = nil
      package.loaded['himalaya.request'] = {
        json = function(_opts)
          return { kill = function() end }
        end,
      }
      package.loaded['himalaya.job'] = {
        kill_and_wait = function()
          kill_called = true
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)
      p.cancel_sync()
      assert.is_true(kill_called)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('on_error callback', function()
    it('clears job and fires cancel callback', function()
      local captured_on_error
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          captured_on_error = opts.on_error
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)

      -- Set a cancel callback
      local cancel_called = false
      p.cancel(function()
        cancel_called = true
      end)

      -- on_error should fire the cancel callback
      captured_on_error()
      assert.is_true(cancel_called)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears job without cancel callback', function()
      local captured_on_error
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          captured_on_error = opts.on_error
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)

      -- on_error without cancel callback should not error
      captured_on_error()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('restart', function()
    it('re-runs probe with saved args after cancel', function()
      -- Use a synchronous mock: request.json calls on_data inline
      local probed_pages = {}
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          local probe_page = opts.args[4]
          table.insert(probed_pages, probe_page)
          -- Don't call on_data — leave job pending so cancel saves args
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Start probe (leaves job pending because on_data is not called)
      p.start('acct', 'inbox', 50, 1, '', bufnr)
      assert.are.same({ 2 }, probed_pages)

      -- Cancel preserves saved_args
      p.cancel()

      -- Restart should re-run with saved args (page 2 again)
      p.restart()
      assert.are.equal(2, #probed_pages) -- original page 2, then restarted page 2

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does nothing when no saved args', function()
      -- restart without any prior start should be a no-op
      probe.restart()
    end)
  end)

  describe('buffer rename on probe completion', function()
    it('renames buffer with page count on probe completion', function()
      local captured_on_data
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          captured_on_data = opts.on_data
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.b[bufnr].himalaya_page = 1
      vim.b[bufnr].himalaya_page_size = 50

      p.start('acct', 'folder', 50, 1, '', bufnr)

      -- Return partial page to trigger rename logic
      -- Suppress redraw in test
      local orig_cmd = vim.cmd
      local cmds = {}
      vim.cmd = function(c)
        table.insert(cmds, c)
      end

      captured_on_data({ {}, {}, {} })

      vim.cmd = orig_cmd

      local name = vim.api.nvim_buf_get_name(bufnr)
      assert.truthy(name:find('Himalaya/envelopes'))
      assert.truthy(name:find('folder'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('renames buffer with query display', function()
      local captured_on_data
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          captured_on_data = opts.on_data
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.b[bufnr].himalaya_page = 1
      vim.b[bufnr].himalaya_page_size = 50

      p.start('acct', 'INBOX', 50, 1, 'subject hello', bufnr)

      local orig_cmd = vim.cmd
      vim.cmd = function() end

      captured_on_data({ {}, {} })

      vim.cmd = orig_cmd

      local name = vim.api.nvim_buf_get_name(bufnr)
      assert.truthy(name:find('subject hello'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('wipes stale envelope buffers that conflict with rename', function()
      local captured_on_data
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function(opts)
          captured_on_data = opts.on_data
          return { kill = function() end }
        end,
      }
      local p = require('himalaya.domain.email.probe')

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.b[bufnr].himalaya_page = 1
      vim.b[bufnr].himalaya_page_size = 50

      -- Create a stale buffer with conflicting name
      local stale_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(stale_buf, 'Himalaya/envelopes [old]')

      p.start('acct', 'INBOX', 50, 1, '', bufnr)

      local orig_cmd = vim.cmd
      local wiped = {}
      vim.cmd = function(c)
        if type(c) == 'string' and c:find('bwipeout') then
          table.insert(wiped, c)
        end
      end

      captured_on_data({ {}, {} })

      vim.cmd = orig_cmd

      assert.is_true(#wiped > 0)

      -- Clean up
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      if vim.api.nvim_buf_is_valid(stale_buf) then
        vim.api.nvim_buf_delete(stale_buf, { force = true })
      end
    end)
  end)

  describe('start skips when total is cached', function()
    it('does not probe when total is already known', function()
      local json_called = false
      package.loaded['himalaya.domain.email.probe'] = nil
      package.loaded['himalaya.request'] = nil
      package.loaded['himalaya.request'] = {
        json = function()
          json_called = true
          return {}
        end,
      }
      local p = require('himalaya.domain.email.probe')
      local key = 'acct\0folder\0'
      p.set_total_from_data(key, 1, 50, 30) -- sets total = 30
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'folder', 50, 1, '', bufnr)
      assert.is_false(json_called)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
