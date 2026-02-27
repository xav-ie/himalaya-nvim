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
    assert.are.equal('', account.default())
  end)

  describe('flag', function()
    it('returns empty table for empty account', function()
      assert.are.same({}, account.flag(''))
    end)

    it('returns --account flag table for non-empty account', function()
      assert.are.same({ '--account', 'work' }, account.flag('work'))
    end)

    it('preserves spaces in account name', function()
      assert.are.same({ '--account', 'My Work Email' }, account.flag('My Work Email'))
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
    it('sets default account from default entry on first load', function()
      account.list()
      local json = vim.json.encode({
        { name = 'personal' },
        { name = 'work', default = true },
      })
      job_run_calls[1].opts.on_exit(json, '', 0)
      assert.are.equal('work', account.default())
    end)

    it('returns empty string before warmup', function()
      assert.are.equal('', account.default())
    end)

    it('does not change default after subsequent refreshes', function()
      account.list()
      local json = vim.json.encode({
        { name = 'personal' },
        { name = 'work', default = true },
      })
      job_run_calls[1].opts.on_exit(json, '', 0)
      assert.are.equal('work', account.default())

      -- Expire the cache
      local real_now = vim.uv.now
      vim.uv.now = function()
        return real_now() + 121 * 1000
      end

      account.list()
      local json2 = vim.json.encode({
        { name = 'personal', default = true },
        { name = 'work' },
      })
      job_run_calls[2].opts.on_exit(json2, '', 0)
      -- default_account should not change once set
      assert.are.equal('work', account.default())

      vim.uv.now = real_now
    end)
  end)

  describe('mock mode', function()
    local mock_account

    before_each(function()
      package.loaded['himalaya.state.account'] = nil
      package.loaded['himalaya.job'] = nil
      package.loaded['himalaya.mock.data'] = nil

      package.loaded['himalaya.job'] = {
        run = function()
          error('job.run should not be called in mock mode')
        end,
      }

      package.loaded['himalaya.config'] = {
        get = function()
          return { executable = 'himalaya', mock = true }
        end,
      }

      package.loaded['himalaya.mock.data'] = {
        accounts = function()
          return {
            { name = 'personal', default = true },
            { name = 'work', default = false },
          }
        end,
      }

      mock_account = require('himalaya.state.account')
    end)

    it('populates cache from mock data without job.run', function()
      local result = mock_account.list()
      assert.are.same({ 'personal', 'work' }, result)
    end)

    it('sets default account from mock data', function()
      mock_account.warmup()
      assert.are.equal('personal', mock_account.default())
    end)

    it('calls async callback via schedule', function()
      local received
      mock_account.list_async(function(names)
        received = names
      end)
      -- callback is deferred via vim.schedule; flush it
      vim.wait(50, function()
        return received ~= nil
      end)
      assert.are.same({ 'personal', 'work' }, received)
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
