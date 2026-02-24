describe('himalaya.perf', function()
  local perf
  local orig_reltime, orig_reltimefloat, orig_notify

  before_each(function()
    package.loaded['himalaya.perf'] = nil

    orig_reltime = vim.fn.reltime
    orig_reltimefloat = vim.fn.reltimefloat
    orig_notify = vim.notify

    vim.fn.reltime = function()
      return { 0, 0 }
    end
    vim.fn.reltimefloat = function()
      return 0.042
    end

    -- vim.log.levels is already defined in nlua; no need to override

    perf = require('himalaya.perf')
  end)

  after_each(function()
    vim.fn.reltime = orig_reltime
    vim.fn.reltimefloat = orig_reltimefloat
    vim.notify = orig_notify
    -- vim.log.levels is not modified, no restore needed
  end)

  describe('is_enabled', function()
    it('returns false by default', function()
      assert.is_false(perf.is_enabled())
    end)

    it('returns true after enable()', function()
      perf.enable()
      assert.is_true(perf.is_enabled())
    end)

    it('returns false after disable()', function()
      perf.enable()
      perf.disable()
      assert.is_false(perf.is_enabled())
    end)
  end)

  describe('when disabled', function()
    it('start() does not create a timer entry', function()
      perf.start('render')
      local snap = perf.snapshot()
      assert.are.same({}, snap.timers)
    end)

    it('stop() does not error', function()
      perf.stop('render')
      local snap = perf.snapshot()
      assert.are.same({}, snap.timers)
    end)

    it('count() does not create a counter entry', function()
      perf.count('draw')
      local snap = perf.snapshot()
      assert.are.same({}, snap.counters)
    end)
  end)

  describe('timers', function()
    it('start()/stop() records elapsed time in snapshot', function()
      perf.enable()
      perf.start('render')
      perf.stop('render')

      local snap = perf.snapshot()
      assert.are.equal(42, snap.timers.render)
    end)

    it('stop() accumulates on repeated calls', function()
      perf.enable()
      perf.start('render')
      perf.stop('render')
      perf.stop('render')

      local snap = perf.snapshot()
      assert.are.equal(84, snap.timers.render)
    end)

    it('stop() on unknown timer is a no-op', function()
      perf.enable()
      perf.stop('nonexistent')

      local snap = perf.snapshot()
      assert.are.same({}, snap.timers)
    end)
  end)

  describe('counters', function()
    it('count() increments snapshot().counters', function()
      perf.enable()
      perf.count('draw')
      perf.count('draw')
      perf.count('draw')

      local snap = perf.snapshot()
      assert.are.equal(3, snap.counters.draw)
    end)
  end)

  describe('reset', function()
    it('clears all timers and counters', function()
      perf.enable()
      perf.start('render')
      perf.stop('render')
      perf.count('draw')

      perf.reset()
      local snap = perf.snapshot()
      assert.are.same({}, snap.timers)
      assert.are.same({}, snap.counters)
    end)
  end)

  describe('snapshot', function()
    it('returns empty tables when nothing recorded', function()
      local snap = perf.snapshot()
      assert.are.same({ timers = {}, counters = {} }, snap)
    end)
  end)

  describe('report', function()
    it('is a no-op when notify is false', function()
      local notify_called = false
      vim.notify = function()
        notify_called = true
      end

      perf.enable()
      perf.start('render')
      perf.stop('render')
      perf.report()

      assert.is_false(notify_called)
    end)

    it('calls vim.notify with formatted output when notify is true', function()
      local notify_msg = nil
      local notify_level = nil
      vim.notify = function(msg, level)
        notify_msg = msg
        notify_level = level
      end

      perf.enable({ notify = true })
      perf.start('render')
      perf.stop('render')
      perf.count('draw')
      perf.report()

      assert.is_not_nil(notify_msg)
      assert.is_truthy(notify_msg:find('himalaya perf:'))
      assert.is_truthy(notify_msg:find('render'))
      assert.is_truthy(notify_msg:find('draw'))
      assert.are.equal(vim.log.levels.INFO, notify_level)
    end)
  end)

  describe('write', function()
    it('encodes results as JSON and writes to file', function()
      local orig_io_open = io.open
      local written_data = nil
      local opened_path = nil
      local closed = false

      io.open = function(path, _mode) -- luacheck: ignore 122
        opened_path = path
        return {
          write = function(_, data)
            written_data = data
          end,
          close = function()
            closed = true
          end,
        }
      end

      local results = { { label = 'test', timers = {}, counters = {} } }
      perf.write('/tmp/perf.json', results)

      io.open = orig_io_open -- luacheck: ignore 122

      assert.are.equal('/tmp/perf.json', opened_path)
      assert.is_truthy(written_data)
      assert.is_truthy(written_data:find('test'))
      assert.is_true(closed)
    end)
  end)
end)
