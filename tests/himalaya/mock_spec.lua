describe('himalaya.mock', function()
  local mock

  before_each(function()
    package.loaded['himalaya.mock'] = nil
    package.loaded['himalaya.mock.data'] = nil
    package.loaded['himalaya.config'] = nil

    package.loaded['himalaya.config'] = {
      get = function()
        return { mock = true }
      end,
    }

    mock = require('himalaya.mock')
  end)

  describe('enabled', function()
    it('returns true when mock config is set', function()
      assert.is_true(mock.enabled())
    end)

    it('returns false when mock config is not set', function()
      package.loaded['himalaya.config'] = {
        get = function()
          return { mock = false }
        end,
      }
      package.loaded['himalaya.mock'] = nil
      mock = require('himalaya.mock')
      assert.is_false(mock.enabled())
    end)
  end)

  describe('json', function()
    it('routes folder list command', function()
      local received
      mock.json({
        cmd = 'folder list %s',
        args = { '' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_true(#received >= 4)
      assert.are.equal('INBOX', received[1].name)
    end)

    it('routes envelope list command with pagination', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 5, 1, '' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.are.equal(5, #received)
    end)

    it('routes envelope list page 2', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 10, 2, '' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.are.equal(10, #received)
    end)

    it('filters envelopes by subject query', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 50, 1, 'subject alpha' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      -- Only "Project Alpha release timeline" threads match
      assert.are.equal(5, #received)
      for _, env in ipairs(received) do
        assert.is_truthy(env.subject:lower():find('alpha'))
      end
    end)

    it('filters envelopes by from query', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 50, 1, 'from bob' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_true(#received > 0)
      for _, env in ipairs(received) do
        assert.is_truthy(env.from.name:lower():find('bob'))
      end
    end)

    it('filters envelopes by compound query', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 50, 1, '(subject alpha or body alpha) and from bob' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      -- Only Bob's messages about Alpha match
      assert.is_true(#received > 0)
      for _, env in ipairs(received) do
        assert.is_truthy(env.subject:lower():find('alpha'))
        assert.is_truthy(env.from.name:lower():find('bob'))
      end
    end)

    it('filters envelopes by flag query', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 50, 1, 'flag flagged' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_true(#received > 0)
      for _, env in ipairs(received) do
        local has_flagged = false
        for _, f in ipairs(env.flags) do
          if f == 'Flagged' then
            has_flagged = true
          end
        end
        assert.is_true(has_flagged)
      end
    end)

    it('filters envelopes with not flag query', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 50, 1, 'not flag seen' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_true(#received > 0)
      for _, env in ipairs(received) do
        local has_seen = false
        for _, f in ipairs(env.flags) do
          if f == 'Seen' then
            has_seen = true
          end
        end
        assert.is_false(has_seen)
      end
    end)

    it('ignores order by suffix in query', function()
      local received
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 50, 1, 'order by date desc' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      -- Should return all envelopes (order by is not a filter)
      assert.are.equal(26, #received)
    end)

    it('reverses envelope order for order by asc', function()
      local desc_result, asc_result
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 5, 1, 'order by date desc' },
        on_data = function(d)
          desc_result = d
        end,
      })
      mock.json({
        cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
        args = { 'INBOX', '', 5, 1, 'order by date asc' },
        on_data = function(d)
          asc_result = d
        end,
      })
      vim.wait(100, function()
        return desc_result ~= nil and asc_result ~= nil
      end)
      -- First element of desc should be last element of asc
      assert.are.equal(desc_result[1].id, asc_result[#asc_result].id)
      assert.are.equal(desc_result[#desc_result].id, asc_result[1].id)
    end)

    it('routes envelope thread command', function()
      local received
      mock.json({
        cmd = 'envelope thread --folder %s %s %s',
        args = { 'INBOX', '', '' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      -- 5 threads + 12 standalone edges + thread internal edges
      assert.is_true(#received > 16)
    end)

    it('returns empty table for unknown commands', function()
      local received
      mock.json({
        cmd = 'unknown command',
        args = {},
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.are.same({}, received)
    end)

    it('respects is_stale callback', function()
      local received
      mock.json({
        cmd = 'folder list %s',
        args = { '' },
        is_stale = function()
          return true
        end,
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_nil(received)
    end)

    it('returns noop handle with kill method', function()
      local handle = mock.json({
        cmd = 'folder list %s',
        args = { '' },
        on_data = function() end,
      })
      assert.is_not_nil(handle)
      assert.is_function(handle.kill)
      assert.is_function(handle.wait)
      -- should not error
      handle:kill()
      handle:wait()
    end)
  end)

  describe('plain', function()
    it('routes message read command', function()
      local received
      mock.plain({
        cmd = 'message read %s --folder %s %s',
        args = { '', 'INBOX', '1001' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_truthy(received:find('Project Alpha release timeline'))
    end)

    it('routes template write command', function()
      local received
      mock.plain({
        cmd = 'template write %s',
        args = { '' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_truthy(received:find('From:'))
      assert.is_truthy(received:find('Subject:'))
    end)

    it('routes template reply command', function()
      local received
      mock.plain({
        cmd = 'template reply %s --folder %s %s',
        args = { '', 'INBOX', '1006' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_truthy(received:find('Re:'))
      assert.is_truthy(received:find('eve@example.com'))
    end)

    it('routes template forward command', function()
      local received
      mock.plain({
        cmd = 'template forward %s --folder %s %s',
        args = { '', 'INBOX', '1001' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_truthy(received:find('Fwd:'))
    end)

    it('routes template send command', function()
      local received
      mock.plain({
        cmd = 'template send %s',
        args = { '' },
        stdin = 'From: user@example.com\nTo: test@test.com\n\nbody\n',
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.are.equal('', received)
    end)

    it('routes flag add command', function()
      local received
      mock.plain({
        cmd = 'flag add %s --folder %s %s %s',
        args = { '', 'INBOX', 'Seen', '1001' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.are.equal('', received)
    end)

    it('routes message delete command', function()
      local received
      mock.plain({
        cmd = 'message delete %s --folder %s %s',
        args = { '', 'INBOX', '1001' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.are.equal('', received)
    end)

    it('routes attachment download command', function()
      local received
      mock.plain({
        cmd = 'attachment download %s --folder %s %s',
        args = { '', 'INBOX', '1001' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.are.equal('', received)
    end)

    it('returns generic body for unscripted message IDs', function()
      local received
      mock.plain({
        cmd = 'message read %s --folder %s %s',
        args = { '', 'INBOX', '1025' },
        on_data = function(d)
          received = d
        end,
      })
      vim.wait(100, function()
        return received ~= nil
      end)
      assert.is_not_nil(received)
      assert.is_truthy(received:find('Vacation request approved'))
    end)
  end)
end)

describe('himalaya.mock.data', function()
  local data

  before_each(function()
    package.loaded['himalaya.mock.data'] = nil
    data = require('himalaya.mock.data')
  end)

  describe('accounts', function()
    it('returns two accounts', function()
      local accounts = data.accounts()
      assert.are.equal(2, #accounts)
    end)

    it('has one default account', function()
      local accounts = data.accounts()
      local defaults = 0
      for _, a in ipairs(accounts) do
        if a.default then
          defaults = defaults + 1
        end
      end
      assert.are.equal(1, defaults)
    end)
  end)

  describe('folders', function()
    it('returns six folders', function()
      local folders = data.folders()
      assert.are.equal(6, #folders)
    end)

    it('includes INBOX', function()
      local folders = data.folders()
      local found = false
      for _, f in ipairs(folders) do
        if f.name == 'INBOX' then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe('envelopes', function()
    it('returns paginated results', function()
      local page1 = data.envelopes('INBOX', 10, 1)
      assert.are.equal(10, #page1)

      local page2 = data.envelopes('INBOX', 10, 2)
      assert.are.equal(10, #page2)

      local page3 = data.envelopes('INBOX', 10, 3)
      assert.are.equal(6, #page3)
    end)

    it('returns envelopes with required fields', function()
      local envs = data.envelopes('INBOX', 5, 1)
      for _, env in ipairs(envs) do
        assert.is_not_nil(env.id)
        assert.is_not_nil(env.subject)
        assert.is_not_nil(env.from)
        assert.is_not_nil(env.from.name)
        assert.is_not_nil(env.date)
        assert.is_not_nil(env.flags)
      end
    end)

    it('returns empty table for empty folders', function()
      local envs = data.envelopes('Spam', 10, 1)
      assert.are.same({}, envs)
    end)

    it('returns sent folder data', function()
      local envs = data.envelopes('Sent', 10, 1)
      assert.is_true(#envs > 0)
    end)
  end)

  describe('thread_edges', function()
    it('returns edges for INBOX', function()
      local edges = data.thread_edges('INBOX')
      assert.is_true(#edges > 0)
    end)

    it('each edge has parent, child, depth', function()
      local edges = data.thread_edges('INBOX')
      for _, edge in ipairs(edges) do
        assert.is_not_nil(edge[1]) -- parent
        assert.is_not_nil(edge[2]) -- child
        assert.is_not_nil(edge[3]) -- depth
        assert.is_not_nil(edge[1].id)
        assert.is_not_nil(edge[2].id)
      end
    end)

    it('returns empty for non-INBOX folders', function()
      local edges = data.thread_edges('Sent')
      assert.are.same({}, edges)
    end)

    it('has ghost parent edges for root messages', function()
      local edges = data.thread_edges('INBOX')
      local ghost_count = 0
      for _, edge in ipairs(edges) do
        if edge[1].id == 0 then
          ghost_count = ghost_count + 1
        end
      end
      -- 4 thread roots + 13 standalone = 17 ghost edges
      assert.are.equal(17, ghost_count)
    end)
  end)

  describe('message_body', function()
    it('returns body for known IDs', function()
      local body = data.message_body(1001)
      assert.is_truthy(body:find('Project Alpha'))
    end)

    it('returns generic body for unscripted IDs', function()
      local body = data.message_body(1025)
      assert.is_truthy(body:find('Vacation request approved'))
    end)

    it('returns fallback for unknown IDs', function()
      local body = data.message_body(9999)
      assert.is_truthy(body:find('Message not found'))
    end)
  end)

  describe('templates', function()
    it('write_template has From/To/Subject headers', function()
      local t = data.write_template()
      assert.is_truthy(t:find('From:'))
      assert.is_truthy(t:find('To:'))
      assert.is_truthy(t:find('Subject:'))
    end)

    it('reply_template includes Re: prefix', function()
      local t = data.reply_template(1001)
      assert.is_truthy(t:find('Re:'))
    end)

    it('forward_template includes Fwd: prefix', function()
      local t = data.forward_template(1001)
      assert.is_truthy(t:find('Fwd:'))
    end)

    it('reply_template falls back to write_template for unknown IDs', function()
      local t = data.reply_template(9999)
      assert.are.equal(data.write_template(), t)
    end)
  end)
end)
