describe('himalaya.request', function()
  local request
  local config

  before_each(function()
    package.loaded['himalaya.request'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['himalaya.job'] = nil
    config = require('himalaya.config')
    config._reset()
    request = require('himalaya.request')
  end)

  describe('json on_exit paths', function()
    local captured_on_exit

    before_each(function()
      captured_on_exit = nil
      package.loaded['himalaya.job'] = {
        run = function(_cmd, opts)
          captured_on_exit = opts.on_exit
          return {}
        end,
      }
      package.loaded['himalaya.request'] = nil
      request = require('himalaya.request')
    end)

    it('calls on_data with parsed JSON on success', function()
      local result
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        on_data = function(data)
          result = data
        end,
      })
      captured_on_exit('[{"id":1}]', '', 0)
      assert.are.same({ { id = 1 } }, result)
    end)

    it('returns empty table for blank stdout', function()
      local result
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        on_data = function(data)
          result = data
        end,
      })
      captured_on_exit('', '', 0)
      assert.are.same({}, result)
    end)

    it('calls on_error for non-zero exit code', function()
      local errored = false
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        silent = true,
        on_data = function() end,
        on_error = function()
          errored = true
        end,
      })
      captured_on_exit('', 'fail', 1)
      assert.is_true(errored)
    end)

    it('calls on_error for invalid JSON', function()
      local errored = false
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        silent = true,
        on_data = function() end,
        on_error = function()
          errored = true
        end,
      })
      captured_on_exit('not json{{{', '', 0)
      assert.is_true(errored)
    end)

    it('calls on_error when exit 0 but stderr contains Error:', function()
      local errored = false
      local data_called = false
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        silent = true,
        on_data = function()
          data_called = true
        end,
        on_error = function()
          errored = true
        end,
      })
      captured_on_exit('', '\27[31mError:\27[0m cannot parse search query', 0)
      assert.is_true(errored)
      assert.is_false(data_called)
    end)

    it('passes through when exit 0 with non-error stderr', function()
      local result
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        on_data = function(data)
          result = data
        end,
      })
      captured_on_exit('[{"id":1}]', 'some warning', 0)
      assert.are.same({ { id = 1 } }, result)
    end)

    it('bails out when is_stale returns true', function()
      local called = false
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        is_stale = function()
          return true
        end,
        on_data = function()
          called = true
        end,
      })
      captured_on_exit('[{"id":1}]', '', 0)
      assert.is_false(called)
    end)
  end)

  describe('build_cmd', function()
    it('builds a basic command with json output', function()
      local cmd = request._build_cmd('envelope list --folder %s', { 'INBOX' }, 'json')
      assert.are.equal(cmd[1], 'himalaya')
      assert.is_truthy(vim.tbl_contains(cmd, '--output'))
      assert.is_truthy(vim.tbl_contains(cmd, 'json'))
      local joined = table.concat(cmd, ' ')
      assert.is_truthy(joined:match('envelope'))
      assert.is_truthy(joined:match('INBOX'))
    end)

    it('prepends --config when config_path is set', function()
      config.setup({ config_path = '/tmp/himalaya.toml' })
      local cmd = request._build_cmd('folder list', {}, 'json')
      local joined = table.concat(cmd, ' ')
      assert.is_truthy(joined:match('--config'))
      assert.is_truthy(joined:match('/tmp/himalaya.toml'))
    end)

    it('uses custom executable', function()
      config.setup({ executable = '/usr/local/bin/himalaya' })
      local cmd = request._build_cmd('folder list', {}, 'json')
      assert.are.equal('/usr/local/bin/himalaya', cmd[1])
    end)
  end)

  describe('plain', function()
    local captured_on_exit

    before_each(function()
      captured_on_exit = nil
      package.loaded['himalaya.job'] = {
        run = function(_cmd, opts)
          captured_on_exit = opts.on_exit
          return {}
        end,
      }
      package.loaded['himalaya.request'] = nil
      request = require('himalaya.request')
    end)

    it('calls on_data with raw stdout on success', function()
      local result
      request.plain({
        cmd = 'folder list',
        msg = 'test',
        on_data = function(data)
          result = data
        end,
      })
      captured_on_exit('INBOX\nSent\nDrafts', '', 0)
      assert.are.equal('INBOX\nSent\nDrafts', result)
    end)

    it('calls on_error on non-zero exit code', function()
      local errored = false
      request.plain({
        cmd = 'folder list',
        msg = 'test',
        silent = true,
        on_data = function() end,
        on_error = function()
          errored = true
        end,
      })
      captured_on_exit('', 'boom', 1)
      assert.is_true(errored)
    end)

    it('passes stdin through to job.run', function()
      local captured_stdin
      package.loaded['himalaya.job'] = {
        run = function(_cmd, opts)
          captured_stdin = opts.stdin
          captured_on_exit = opts.on_exit
          return {}
        end,
      }
      package.loaded['himalaya.request'] = nil
      request = require('himalaya.request')
      request.plain({
        cmd = 'message send',
        msg = 'test',
        stdin = 'email body',
        on_data = function() end,
      })
      assert.are.equal('email body', captured_stdin)
    end)
  end)

  describe('on_exit non-silent error paths', function()
    local captured_on_exit
    local notify_calls

    before_each(function()
      captured_on_exit = nil
      notify_calls = {}
      package.loaded['himalaya.job'] = {
        run = function(_cmd, opts)
          captured_on_exit = opts.on_exit
          return {}
        end,
      }
      package.loaded['himalaya.request'] = nil
      -- suppress vim.notify to capture log.err calls
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end
      request = require('himalaya.request')
      vim.notify = orig_notify
    end)

    it('logs error message with stderr for non-zero exit (non-silent)', function()
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end
      request.json({
        cmd = 'envelope list',
        msg = 'Listing envelopes',
        on_data = function() end,
      })
      captured_on_exit('', 'connection refused\nbacktrace here', 1)
      vim.notify = orig_notify
      assert.is_true(#notify_calls > 0)
      local err_msg = notify_calls[#notify_calls].msg
      assert.is_truthy(err_msg:find('FAIL'))
      assert.is_truthy(err_msg:find('connection refused'))
    end)

    it('logs error message without stderr for non-zero exit (non-silent)', function()
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end
      request.json({
        cmd = 'envelope list',
        msg = 'Listing envelopes',
        on_data = function() end,
      })
      captured_on_exit('', '', 2)
      vim.notify = orig_notify
      assert.is_true(#notify_calls > 0)
      local err_msg = notify_calls[#notify_calls].msg
      assert.is_truthy(err_msg:find('FAIL'))
      assert.is_truthy(err_msg:find('exit code 2'))
    end)

    it('logs stderr error for exit 0 with Error: prefix (non-silent)', function()
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end
      request.json({
        cmd = 'envelope list',
        msg = 'Fetching envelopes',
        on_data = function() end,
      })
      captured_on_exit('', '\27[31mError:\27[0m cannot parse search query `bad`', 0)
      vim.notify = orig_notify
      assert.is_true(#notify_calls > 0)
      local err_msg = notify_calls[#notify_calls].msg
      assert.is_truthy(err_msg:find('cannot parse'))
      assert.is_truthy(err_msg:find('Fetching envelopes'))
    end)

    it('logs JSON parse error for invalid JSON (non-silent)', function()
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        on_data = function() end,
      })
      captured_on_exit('not json{{{', '', 0)
      vim.notify = orig_notify
      assert.is_true(#notify_calls > 0)
      local err_msg = notify_calls[#notify_calls].msg
      assert.is_truthy(err_msg:find('Failed to parse JSON'))
    end)
  end)
end)
