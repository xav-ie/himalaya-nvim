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
    assert.is_function(email.resize_listing)
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
