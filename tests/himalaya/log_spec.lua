describe('himalaya.log', function()
  local log = require('himalaya.log')

  it('exposes info, warn, and err functions', function()
    assert.is_function(log.info)
    assert.is_function(log.warn)
    assert.is_function(log.err)
  end)

  it('calls vim.notify with correct level for info', function()
    local called_with = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      called_with = { msg = msg, level = level }
    end
    log.info('test message')
    vim.notify = orig
    assert.are.equal('test message', called_with.msg)
    assert.are.equal(vim.log.levels.INFO, called_with.level)
  end)

  it('calls vim.notify with correct level for warn', function()
    local called_with = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      called_with = { msg = msg, level = level }
    end
    log.warn('warning')
    vim.notify = orig
    assert.are.equal('warning', called_with.msg)
    assert.are.equal(vim.log.levels.WARN, called_with.level)
  end)

  it('calls vim.notify with correct level for err', function()
    local called_with = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      called_with = { msg = msg, level = level }
    end
    log.err('error')
    vim.notify = orig
    assert.are.equal('error', called_with.msg)
    assert.are.equal(vim.log.levels.ERROR, called_with.level)
  end)

  describe('debug', function()
    it('does nothing when himalaya_debug is not set', function()
      vim.g.himalaya_debug = nil
      local echoed = false
      local orig = vim.api.nvim_echo
      vim.api.nvim_echo = function()
        echoed = true
      end
      log.debug('test %s', 'msg')
      vim.api.nvim_echo = orig
      assert.is_false(echoed)
    end)

    it('echoes formatted message when himalaya_debug is set', function()
      vim.g.himalaya_debug = true
      local echo_args
      local orig = vim.api.nvim_echo
      vim.api.nvim_echo = function(chunks, history, opts)
        echo_args = { chunks = chunks, history = history, opts = opts }
      end
      log.debug('hello %s %d', 'world', 42)
      vim.api.nvim_echo = orig
      vim.g.himalaya_debug = nil
      assert.is_not_nil(echo_args)
      assert.are.equal('hello world 42', echo_args.chunks[1][1])
      assert.are.equal('Comment', echo_args.chunks[1][2])
      assert.is_true(echo_args.history)
    end)

    it('echoes plain message when no varargs given', function()
      vim.g.himalaya_debug = true
      local echo_args
      local orig = vim.api.nvim_echo
      vim.api.nvim_echo = function(chunks, history, opts)
        echo_args = { chunks = chunks, history = history, opts = opts }
      end
      log.debug('plain message')
      vim.api.nvim_echo = orig
      vim.g.himalaya_debug = nil
      assert.is_not_nil(echo_args)
      assert.are.equal('plain message', echo_args.chunks[1][1])
    end)
  end)
end)
