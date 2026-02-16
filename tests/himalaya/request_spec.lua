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
