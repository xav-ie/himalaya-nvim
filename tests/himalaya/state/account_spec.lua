describe('himalaya.state.account', function()
  local account
  local job_run_calls

  before_each(function()
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.job'] = nil

    job_run_calls = {}
    package.loaded['himalaya.job'] = {
      run = function(cmd, opts)
        job_run_calls[#job_run_calls + 1] = { cmd = cmd, opts = opts }
      end,
    }

    package.loaded['himalaya.config'] = {
      get = function()
        return { executable = 'himalaya' }
      end,
    }

    account = require('himalaya.state.account')
  end)

  it('defaults to empty string', function()
    assert.are.equal('', account.current())
  end)

  it('stores selected account', function()
    account.select('work')
    assert.are.equal('work', account.current())
  end)

  it('can switch accounts', function()
    account.select('work')
    account.select('personal')
    assert.are.equal('personal', account.current())
  end)

  describe('flag', function()
    it('returns empty string for empty account', function()
      assert.are.equal('', account.flag(''))
    end)

    it('returns --account flag for non-empty account', function()
      assert.are.equal('--account work', account.flag('work'))
    end)
  end)

  describe('list', function()
    it('returns empty table when cache is cold', function()
      assert.are.same({}, account.list())
    end)

    it('triggers background refresh when cache is cold', function()
      account.list()
      assert.are.equal(1, #job_run_calls)
    end)

    it('returns cached data when cache is warm', function()
      -- Trigger a refresh
      account.list()
      -- Simulate async completion
      local json = vim.json.encode({ { name = 'work' }, { name = 'personal' } })
      job_run_calls[1].opts.on_exit(json, '', 0)

      local result = account.list()
      assert.are.same({ 'personal', 'work' }, result)
    end)

    it('triggers background refresh when cache is stale', function()
      -- Warm the cache
      account.list()
      local json = vim.json.encode({ { name = 'A' } })
      job_run_calls[1].opts.on_exit(json, '', 0)

      -- Expire the cache by stubbing vim.uv.now
      local real_now = vim.uv.now
      vim.uv.now = function()
        return real_now() + 121 * 1000
      end

      account.list()
      assert.are.equal(2, #job_run_calls)

      vim.uv.now = real_now
    end)

    it('returns stale cached data while refresh is in flight', function()
      -- Warm the cache
      account.list()
      local json = vim.json.encode({ { name = 'A' } })
      job_run_calls[1].opts.on_exit(json, '', 0)

      -- Expire the cache
      local real_now = vim.uv.now
      vim.uv.now = function()
        return real_now() + 121 * 1000
      end

      local result = account.list()
      assert.are.same({ 'A' }, result)

      vim.uv.now = real_now
    end)
  end)

  describe('list_async', function()
    it('calls callback with cached data when fresh', function()
      -- Warm the cache
      account.list()
      local json = vim.json.encode({ { name = 'X' }, { name = 'Y' } })
      job_run_calls[1].opts.on_exit(json, '', 0)

      local received
      account.list_async(function(names)
        received = names
      end)
      assert.are.same({ 'X', 'Y' }, received)
      -- No new job spawned
      assert.are.equal(1, #job_run_calls)
    end)

    it('calls callback after async fetch when stale', function()
      local received
      account.list_async(function(names)
        received = names
      end)
      assert.is_nil(received)

      -- Simulate completion
      local json = vim.json.encode({ { name = 'Z' } })
      job_run_calls[1].opts.on_exit(json, '', 0)
      assert.are.same({ 'Z' }, received)
    end)
  end)

  describe('warmup', function()
    it('triggers a background refresh', function()
      account.warmup()
      assert.are.equal(1, #job_run_calls)
    end)

    it('does not trigger refresh if cache already exists', function()
      -- Warm the cache first
      account.warmup()
      local json = vim.json.encode({ { name = 'A' } })
      job_run_calls[1].opts.on_exit(json, '', 0)

      account.warmup()
      assert.are.equal(1, #job_run_calls)
    end)
  end)

  describe('deduplication', function()
    it('does not spawn multiple jobs for concurrent refreshes', function()
      account.list()
      account.list()
      account.list()
      assert.are.equal(1, #job_run_calls)
    end)
  end)

  describe('default account', function()
    it('sets current account from default entry on first load', function()
      account.list()
      local json = vim.json.encode({
        { name = 'personal' },
        { name = 'work', default = true },
      })
      job_run_calls[1].opts.on_exit(json, '', 0)
      assert.are.equal('work', account.current())
    end)

    it('does not override manually selected account', function()
      account.select('custom')
      account.list()
      local json = vim.json.encode({
        { name = 'personal' },
        { name = 'work', default = true },
      })
      job_run_calls[1].opts.on_exit(json, '', 0)
      assert.are.equal('custom', account.current())
    end)
  end)

  describe('error handling', function()
    it('preserves existing cache on failed refresh', function()
      -- Warm the cache
      account.list()
      local json = vim.json.encode({ { name = 'A' } })
      job_run_calls[1].opts.on_exit(json, '', 0)

      -- Expire the cache
      local real_now = vim.uv.now
      vim.uv.now = function()
        return real_now() + 121 * 1000
      end

      account.list()
      -- Simulate failure
      job_run_calls[2].opts.on_exit('', 'error', 1)

      vim.uv.now = real_now

      -- Cache should still have old data
      assert.are.same({ 'A' }, account.list())
    end)
  end)
end)
