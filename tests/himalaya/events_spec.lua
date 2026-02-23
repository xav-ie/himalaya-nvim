describe('himalaya.events', function()
  local events

  before_each(function()
    package.loaded['himalaya.events'] = nil
    events = require('himalaya.events')
    events._reset()
  end)

  describe('on/emit', function()
    it('calls a single listener', function()
      local received
      events.on('TestEvent', function(data)
        received = data
      end)
      events.emit('TestEvent', { value = 42 })
      assert.are.same({ value = 42 }, received)
    end)

    it('calls multiple listeners in order', function()
      local calls = {}
      events.on('TestEvent', function()
        table.insert(calls, 'first')
      end)
      events.on('TestEvent', function()
        table.insert(calls, 'second')
      end)
      events.emit('TestEvent')
      assert.are.same({ 'first', 'second' }, calls)
    end)

    it('passes nil data without error', function()
      local called = false
      events.on('TestEvent', function(data)
        called = true
        assert.is_nil(data)
      end)
      events.emit('TestEvent')
      assert.is_true(called)
    end)

    it('returns unique ids', function()
      local id1 = events.on('A', function() end)
      local id2 = events.on('B', function() end)
      local id3 = events.on('A', function() end)
      assert.are_not.equal(id1, id2)
      assert.are_not.equal(id2, id3)
      assert.are_not.equal(id1, id3)
    end)
  end)

  describe('zero overhead', function()
    it('emit with no listeners is a no-op', function()
      -- Should not error
      events.emit('NoListeners', { foo = 'bar' })
    end)
  end)

  describe('off', function()
    it('removes a listener by id', function()
      local called = false
      local id = events.on('TestEvent', function()
        called = true
      end)
      events.off(id)
      events.emit('TestEvent')
      assert.is_false(called)
    end)

    it('unknown id is a no-op', function()
      events.off(999)
    end)

    it('removes only the targeted listener', function()
      local calls = {}
      local id1 = events.on('TestEvent', function()
        table.insert(calls, 'first')
      end)
      events.on('TestEvent', function()
        table.insert(calls, 'second')
      end)
      events.off(id1)
      events.emit('TestEvent')
      assert.are.same({ 'second' }, calls)
    end)
  end)

  describe('once', function()
    it('fires once then auto-removes', function()
      local count = 0
      events.once('TestEvent', function()
        count = count + 1
      end)
      events.emit('TestEvent')
      events.emit('TestEvent')
      assert.are.equal(1, count)
    end)

    it('can be removed before firing', function()
      local called = false
      local id = events.once('TestEvent', function()
        called = true
      end)
      events.off(id)
      events.emit('TestEvent')
      assert.is_false(called)
    end)
  end)

  describe('error isolation', function()
    it('bad listener does not crash others', function()
      local calls = {}
      events.on('TestEvent', function()
        table.insert(calls, 'before')
      end)
      events.on('TestEvent', function()
        error('boom')
      end)
      events.on('TestEvent', function()
        table.insert(calls, 'after')
      end)
      -- Suppress vim.notify so the expected warning doesn't leak to stderr
      local orig_notify = vim.notify
      vim.notify = function() end
      events.emit('TestEvent')
      vim.notify = orig_notify
      assert.are.same({ 'before', 'after' }, calls)
    end)

    it('logs warning on listener error', function()
      local warned
      local orig_warn = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN then
          warned = msg
        end
      end
      events.on('TestEvent', function()
        error('kaboom')
      end)
      events.emit('TestEvent')
      vim.notify = orig_warn
      assert.is_not_nil(warned)
      assert.truthy(warned:find('kaboom'))
      assert.truthy(warned:find('TestEvent'))
    end)
  end)

  describe('count', function()
    it('returns 0 for unknown events', function()
      assert.are.equal(0, events.count('NoSuchEvent'))
    end)

    it('tracks registrations', function()
      events.on('TestEvent', function() end)
      events.on('TestEvent', function() end)
      assert.are.equal(2, events.count('TestEvent'))
    end)

    it('decrements after off', function()
      local id = events.on('TestEvent', function() end)
      events.on('TestEvent', function() end)
      events.off(id)
      assert.are.equal(1, events.count('TestEvent'))
    end)

    it('decrements after once fires', function()
      events.once('TestEvent', function() end)
      events.on('TestEvent', function() end)
      assert.are.equal(2, events.count('TestEvent'))
      events.emit('TestEvent')
      assert.are.equal(1, events.count('TestEvent'))
    end)
  end)

  describe('_reset', function()
    it('clears everything', function()
      events.on('A', function() end)
      events.on('B', function() end)
      events._reset()
      assert.are.equal(0, events.count('A'))
      assert.are.equal(0, events.count('B'))
    end)

    it('resets id counter', function()
      events.on('A', function() end)
      events._reset()
      local id = events.on('A', function() end)
      assert.are.equal(1, id)
    end)
  end)
end)
