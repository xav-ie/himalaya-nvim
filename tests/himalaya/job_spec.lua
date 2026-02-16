describe('himalaya.job', function()
  local job = require('himalaya.job')

  it('exposes a run function', function()
    assert.is_function(job.run)
  end)

  it('runs a command and collects stdout', function()
    local done = false
    local result = nil

    job.run({ 'echo', 'hello world' }, {
      on_exit = function(out, err, code)
        result = out
        done = true
      end,
    })

    vim.wait(5000, function() return done end)
    assert.is_true(done)
    assert.are.equal('hello world\n', result)
  end)

  it('collects stderr on failure', function()
    local done = false
    local err_result = nil
    local exit_code = nil

    job.run({ 'sh', '-c', 'echo bad >&2; exit 1' }, {
      on_exit = function(out, err, code)
        err_result = err
        exit_code = code
        done = true
      end,
    })

    vim.wait(5000, function() return done end)
    assert.is_true(done)
    assert.are.equal(1, exit_code)
    assert.is_truthy(err_result:match('bad'))
  end)

  it('can pipe stdin', function()
    local done = false
    local result = nil

    job.run({ 'cat' }, {
      stdin = 'piped content',
      on_exit = function(out, err, code)
        result = out
        done = true
      end,
    })

    vim.wait(5000, function() return done end)
    assert.is_true(done)
    assert.are.equal('piped content', result)
  end)
end)
