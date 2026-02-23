describe('email.apply_search_preset', function()
  local email
  local captured_json

  local tracked_bufs = {}
  local function track(buf)
    tracked_bufs[#tracked_bufs + 1] = buf
    return buf
  end

  local function make_listing_buf(ids)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.b[buf].himalaya_buffer_type = 'listing'
    vim.b[buf].himalaya_account = 'test'
    vim.b[buf].himalaya_folder = 'INBOX'
    vim.b[buf].himalaya_page = 1
    vim.b[buf].himalaya_query = ''
    vim.bo[buf].buftype = 'nofile'
    local lines = {}
    for _, id in ipairs(ids) do
      lines[#lines + 1] =
        string.format(' %d    │ *   │ Subject              │ Sender               │ 2024-01-01 00:00:00', id)
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    return buf
  end

  before_each(function()
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.config'] = nil

    captured_json = nil

    package.loaded['himalaya.request'] = {
      json = function(opts)
        captured_json = opts
        return { kill = function() end }
      end,
      plain = function()
        return { kill = function() end }
      end,
    }
    package.loaded['himalaya.domain.email.probe'] = {
      reset_if_changed = function() end,
      set_total_from_data = function() end,
      total_pages_str = function()
        return '?'
      end,
      start = function() end,
      cancel = function(cb)
        if cb then
          cb()
        end
      end,
      cancel_sync = function() end,
      restart = function() end,
    }
    package.loaded['himalaya.job'] = {
      kill_and_wait = function() end,
    }
    package.loaded['himalaya.domain.email.thread_listing'] = {
      cancel_jobs = function() end,
      list = function() end,
      mark_seen_optimistic = function() end,
      is_busy = function()
        return false
      end,
    }
    package.loaded['himalaya.state.context'] = {
      resolve = function()
        return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
      end,
    }

    require('himalaya.config')._reset()
    email = require('himalaya.domain.email')
  end)

  after_each(function()
    for _, b in ipairs(tracked_bufs) do
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end
    tracked_bufs = {}
    vim.wo.winbar = ''
  end)

  it('notifies when no presets configured', function()
    local notified_msg, notified_level
    local orig = vim.notify
    vim.notify = function(msg, level)
      notified_msg = msg
      notified_level = level
    end
    email.apply_search_preset()
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
    email.apply_search_preset()
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
    email.apply_search_preset()
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
    email.apply_search_preset()
    vim.ui.select = orig
    local formatted = format_fn({ name = 'unread', query = 'flag unseen' })
    assert.truthy(formatted:find('unread'))
    assert.truthy(formatted:find('flag unseen'))
  end)

  it('applies selected preset query and resets page', function()
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
    local buf = track(make_listing_buf({ 1 }))
    vim.b[buf].himalaya_page = 5
    email.apply_search_preset()
    vim.ui.select = orig
    assert.are.equal('flag unseen', vim.b[buf].himalaya_query)
    assert.are.equal(1, vim.b[buf].himalaya_page)
    assert.is_not_nil(captured_json)
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
    local buf = track(make_listing_buf({ 1 }))
    vim.b[buf].himalaya_query = 'original'
    email.apply_search_preset()
    vim.ui.select = orig
    assert.are.equal('original', vim.b[buf].himalaya_query)
    assert.is_nil(captured_json)
  end)
end)
