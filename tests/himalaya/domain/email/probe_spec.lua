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
      probe.set_total_from_data(key, 1, 50, 25)  -- simulate partial
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
            opts.on_data({{}, {}, {}})
          else
            local full = {}
            for i = 1, page_size do full[i] = {} end
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
      assert.are.same({2, 4, 8, 10}, probed_pages)
    end)

    it('uses exponential doubling from page 3', function()
      local p = setup_mock()
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 3, '', bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.are.same({4, 8, 10}, probed_pages)
    end)

    it('stops on partial page during doubling', function()
      local p = setup_mock(4)
      local bufnr = vim.api.nvim_create_buf(false, true)
      p.start('acct', 'inbox', 50, 1, '', bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.are.same({2, 4}, probed_pages)
      assert.are.equal(153, p.total_count('acct\0inbox\0'))
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
  end)
end)
