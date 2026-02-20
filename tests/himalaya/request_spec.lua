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
        on_data = function(data) result = data end,
      })
      captured_on_exit('[{"id":1}]', '', 0)
      assert.are.same({{id = 1}}, result)
    end)

    it('returns empty table for blank stdout', function()
      local result
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        on_data = function(data) result = data end,
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
        on_error = function() errored = true end,
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
        on_error = function() errored = true end,
      })
      captured_on_exit('not json{{{', '', 0)
      assert.is_true(errored)
    end)

    it('bails out when is_stale returns true', function()
      local called = false
      request.json({
        cmd = 'envelope list',
        msg = 'test',
        is_stale = function() return true end,
        on_data = function() called = true end,
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
end)
