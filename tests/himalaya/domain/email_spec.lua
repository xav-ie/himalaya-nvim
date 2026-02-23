describe('himalaya.domain.email', function()
  local email
  local compose

  before_each(function()
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.domain.email.compose'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.context'] = nil
    require('himalaya.config')._reset()
    email = require('himalaya.domain.email')
    compose = require('himalaya.domain.email.compose')
  end)

  it('exposes all public functions', function()
    assert.is_function(email.list)
    assert.is_function(email.list_with)
    assert.is_function(email.read)
    assert.is_function(email.delete)
    assert.is_function(email.copy)
    assert.is_function(email.move)
    assert.is_function(email.select_folder_then_copy)
    assert.is_function(email.select_folder_then_move)
    assert.is_function(email.flag_add)
    assert.is_function(email.flag_remove)
    assert.is_function(email.download_attachments)
    assert.is_function(email.open_browser)
    assert.is_function(email.complete_contact)
    assert.is_function(email.set_list_envelopes_query)
    assert.is_function(email.apply_search_preset)
    assert.is_function(email.resize_listing)
    assert.is_function(email.cleanup)
    assert.is_function(email.jump_to_unread)
  end)

  it('exposes compose functions', function()
    assert.is_function(compose.write)
    assert.is_function(compose.reply)
    assert.is_function(compose.reply_all)
    assert.is_function(compose.forward)
    assert.is_function(compose.save_draft)
    assert.is_function(compose.process_draft)
  end)

  describe('get_email_id_from_line', function()
    it('extracts numeric id from a listing line', function()
      assert.are.equal(
        '123',
        email._get_email_id_from_line(
          ' 123    \xe2\x94\x82 *   \xe2\x94\x82 Subject              \xe2\x94\x82 Sender               \xe2\x94\x82 2024-01-01 00:00:00'
        )
      )
    end)

    it('returns empty for header line', function()
      assert.are.equal(
        '',
        email._get_email_id_from_line(
          ' ID     \xe2\x94\x82 FLGS \xe2\x94\x82 SUBJECT              \xe2\x94\x82 FROM                 \xe2\x94\x82 DATE               '
        )
      )
    end)

    it('returns empty for separator line', function()
      assert.are.equal(
        '',
        email._get_email_id_from_line(
          '\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\xbc\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80'
        )
      )
    end)
  end)

  describe('mark_envelope_seen', function()
    it('dispatches to thread_listing for thread-listing buffers', function()
      local marked_id
      package.loaded['himalaya.domain.email.thread_listing'] = {
        mark_seen_optimistic = function(id)
          marked_id = id
        end,
      }

      -- Set up current buffer as thread-listing
      vim.api.nvim_buf_set_var(0, 'himalaya_buffer_type', 'thread-listing')
      email._mark_envelope_seen('42')

      assert.are.equal('42', marked_id)
      vim.api.nvim_buf_del_var(0, 'himalaya_buffer_type')
    end)

    it('does not dispatch when no listing buffer exists', function()
      local marked_id
      package.loaded['himalaya.domain.email.thread_listing'] = {
        mark_seen_optimistic = function(id)
          marked_id = id
        end,
      }

      email._mark_envelope_seen('42')
      assert.is_nil(marked_id)
    end)
  end)

  describe('bufwidth', function()
    it('returns a positive number', function()
      local width = email._bufwidth()
      assert.is_true(width > 0)
    end)
  end)

  describe('line_to_complete_item', function()
    it('formats email-only contact', function()
      local result = email._line_to_complete_item('user@example.com')
      assert.are.equal('<user@example.com>', result)
    end)

    it('formats contact with name', function()
      local result = email._line_to_complete_item('user@example.com\tJohn Doe')
      assert.are.equal('"John Doe"<user@example.com>', result)
    end)
  end)

  describe('complete_contact caching', function()
    local system_calls
    local orig_system

    before_each(function()
      system_calls = {}
      local cfg = require('himalaya.config').get()
      cfg.complete_contact_cmd = 'contacts %s'
      orig_system = vim.fn.system
      vim.fn.system = function(cmd)
        table.insert(system_calls, cmd)
        if cmd:find('jo') then
          return 'john@ex.com\tJohn Doe\njoan@ex.com\tJoan Smith\n'
        elseif cmd:find('ma') then
          return 'mary@ex.com\tMary Jones\n'
        end
        return ''
      end
    end)

    after_each(function()
      vim.fn.system = orig_system
    end)

    it('calls external command on first query', function()
      local items = email.complete_contact(0, 'jo')
      assert.are.equal(1, #system_calls)
      assert.are.equal(2, #items)
    end)

    it('filters from cache when query is refined', function()
      email.complete_contact(0, 'jo')
      assert.are.equal(1, #system_calls)
      local items = email.complete_contact(0, 'john')
      assert.are.equal(1, #system_calls)
      assert.are.equal(1, #items)
      assert.is_truthy(items[1]:find('John Doe'))
    end)

    it('calls external command when query is not a refinement', function()
      email.complete_contact(0, 'jo')
      assert.are.equal(1, #system_calls)
      email.complete_contact(0, 'ma')
      assert.are.equal(2, #system_calls)
    end)
  end)
end)

describe('himalaya.domain.email (extended)', function()
  local email
  local captured_json, captured_plain
  local job_kill_count
  local emitted_events

  local function make_listing_buf(ids)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local lines = {}
    for _, id in ipairs(ids) do
      lines[#lines + 1] = string.format(' %d    │ *   │ Subject │ Sender │ 2024-01-01', id)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.b[buf].himalaya_buffer_type = 'listing'
    vim.b[buf].himalaya_account = 'test-acct'
    vim.b[buf].himalaya_folder = 'INBOX'
    vim.b[buf].himalaya_page = 1
    vim.b[buf].himalaya_page_size = 50
    vim.b[buf].himalaya_query = ''
    vim.bo[buf].buftype = 'nofile'
    return buf
  end

  local tracked_bufs = {}
  local function track(buf)
    tracked_bufs[#tracked_bufs + 1] = buf
    return buf
  end

  before_each(function()
    -- Clear email module so it re-captures upvalues from stubs
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.config'] = nil

    captured_json = nil
    captured_plain = nil
    job_kill_count = 0
    emitted_events = {}

    package.loaded['himalaya.events'] = {
      emit = function(event, data)
        table.insert(emitted_events, { event = event, data = data })
      end,
      _reset = function() end,
    }
    package.loaded['himalaya.request'] = {
      json = function(opts)
        captured_json = opts
        return { kill = function() end }
      end,
      plain = function(opts)
        captured_plain = opts
        return { kill = function() end }
      end,
    }
    package.loaded['himalaya.domain.email.probe'] = {
      reset_if_changed = function() end,
      set_total_from_data = function() end,
      total_pages_str = function()
        return '?'
      end,
      start = function() end,
      cancel = function(cb)
        if cb then
          cb()
        end
      end,
      cancel_sync = function() end,
      restart = function() end,
    }
    package.loaded['himalaya.job'] = {
      kill_and_wait = function()
        job_kill_count = job_kill_count + 1
      end,
    }
    package.loaded['himalaya.domain.email.thread_listing'] = {
      cancel_jobs = function() end,
      list = function() end,
      mark_seen_optimistic = function() end,
      is_busy = function()
        return false
      end,
    }
    package.loaded['himalaya.state.context'] = {
      resolve = function()
        return vim.b.himalaya_account or '', vim.b.himalaya_folder or 'INBOX'
      end,
    }
    package.loaded['himalaya.domain.email.flags'] = {
      complete_list = function()
        return { 'Seen', 'Flagged', 'Answered', 'Draft' }
      end,
    }
    package.loaded['himalaya.domain.folder'] = {
      open_picker = function(cb)
        cb('Archive')
      end,
    }

    require('himalaya.config')._reset()
    require('himalaya.config').get().always_confirm = false
    email = require('himalaya.domain.email')
  end)

  after_each(function()
    for _, b in ipairs(tracked_bufs) do
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end
    tracked_bufs = {}
    -- Close extra windows (splits from read())
    while #vim.api.nvim_tabpage_list_wins(0) > 1 do
      local wins = vim.api.nvim_tabpage_list_wins(0)
      pcall(vim.api.nvim_win_close, wins[#wins], true)
    end
    vim.wo.winbar = ''
  end)

  describe('context_email_id', function()
    it('returns cursor line id in listing buffer', function()
      track(make_listing_buf({ 42, 43 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      assert.are.equal('42', email.context_email_id())
    end)

    it('returns buffer var in non-listing buffer', function()
      vim.b.himalaya_current_email_id = '99'
      assert.are.equal('99', email.context_email_id())
      vim.b.himalaya_current_email_id = nil
    end)

    it('returns empty when no context', function()
      local buf = track(vim.api.nvim_create_buf(false, true))
      vim.api.nvim_set_current_buf(buf)
      assert.are.equal('', email.context_email_id())
    end)
  end)

  describe('is_busy', function()
    it('returns false when no jobs in flight', function()
      assert.is_false(email.is_busy())
    end)
  end)

  describe('cleanup', function()
    it('resets module state without error', function()
      email.cleanup()
      assert.is_false(email.is_busy())
    end)
  end)

  describe('complete_contact findstart=1', function()
    it('returns -3 when no complete_contact_cmd', function()
      local orig = vim.api.nvim_err_writeln
      vim.api.nvim_err_writeln = function() end
      assert.are.equal(-3, email.complete_contact(1, ''))
      vim.api.nvim_err_writeln = orig
    end)

    it('finds start position in To: line', function()
      local cfg = require('himalaya.config').get()
      cfg.complete_contact_cmd = 'echo %s'
      local buf = track(vim.api.nvim_create_buf(false, true))
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'To: john' })
      vim.api.nvim_win_set_cursor(0, { 1, 8 })
      local result = email.complete_contact(1, '')
      assert.is_true(result >= 3) -- after "To: "
    end)

    it('handles line with spaces after separator', function()
      local cfg = require('himalaya.config').get()
      cfg.complete_contact_cmd = 'echo %s'
      local buf = track(vim.api.nvim_create_buf(false, true))
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'To: a@b.com,  user' })
      vim.api.nvim_win_set_cursor(0, { 1, 19 })
      local result = email.complete_contact(1, '')
      assert.is_true(result >= 0)
    end)
  end)

  describe('list', function()
    it('switches account and resets state', function()
      local buf = track(make_listing_buf({ 1 }))
      email.list('new-acct')
      assert.are.equal('new-acct', vim.b[buf].himalaya_account)
      assert.are.equal('INBOX', vim.b[buf].himalaya_folder)
      assert.are.equal(1, vim.b[buf].himalaya_page)
      assert.is_not_nil(captured_json)
    end)

    it('preserves existing state without account arg', function()
      local buf = track(make_listing_buf({ 1 }))
      vim.b[buf].himalaya_page = 3
      email.list()
      assert.is_not_nil(captured_json)
    end)

    it('falls back to default account on empty resolve', function()
      package.loaded['himalaya.state.context'] = {
        resolve = function()
          return '', 'INBOX'
        end,
      }
      -- Re-require to pick up new stub
      package.loaded['himalaya.domain.email'] = nil
      email = require('himalaya.domain.email')
      track(make_listing_buf({ 1 }))
      email.list()
      assert.is_not_nil(captured_json)
    end)

    it('sets restore_email_id from opts', function()
      track(make_listing_buf({ 1, 2 }))
      email.list(nil, { restore_email_id = '2' })
      assert.is_not_nil(captured_json)
    end)
  end)

  describe('list_with', function()
    it('issues json request', function()
      track(make_listing_buf({ 1 }))
      email.list_with('acct', 'INBOX', 1, '')
      assert.is_not_nil(captured_json)
      assert.truthy(captured_json.cmd:find('envelope list'))
    end)

    it('on_error clears loading winbar', function()
      track(make_listing_buf({ 1 }))
      vim.wo.winbar = '%#Comment# loading...%*'
      email.list_with('acct', 'INBOX', 1, '')
      captured_json.on_error()
      assert.are.equal('', vim.wo.winbar)
    end)

    it('stale check returns true after new list_with', function()
      track(make_listing_buf({ 1 }))
      email.list_with('acct', 'INBOX', 1, '')
      local first = captured_json
      email.list_with('acct', 'INBOX', 2, '')
      assert.is_true(first.is_stale())
      assert.is_false(captured_json.is_stale())
    end)
  end)

  describe('_cancel_jobs', function()
    it('kills fetch_job when present', function()
      track(make_listing_buf({ 1 }))
      email.list_with('acct', 'INBOX', 1, '')
      job_kill_count = 0
      email._cancel_jobs()
      assert.are.equal(1, job_kill_count)
    end)
  end)

  describe('delete', function()
    it('sends delete command for cursor line', function()
      track(make_listing_buf({ 42, 43 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.delete()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message delete'))
    end)

    it('sends delete command for visual range', function()
      track(make_listing_buf({ 10, 20, 30 }))
      email.delete(1, 3)
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message delete'))
    end)

    it('prompts for confirmation when always_confirm=true', function()
      local cfg = require('himalaya.config').get()
      cfg.always_confirm = true
      local orig = vim.fn.inputdialog
      vim.fn.inputdialog = function()
        return 'y'
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.delete()
      vim.fn.inputdialog = orig
      assert.is_not_nil(captured_plain)
    end)

    it('cancels on confirmation rejection', function()
      local cfg = require('himalaya.config').get()
      cfg.always_confirm = true
      local orig = vim.fn.inputdialog
      vim.fn.inputdialog = function()
        return 'n'
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.delete()
      vim.fn.inputdialog = orig
      assert.is_nil(captured_plain)
    end)

    it('cancels on escape (inputdialog returns _cancel_)', function()
      local cfg = require('himalaya.config').get()
      cfg.always_confirm = true
      local orig = vim.fn.inputdialog
      vim.fn.inputdialog = function()
        return '_cancel_'
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.delete()
      vim.fn.inputdialog = orig
      assert.is_nil(captured_plain)
    end)

    it('on_data refreshes listing', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.delete()
      captured_plain.on_data()
      -- refresh_listing calls list_with which sets captured_json
      assert.is_not_nil(captured_json)
    end)

    it('on_data emits EmailDeleted event', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.delete()
      captured_plain.on_data()
      local found = false
      for _, e in ipairs(emitted_events) do
        if e.event == 'EmailDeleted' then
          assert.are.equal('test-acct', e.data.account)
          assert.are.equal('INBOX', e.data.folder)
          assert.are.equal('42', e.data.ids)
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe('copy', function()
    it('sends copy command', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.copy('Archive')
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message copy'))
    end)

    it('on_data refreshes listing', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.copy('Archive')
      captured_plain.on_data()
      assert.is_not_nil(captured_json)
    end)

    it('on_data emits EmailCopied event', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.copy('Archive')
      captured_plain.on_data()
      local found = false
      for _, e in ipairs(emitted_events) do
        if e.event == 'EmailCopied' then
          assert.are.equal('test-acct', e.data.account)
          assert.are.equal('INBOX', e.data.folder)
          assert.are.equal('42', e.data.ids)
          assert.are.equal('Archive', e.data.target_folder)
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('supports visual range', function()
      track(make_listing_buf({ 10, 20 }))
      email.copy('Archive', 1, 2)
      assert.is_not_nil(captured_plain)
    end)
  end)

  describe('move', function()
    it('sends move command', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.move('Trash')
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message move'))
    end)

    it('prompts for confirmation when always_confirm=true', function()
      local cfg = require('himalaya.config').get()
      cfg.always_confirm = true
      local orig = vim.fn.inputdialog
      vim.fn.inputdialog = function()
        return 'y'
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.move('Trash')
      vim.fn.inputdialog = orig
      assert.is_not_nil(captured_plain)
    end)

    it('cancels on rejection', function()
      local cfg = require('himalaya.config').get()
      cfg.always_confirm = true
      local orig = vim.fn.inputdialog
      vim.fn.inputdialog = function()
        return 'n'
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.move('Trash')
      vim.fn.inputdialog = orig
      assert.is_nil(captured_plain)
    end)

    it('on_data refreshes listing', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.move('Trash')
      captured_plain.on_data()
      assert.is_not_nil(captured_json)
    end)

    it('on_data emits EmailMoved event', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.move('Trash')
      captured_plain.on_data()
      local found = false
      for _, e in ipairs(emitted_events) do
        if e.event == 'EmailMoved' then
          assert.are.equal('test-acct', e.data.account)
          assert.are.equal('INBOX', e.data.folder)
          assert.are.equal('42', e.data.ids)
          assert.are.equal('Trash', e.data.target_folder)
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe('select_folder_then_copy', function()
    it('opens picker then copies', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.select_folder_then_copy()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message copy'))
    end)

    it('supports visual range', function()
      track(make_listing_buf({ 10, 20 }))
      email.select_folder_then_copy(1, 2)
      assert.is_not_nil(captured_plain)
    end)
  end)

  describe('select_folder_then_move', function()
    it('opens picker then moves', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.select_folder_then_move()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message move'))
    end)
  end)

  describe('mark_seen', function()
    it('sends flag add Seen command', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.mark_seen()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('flag add'))
      assert.truthy(captured_plain.cmd:find('Seen'))
    end)

    it('on_data refreshes listing via saved_view', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.mark_seen()
      captured_plain.on_data()
      -- refresh_listing → list_with sets captured_json
      assert.is_not_nil(captured_json)
    end)

    it('on_data emits EmailMarkedSeen event', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.mark_seen()
      captured_plain.on_data()
      local found = false
      for _, e in ipairs(emitted_events) do
        if e.event == 'EmailMarkedSeen' then
          assert.are.equal('test-acct', e.data.account)
          assert.are.equal('INBOX', e.data.folder)
          assert.are.equal('42', e.data.ids)
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('supports visual range', function()
      track(make_listing_buf({ 10, 20 }))
      email.mark_seen(1, 2)
      assert.is_not_nil(captured_plain)
    end)
  end)

  describe('mark_unseen', function()
    it('sends flag remove Seen command', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.mark_unseen()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('flag remove'))
      assert.truthy(captured_plain.cmd:find('Seen'))
    end)

    it('on_data emits EmailMarkedUnseen event', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.mark_unseen()
      captured_plain.on_data()
      local found = false
      for _, e in ipairs(emitted_events) do
        if e.event == 'EmailMarkedUnseen' then
          assert.are.equal('test-acct', e.data.account)
          assert.are.equal('INBOX', e.data.folder)
          assert.are.equal('42', e.data.ids)
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('supports visual range', function()
      track(make_listing_buf({ 10, 20, 30 }))
      email.mark_unseen(1, 3)
      assert.is_not_nil(captured_plain)
    end)
  end)

  describe('flag_add', function()
    it('presents flag picker and sends add command', function()
      local orig_select = vim.ui.select
      vim.ui.select = function(items, _, cb)
        cb(items[2]) -- 'Flagged'
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.flag_add()
      vim.ui.select = orig_select
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('flag add'))
    end)

    it('does nothing when user cancels picker', function()
      local orig_select = vim.ui.select
      vim.ui.select = function(_, _, cb)
        cb(nil)
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.flag_add()
      vim.ui.select = orig_select
      assert.is_nil(captured_plain)
    end)

    it('on_data emits EmailFlagAdded event', function()
      local orig_select = vim.ui.select
      vim.ui.select = function(items, _, cb)
        cb(items[2]) -- 'Flagged'
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.flag_add()
      vim.ui.select = orig_select
      captured_plain.on_data()
      local found = false
      for _, e in ipairs(emitted_events) do
        if e.event == 'EmailFlagAdded' then
          assert.are.equal('test-acct', e.data.account)
          assert.are.equal('INBOX', e.data.folder)
          assert.are.equal('42', e.data.ids)
          assert.are.equal('Flagged', e.data.flag)
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('supports visual range', function()
      local orig_select = vim.ui.select
      vim.ui.select = function(items, _, cb)
        cb(items[1])
      end
      track(make_listing_buf({ 10, 20 }))
      email.flag_add(1, 2)
      vim.ui.select = orig_select
      assert.is_not_nil(captured_plain)
    end)
  end)

  describe('flag_remove', function()
    it('uses current flags from envelope cache', function()
      local buf = track(make_listing_buf({ 42 }))
      vim.b[buf].himalaya_envelopes = {
        { id = 42, flags = { 'Seen', 'Flagged' } },
      }
      local picker_items
      local orig_select = vim.ui.select
      vim.ui.select = function(items, _, cb)
        picker_items = items
        cb(items[1])
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.flag_remove()
      vim.ui.select = orig_select
      assert.are.same({ 'Seen', 'Flagged' }, picker_items)
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('flag remove'))
    end)

    it('falls back to complete_list when no flags cached', function()
      track(make_listing_buf({ 42 }))
      local picker_items
      local orig_select = vim.ui.select
      vim.ui.select = function(items, _, cb)
        picker_items = items
        cb(items[1])
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.flag_remove()
      vim.ui.select = orig_select
      -- Falls back to complete_list: Seen, Flagged, Answered, Draft
      assert.are.equal(4, #picker_items)
    end)

    it('does nothing when user cancels', function()
      local orig_select = vim.ui.select
      vim.ui.select = function(_, _, cb)
        cb(nil)
      end
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.flag_remove()
      vim.ui.select = orig_select
      assert.is_nil(captured_plain)
    end)

    it('on_data emits EmailFlagRemoved event', function()
      local buf = track(make_listing_buf({ 42 }))
      vim.b[buf].himalaya_envelopes = {
        { id = 42, flags = { 'Seen', 'Flagged' } },
      }
      local orig_select = vim.ui.select
      vim.ui.select = function(items, _, cb)
        cb(items[1]) -- 'Seen'
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.flag_remove()
      vim.ui.select = orig_select
      captured_plain.on_data()
      local found = false
      for _, e in ipairs(emitted_events) do
        if e.event == 'EmailFlagRemoved' then
          assert.are.equal('test-acct', e.data.account)
          assert.are.equal('INBOX', e.data.folder)
          assert.are.equal('42', e.data.ids)
          assert.are.equal('Seen', e.data.flag)
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe('download_attachments', function()
    it('sends attachment download command', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.download_attachments()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('attachment download'))
    end)

    it('on_data reports no attachments', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.download_attachments()
      local orig = vim.notify
      vim.notify = function() end
      captured_plain.on_data('')
      vim.notify = orig
    end)

    it('on_data reports downloaded files', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.download_attachments()
      local orig = vim.notify
      vim.notify = function() end
      captured_plain.on_data('file1.pdf\nfile2.txt')
      vim.notify = orig
    end)
  end)

  describe('open_browser', function()
    it('sends export command', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.open_browser()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message export'))
    end)

    it('on_data logs output', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.open_browser()
      local orig = vim.notify
      vim.notify = function() end
      captured_plain.on_data('Opened in browser')
      vim.notify = orig
    end)
  end)

  describe('read', function()
    it('opens email in split window', function()
      track(make_listing_buf({ 42, 43 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.read()
      assert.is_not_nil(captured_plain)
      assert.truthy(captured_plain.cmd:find('message read'))

      -- Simulate on_data
      captured_plain.on_data('Subject: Test\n\nHello world\n')
      -- A new split should exist
      assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(0))
      assert.are.equal('himalaya-email-reading', vim.bo.filetype)
      assert.are.equal('42', vim.b.himalaya_current_email_id)
    end)

    it('trims trailing empty line', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.read()
      captured_plain.on_data('line1\nline2\n')
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are_not.equal('', lines[#lines])
    end)

    it('reuses existing reading window', function()
      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      -- Create an existing email reading window
      local email_buf = vim.api.nvim_create_buf(true, true)
      track(email_buf)
      vim.api.nvim_open_win(email_buf, false, { split = 'below' })
      vim.api.nvim_buf_set_name(email_buf, 'Himalaya/read email [old]')
      local win_count = #vim.api.nvim_tabpage_list_wins(0)

      email.read()
      captured_plain.on_data('New email content')

      -- Should reuse, not create a new split
      assert.are.equal(win_count, #vim.api.nvim_tabpage_list_wins(0))
    end)

    it('on_error calls probe.restart', function()
      local restarted = false
      package.loaded['himalaya.domain.email.probe'].restart = function()
        restarted = true
      end
      package.loaded['himalaya.domain.email'] = nil
      email = require('himalaya.domain.email')

      track(make_listing_buf({ 42 }))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.read()
      captured_plain.on_error()
      assert.is_true(restarted)
    end)
  end)

  describe('set_list_envelopes_query', function()
    it('opens search and refreshes on callback', function()
      local search_opened = false
      package.loaded['himalaya.ui.search'] = {
        open = function(cb)
          search_opened = true
          cb('subject hello', 'Sent')
        end,
      }
      local buf = track(make_listing_buf({ 1 }))
      email.set_list_envelopes_query()
      assert.is_true(search_opened)
      assert.are.equal('subject hello', vim.b[buf].himalaya_query)
      assert.are.equal('Sent', vim.b[buf].himalaya_folder)
      assert.are.equal(1, vim.b[buf].himalaya_page)
    end)

    it('preserves folder when callback returns empty folder', function()
      package.loaded['himalaya.ui.search'] = {
        open = function(cb)
          cb('test', '')
        end,
      }
      local buf = track(make_listing_buf({ 1 }))
      email.set_list_envelopes_query()
      assert.are.equal('INBOX', vim.b[buf].himalaya_folder)
    end)
  end)

  describe('jump_to_unread', function()
    it('moves cursor to first unseen line', function()
      local buf = track(make_listing_buf({ 10, 20, 30 }))
      vim.b[buf].himalaya_envelopes = {
        { id = 10, flags = { 'Seen' }, subject = 'A', from = { name = 'X' }, date = '2024-01-01' },
        { id = 20, flags = {}, subject = 'B', from = { name = 'Y' }, date = '2024-01-01' },
        { id = 30, flags = { 'Seen' }, subject = 'C', from = { name = 'Z' }, date = '2024-01-01' },
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.jump_to_unread()
      assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('wraps from end to beginning', function()
      local buf = track(make_listing_buf({ 10, 20, 30 }))
      vim.b[buf].himalaya_envelopes = {
        { id = 10, flags = {}, subject = 'A', from = { name = 'X' }, date = '2024-01-01' },
        { id = 20, flags = { 'Seen' }, subject = 'B', from = { name = 'Y' }, date = '2024-01-01' },
        { id = 30, flags = { 'Seen' }, subject = 'C', from = { name = 'Z' }, date = '2024-01-01' },
      }
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      email.jump_to_unread()
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('notifies when all emails are seen', function()
      local buf = track(make_listing_buf({ 10, 20 }))
      vim.b[buf].himalaya_envelopes = {
        { id = 10, flags = { 'Seen' }, subject = 'A', from = { name = 'X' }, date = '2024-01-01' },
        { id = 20, flags = { 'Seen' }, subject = 'B', from = { name = 'Y' }, date = '2024-01-01' },
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local notified = false
      local orig = vim.notify
      vim.notify = function(msg)
        if type(msg) == 'string' and msg:find('No unread') then
          notified = true
        end
      end
      email.jump_to_unread()
      vim.notify = orig
      assert.is_true(notified)
    end)

    it('delegates to thread_listing for thread-listing buffers', function()
      local jumped = false
      package.loaded['himalaya.domain.email.thread_listing'].jump_to_unread = function()
        jumped = true
      end
      local buf = track(make_listing_buf({ 42 }))
      vim.b[buf].himalaya_buffer_type = 'thread-listing'
      email.jump_to_unread()
      assert.is_true(jumped)
    end)
  end)

  describe('resolve_target_ids from read buffer', function()
    it('returns buffer var when not in listing', function()
      vim.b.himalaya_current_email_id = '77'
      email.delete()
      assert.is_not_nil(captured_plain)
      vim.b.himalaya_current_email_id = nil
    end)
  end)

  describe('refresh_listing thread mode', function()
    it('delegates to thread_listing.list', function()
      local thread_list_called = false
      package.loaded['himalaya.domain.email.thread_listing'].list = function()
        thread_list_called = true
      end
      local buf = track(make_listing_buf({ 42 }))
      vim.b[buf].himalaya_buffer_type = 'thread-listing'
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      email.delete()
      captured_plain.on_data()
      assert.is_true(thread_list_called)
    end)
  end)

  describe('mark_envelope_seen flat listing', function()
    it('returns early when no envelopes var', function()
      track(make_listing_buf({ 42 }))
      -- Don't set himalaya_envelopes — should return early without error
      email._mark_envelope_seen('42')
    end)
  end)

  describe('restore_cursor saved_view path', function()
    it('restores view after mark_seen + refresh', function()
      track(make_listing_buf({ 1, 2, 3 }))
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- mark_seen sets saved_view before refresh
      email.mark_seen()
      assert.is_not_nil(captured_plain)

      -- Invoke on_data → sets saved_view + calls refresh_listing → list_with
      captured_plain.on_data()
      assert.is_not_nil(captured_json)

      -- Invoke list_with on_data → on_list_with → restore_cursor uses saved_view
      captured_json.on_data({
        { id = 1, subject = 'A', from = { name = 'X' }, date = '2024-01-01', flags = {} },
        { id = 2, subject = 'B', from = { name = 'Y' }, date = '2024-01-01', flags = {} },
        { id = 3, subject = 'C', from = { name = 'Z' }, date = '2024-01-01', flags = {} },
      })
      -- Should not error — saved_view path was exercised
    end)
  end)
end)
