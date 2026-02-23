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
    package.loaded['himalaya.state.context'] = nil
    package.loaded['himalaya.domain.email'] = nil

    package.loaded['himalaya.request'] = {
      plain = function(opts)
        table.insert(request_calls, opts)
      end,
      json = function() end,
    }
    package.loaded['himalaya.log'] = {
      info = function() end,
      warn = function() end,
      err = function() end,
      debug = function() end,
    }
    package.loaded['himalaya.state.account'] = {
      flag = function(acct)
        if acct == '' then
          return ''
        end
        return '--account ' .. acct
      end,
    }
    package.loaded['himalaya.state.context'] = {
      resolve = function()
        return 'test-acct', 'INBOX'
      end,
    }
    package.loaded['himalaya.domain.email'] = {
      context_email_id = function()
        return '42'
      end,
    }

    vim.b.himalaya_account = 'test-acct'
    vim.b.himalaya_folder = 'INBOX'

    compose = require('himalaya.domain.email.compose')

    orig_input = vim.fn.input
    orig_tempname = vim.fn.tempname
    orig_writefile = vim.fn.writefile
    orig_delete = vim.fn.delete
    orig_buf_get_name = vim.api.nvim_buf_get_name

    vim.fn.tempname = function()
      return '/tmp/test_draft'
    end
    vim.fn.writefile = function()
      return 0
    end
    vim.fn.delete = function()
      return 0
    end
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
      -- Simulate a reply buffer with reply_id set
      vim.b.himalaya_reply_id = '42'
      compose.send()
      -- Trigger on_data to simulate successful send
      request_calls[1].on_data()
      assert.are.equal(2, #request_calls)
      assert.is_truthy(request_calls[2].cmd:find('flag add'))
    end)

    it('does not add answered flag for new compose', function()
      -- No reply_id set — new compose
      vim.b.himalaya_reply_id = nil
      compose.send()
      request_calls[1].on_data()
      assert.are.equal(1, #request_calls)
    end)

    it('handles buffer deleted before on_data fires', function()
      -- Create a scratch buffer and set reply vars on it
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { 'body' })
      vim.api.nvim_buf_set_var(scratch, 'himalaya_account', 'test-acct')
      vim.api.nvim_buf_set_var(scratch, 'himalaya_folder', 'INBOX')
      vim.api.nvim_buf_set_var(scratch, 'himalaya_reply_id', '99')

      compose.send(scratch)
      assert.are.equal(1, #request_calls)

      -- Delete the buffer before the callback fires
      vim.api.nvim_buf_delete(scratch, { force = true })
      assert.is_false(vim.api.nvim_buf_is_valid(scratch))

      -- on_data should not error, and should still fire the answered flag request
      assert.has_no.errors(function()
        request_calls[1].on_data()
      end)
      assert.are.equal(2, #request_calls)
      assert.is_truthy(request_calls[2].cmd:find('flag add'))
      assert.are.equal('99', request_calls[2].args[3])
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
      vim.fn.input = function()
        input_called = true
        return 'q'
      end
      compose.process_draft()
      assert.is_false(input_called)
      assert.are.equal(0, #request_calls)
    end)

    it('saves draft via stdin on "d"', function()
      vim.fn.input = function()
        return 'd'
      end
      compose.process_draft()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template save'))
      assert.is_truthy(request_calls[1].cmd:find('drafts'))
      assert.is_truthy(request_calls[1].stdin)
      assert.is_falsy(request_calls[1].cmd:find('<'))
    end)

    it('emits DraftSaved event on "d"', function()
      -- Stub events module with capturing emit
      local draft_events = {}
      package.loaded['himalaya.events'] = {
        emit = function(event, data)
          table.insert(draft_events, { event = event, data = data })
        end,
        _reset = function() end,
      }
      package.loaded['himalaya.domain.email.compose'] = nil
      compose = require('himalaya.domain.email.compose')
      vim.fn.input = function()
        return 'd'
      end
      compose.process_draft()
      local found = false
      for _, e in ipairs(draft_events) do
        if e.event == 'DraftSaved' then
          assert.are.equal('test-acct', e.data.account)
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('quits without any request on "q"', function()
      vim.fn.input = function()
        return 'q'
      end
      compose.process_draft()
      assert.are.equal(0, #request_calls)
    end)

    it('treats empty input as quit', function()
      vim.fn.input = function()
        return ''
      end
      compose.process_draft()
      assert.are.equal(0, #request_calls)
    end)

    it('handles uppercase choices', function()
      vim.fn.input = function()
        return 'D'
      end
      compose.process_draft()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template save'))
    end)
  end)

  describe('save_draft', function()
    it('saves buffer content and marks unmodified', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'line1', 'line2' })
      vim.bo.modified = true
      compose.save_draft()
      assert.is_false(vim.bo.modified)
    end)
  end)

  describe('process_draft cancel', function()
    it('re-displays buffer on "c" choice', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'draft body' })
      vim.api.nvim_buf_set_var(buf, 'himalaya_account', 'test-acct')

      vim.fn.input = function()
        return 'c'
      end
      compose.process_draft(buf)
      -- Buffer should be displayed in a window
      assert.are.equal(buf, vim.api.nvim_win_get_buf(0))
      assert.are.equal(0, #request_calls)

      -- cleanup
      while #vim.api.nvim_tabpage_list_wins(0) > 1 do
        local wins = vim.api.nvim_tabpage_list_wins(0)
        pcall(vim.api.nvim_win_close, wins[#wins], true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)

    it('logs error when process_draft pcall fails', function()
      local logged_errors = {}
      package.loaded['himalaya.log'].err = function(msg)
        table.insert(logged_errors, msg)
      end

      vim.fn.input = function()
        error('test-error')
      end
      compose.process_draft()
      assert.are.equal(1, #logged_errors)
      assert.is_truthy(logged_errors[1]:find('test%-error'))
    end)
  end)
end)

describe('himalaya.domain.email.compose (write/reply/forward)', function()
  local compose
  local request_calls
  local emitted_events
  local tracked_bufs = {}

  local function track(buf)
    tracked_bufs[#tracked_bufs + 1] = buf
    return buf
  end

  before_each(function()
    request_calls = {}
    emitted_events = {}

    package.loaded['himalaya.domain.email.compose'] = nil
    package.loaded['himalaya.request'] = nil
    package.loaded['himalaya.log'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.context'] = nil
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.events'] = nil
    package.loaded['himalaya.ui.win'] = nil

    package.loaded['himalaya.request'] = {
      plain = function(opts)
        table.insert(request_calls, opts)
      end,
      json = function() end,
    }
    package.loaded['himalaya.log'] = {
      info = function() end,
      warn = function() end,
      err = function() end,
      debug = function() end,
    }
    package.loaded['himalaya.state.account'] = {
      flag = function(acct)
        if acct == '' then
          return ''
        end
        return '--account ' .. acct
      end,
    }
    package.loaded['himalaya.state.context'] = {
      resolve = function()
        return 'test-acct', 'INBOX'
      end,
    }
    package.loaded['himalaya.domain.email'] = {
      context_email_id = function()
        return '42'
      end,
    }
    package.loaded['himalaya.events'] = {
      emit = function(event, data)
        table.insert(emitted_events, { event = event, data = data })
      end,
      _reset = function() end,
    }
    package.loaded['himalaya.ui.win'] = {
      find_by_name = function()
        return nil
      end,
    }

    package.loaded['himalaya.config'] = nil
    require('himalaya.config')._reset()

    compose = require('himalaya.domain.email.compose')
  end)

  after_each(function()
    require('himalaya.config')._reset()
    for _, b in ipairs(tracked_bufs) do
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end
    tracked_bufs = {}
    while #vim.api.nvim_tabpage_list_wins(0) > 1 do
      local wins = vim.api.nvim_tabpage_list_wins(0)
      pcall(vim.api.nvim_win_close, wins[#wins], true)
    end
  end)

  describe('write', function()
    it('opens compose buffer with provided template', function()
      compose.write('To: \nSubject: \n\nBody')
      -- open_write_buffer creates a new buffer via vim.cmd split/edit
      assert.are.equal('himalaya-email-writing', vim.bo.filetype)
      assert.are.equal('test-acct', vim.b.himalaya_account)
      assert.are.equal('INBOX', vim.b.himalaya_folder)
      assert.is_nil(vim.b.himalaya_reply_id)
      assert.are.equal(1, #emitted_events)
      assert.are.equal('ComposeOpened', emitted_events[1].event)
      assert.are.equal('write', emitted_events[1].data.mode)
      track(vim.api.nvim_get_current_buf())
    end)

    it('fetches template via request when no template given', function()
      compose.write()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template write'))
      -- Trigger on_data callback
      request_calls[1].on_data('To: \nSubject: \n\nFetched body')
      assert.are.equal('himalaya-email-writing', vim.bo.filetype)
      assert.are.equal(1, #emitted_events)
      assert.are.equal('ComposeOpened', emitted_events[1].event)
      track(vim.api.nvim_get_current_buf())
    end)

    it('strips carriage returns and trailing empty line from content', function()
      compose.write('line1\r\nline2\r\n')
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      -- \r should be stripped; trailing empty line removed
      for _, line in ipairs(lines) do
        assert.is_falsy(line:find('\r'))
      end
      assert.are_not.equal('', lines[#lines])
      track(vim.api.nvim_get_current_buf())
    end)
  end)

  describe('reply', function()
    it('fetches reply template and opens buffer', function()
      compose.reply()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template reply'))
      assert.is_falsy(request_calls[1].cmd:find('%-%-all'))
      -- Trigger on_data
      request_calls[1].on_data('Re: Test\n\n> original')
      assert.are.equal('himalaya-email-writing', vim.bo.filetype)
      assert.are.equal('42', vim.b.himalaya_reply_id)
      assert.are.equal(1, #emitted_events)
      assert.are.equal('reply', emitted_events[1].data.mode)
      assert.are.equal('42', emitted_events[1].data.reply_id)
      track(vim.api.nvim_get_current_buf())
    end)
  end)

  describe('reply_all', function()
    it('fetches reply-all template and opens buffer', function()
      compose.reply_all()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template reply'))
      assert.is_truthy(request_calls[1].cmd:find('%-%-all'))
      -- Trigger on_data
      request_calls[1].on_data('Re: Test\n\n> original')
      assert.are.equal('himalaya-email-writing', vim.bo.filetype)
      assert.are.equal('42', vim.b.himalaya_reply_id)
      assert.are.equal(1, #emitted_events)
      assert.are.equal('reply_all', emitted_events[1].data.mode)
      track(vim.api.nvim_get_current_buf())
    end)
  end)

  describe('forward', function()
    it('fetches forward template and opens buffer', function()
      compose.forward()
      assert.are.equal(1, #request_calls)
      assert.is_truthy(request_calls[1].cmd:find('template forward'))
      -- Trigger on_data
      request_calls[1].on_data('Fwd: Test\n\nforwarded body')
      assert.are.equal('himalaya-email-writing', vim.bo.filetype)
      -- forward does NOT set reply_id
      assert.is_nil(vim.b.himalaya_reply_id)
      assert.are.equal(1, #emitted_events)
      assert.are.equal('forward', emitted_events[1].data.mode)
      track(vim.api.nvim_get_current_buf())
    end)
  end)

  describe('signature', function()
    it('appends string signature to buffer', function()
      require('himalaya.config').setup({ signature = '--\nJohn Doe' })
      package.loaded['himalaya.domain.email.compose'] = nil
      compose = require('himalaya.domain.email.compose')
      compose.write('To: \nSubject: \n\nBody')
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal('', lines[#lines - 2])
      assert.are.equal('--', lines[#lines - 1])
      assert.are.equal('John Doe', lines[#lines])
      track(vim.api.nvim_get_current_buf())
    end)

    it('appends per-account signature when account matches', function()
      require('himalaya.config').setup({
        signature = {
          ['test-acct'] = '--\nWork Sig',
          personal = '--\nPersonal Sig',
        },
      })
      package.loaded['himalaya.domain.email.compose'] = nil
      compose = require('himalaya.domain.email.compose')
      compose.write('To: \nSubject: \n\nBody')
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal('', lines[#lines - 2])
      assert.are.equal('--', lines[#lines - 1])
      assert.are.equal('Work Sig', lines[#lines])
      track(vim.api.nvim_get_current_buf())
    end)

    it('does not append signature when account is missing from table', function()
      require('himalaya.config').setup({
        signature = {
          other = '--\nOther Sig',
        },
      })
      package.loaded['himalaya.domain.email.compose'] = nil
      compose = require('himalaya.domain.email.compose')
      compose.write('To: \nSubject: \n\nBody')
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      -- Last line should be Body, no blank + signature appended
      assert.are.equal('Body', lines[#lines])
      track(vim.api.nvim_get_current_buf())
    end)

    it('does not append signature when signature is nil', function()
      require('himalaya.config').setup({ signature = nil })
      package.loaded['himalaya.domain.email.compose'] = nil
      compose = require('himalaya.domain.email.compose')
      compose.write('To: \nSubject: \n\nBody')
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal('Body', lines[#lines])
      track(vim.api.nvim_get_current_buf())
    end)

    it('does not append blank line when signature is empty string', function()
      require('himalaya.config').setup({ signature = '' })
      package.loaded['himalaya.domain.email.compose'] = nil
      compose = require('himalaya.domain.email.compose')
      compose.write('To: \nSubject: \n\nBody')
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal('Body', lines[#lines])
      track(vim.api.nvim_get_current_buf())
    end)
  end)

  describe('open_write_buffer multi-window', function()
    it('uses edit when multiple windows exist', function()
      -- Create a second window so winnr('$') > 1
      vim.cmd('botright split')
      compose.write('Template content')
      assert.are.equal('himalaya-email-writing', vim.bo.filetype)
      track(vim.api.nvim_get_current_buf())
    end)

    it('reuses reading window when it exists', function()
      -- Create a "reading" window
      local read_buf = vim.api.nvim_create_buf(true, true)
      track(read_buf)
      vim.api.nvim_open_win(read_buf, false, { split = 'below' })
      vim.api.nvim_buf_set_name(read_buf, 'Himalaya/read email [42]')

      -- Stub win.find_by_name to return the reading window
      local read_win = nil
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(w) == read_buf then
          read_win = w
          break
        end
      end
      package.loaded['himalaya.ui.win'].find_by_name = function()
        return read_win
      end
      -- Re-require compose to pick up the new win stub
      package.loaded['himalaya.domain.email.compose'] = nil
      compose = require('himalaya.domain.email.compose')

      compose.write('Template in reading win')
      assert.are.equal('himalaya-email-writing', vim.bo.filetype)
      track(vim.api.nvim_get_current_buf())
    end)
  end)
end)
