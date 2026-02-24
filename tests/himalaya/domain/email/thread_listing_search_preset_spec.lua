describe('thread_listing.apply_search_preset', function()
  local thread_listing
  local list_called

  before_each(function()
    package.loaded['himalaya.domain.email.thread_listing'] = nil
    package.loaded['himalaya.config'] = nil

    list_called = false

    -- Stub dependencies that thread_listing requires at load time
    package.loaded['himalaya.request'] = {
      json = function()
        return { kill = function() end }
      end,
      plain = function()
        return { kill = function() end }
      end,
    }
    package.loaded['himalaya.domain.email.probe'] = {
      cancel_sync = function() end,
    }
    package.loaded['himalaya.job'] = {
      kill_and_wait = function() end,
    }

    require('himalaya.config')._reset()
    thread_listing = require('himalaya.domain.email.thread_listing')

    -- Spy on list() to verify it gets called without triggering real CLI work
    thread_listing.list = function()
      list_called = true
    end
  end)

  after_each(function()
    vim.wo.winbar = ''
  end)

  it('notifies when no presets configured', function()
    local notified_msg, notified_level
    local orig = vim.notify
    vim.notify = function(msg, level)
      notified_msg = msg
      notified_level = level
    end
    thread_listing.apply_search_preset()
    vim.notify = orig
    assert.are.equal('No search presets configured', notified_msg)
    assert.are.equal(vim.log.levels.INFO, notified_level)
  end)

  it('does not open vim.ui.select when no presets', function()
    local select_called = false
    local orig = vim.ui.select
    vim.ui.select = function()
      select_called = true
    end
    local orig_notify = vim.notify
    vim.notify = function() end
    thread_listing.apply_search_preset()
    vim.notify = orig_notify
    vim.ui.select = orig
    assert.is_false(select_called)
  end)

  it('opens vim.ui.select with configured presets', function()
    local cfg = require('himalaya.config')
    cfg.setup({
      search_presets = {
        { name = 'unread', query = 'flag unseen' },
        { name = 'flagged', query = 'flag flagged' },
      },
    })
    local select_items, select_opts
    local orig = vim.ui.select
    vim.ui.select = function(items, opts, cb)
      select_items = items
      select_opts = opts
      cb(nil)
    end
    thread_listing.apply_search_preset()
    vim.ui.select = orig
    assert.are.equal(2, #select_items)
    assert.are.equal('unread', select_items[1].name)
    assert.are.equal('flag unseen', select_items[1].query)
    assert.are.equal('Search preset:', select_opts.prompt)
  end)

  it('format_item shows name and query', function()
    local cfg = require('himalaya.config')
    cfg.setup({
      search_presets = {
        { name = 'unread', query = 'flag unseen' },
      },
    })
    local format_fn
    local orig = vim.ui.select
    vim.ui.select = function(_, opts, cb)
      format_fn = opts.format_item
      cb(nil)
    end
    thread_listing.apply_search_preset()
    vim.ui.select = orig
    local formatted = format_fn({ name = 'unread', query = 'flag unseen' })
    assert.truthy(formatted:find('unread'))
    assert.truthy(formatted:find('flag unseen'))
  end)

  it('applies selected preset and calls list()', function()
    local cfg = require('himalaya.config')
    cfg.setup({
      search_presets = {
        { name = 'unread', query = 'flag unseen' },
      },
    })
    local orig = vim.ui.select
    vim.ui.select = function(items, _, cb)
      cb(items[1])
    end
    thread_listing.apply_search_preset()
    vim.ui.select = orig
    assert.is_true(list_called)
  end)

  it('does nothing when selection is cancelled', function()
    local cfg = require('himalaya.config')
    cfg.setup({
      search_presets = {
        { name = 'unread', query = 'flag unseen' },
      },
    })
    local orig = vim.ui.select
    vim.ui.select = function(_, _, cb)
      cb(nil)
    end
    thread_listing.apply_search_preset()
    vim.ui.select = orig
    assert.is_false(list_called)
  end)
end)
