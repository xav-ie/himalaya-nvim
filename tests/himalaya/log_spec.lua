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
end)
