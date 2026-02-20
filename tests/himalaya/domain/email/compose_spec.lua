describe('himalaya.domain.email.compose', function()
  local compose
  local request_calls
  local orig_input, orig_tempname, orig_writefile, orig_delete
  local orig_buf_get_name

  before_each(function()
    request_calls = {}

    package.loaded['himalaya.domain.email.compose'] = nil
    package.loaded['himalaya.request'] = nil
    package.loaded['himalaya.log'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.folder'] = nil
    package.loaded['himalaya.domain.email'] = nil

    package.loaded['himalaya.request'] = {
      plain = function(opts) table.insert(request_calls, opts) end,
      json = function() end,
    }
    package.loaded['himalaya.log'] = {
      info = function() end,
      warn = function() end,
      err = function() end,
      debug = function() end,
    }
    package.loaded['himalaya.state.account'] = {
      current = function() return 'test-acct' end,
      flag = function(acct) return '--account ' .. acct end,
    }
    package.loaded['himalaya.state.folder'] = {
      current = function() return 'INBOX' end,
    }
    package.loaded['himalaya.domain.email'] = {
      _get_current_id = function() return '42' end,
      context_email_id = function() return '42' end,
    }

    compose = require('himalaya.domain.email.compose')

    orig_input = vim.fn.input
    orig_tempname = vim.fn.tempname
    orig_writefile = vim.fn.writefile
    orig_delete = vim.fn.delete
    orig_buf_get_name = vim.api.nvim_buf_get_name

    vim.fn.tempname = function() return '/tmp/test_draft' end
    vim.fn.writefile = function() return 0 end
    vim.fn.delete = function() return 0 end
  end)

  after_each(function()
    vim.fn.input = orig_input
    vim.fn.tempname = orig_tempname
    vim.fn.writefile = orig_writefile
    vim.fn.delete = orig_delete
    vim.api.nvim_buf_get_name = orig_buf_get_name
  end)

  describe('send', function()
    it('sends email via stdin without shell redirect', function()
      compose.send()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template send'))
      assert.is_falsy(request_calls[1].cmd:find('<'))
      assert.is_truthy(request_calls[1].stdin)
    end)

    it('adds answered flag only for reply buffers', function()
      -- Simulate a reply buffer name
      vim.api.nvim_buf_get_name = function() return 'Himalaya/reply [42]' end
      compose.send()
      -- Trigger on_data to simulate successful send
      request_calls[1].on_data()
      assert.are.equal(2, #request_calls)
      assert.is_truthy(request_calls[2].cmd:find('flag add'))
    end)

    it('does not add answered flag for new compose', function()
      -- Simulate a new compose buffer name
      vim.api.nvim_buf_get_name = function() return 'Himalaya/write' end
      compose.send()
      request_calls[1].on_data()
      assert.are.equal(1, #request_calls)
    end)

    it('prevents double-send', function()
      compose.send()
      request_calls[1].on_data()
      local count_after_first = #request_calls

      compose.send()
      assert.are.equal(count_after_first, #request_calls)
    end)
  end)

  describe('process_draft', function()
    it('skips prompt when email was already sent', function()
      compose.send()
      request_calls[1].on_data()
      request_calls = {}

      local input_called = false
      vim.fn.input = function() input_called = true; return 'q' end
      compose.process_draft()
      assert.is_false(input_called)
      assert.are.equal(0, #request_calls)
    end)

    it('saves draft via stdin on "d"', function()
      vim.fn.input = function() return 'd' end
      compose.process_draft()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template save'))
      assert.is_truthy(request_calls[1].cmd:find('drafts'))
      assert.is_truthy(request_calls[1].stdin)
      assert.is_falsy(request_calls[1].cmd:find('<'))
    end)

    it('quits without any request on "q"', function()
      vim.fn.input = function() return 'q' end
      compose.process_draft()
      assert.are.equal(0, #request_calls)
    end)

    it('treats empty input as quit', function()
      vim.fn.input = function() return '' end
      compose.process_draft()
      assert.are.equal(0, #request_calls)
    end)

    it('handles uppercase choices', function()
      vim.fn.input = function() return 'D' end
      compose.process_draft()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template save'))
    end)
  end)

  describe('save_draft', function()
    it('saves buffer content and marks unmodified', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {'line1', 'line2'})
      vim.bo.modified = true
      compose.save_draft()
      assert.is_false(vim.bo.modified)
    end)
  end)
end)
