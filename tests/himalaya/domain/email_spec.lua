describe('himalaya.domain.email', function()
  local email

  before_each(function()
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.folder'] = nil
    require('himalaya.config')._reset()
    email = require('himalaya.domain.email')
  end)

  it('exposes all public functions', function()
    assert.is_function(email.list)
    assert.is_function(email.list_with)
    assert.is_function(email.read)
    assert.is_function(email.write)
    assert.is_function(email.reply)
    assert.is_function(email.reply_all)
    assert.is_function(email.forward)
    assert.is_function(email.delete)
    assert.is_function(email.copy)
    assert.is_function(email.move)
    assert.is_function(email.select_folder_then_copy)
    assert.is_function(email.select_folder_then_move)
    assert.is_function(email.flag_add)
    assert.is_function(email.flag_remove)
    assert.is_function(email.download_attachments)
    assert.is_function(email.open_browser)
    assert.is_function(email.save_draft)
    assert.is_function(email.process_draft)
    assert.is_function(email.complete_contact)
    assert.is_function(email.set_list_envelopes_query)
    assert.is_function(email.resize_listing)
  end)

  describe('get_email_id_from_line', function()
    it('extracts numeric id from a listing line', function()
      assert.are.equal('123', email._get_email_id_from_line(' 123    \xe2\x94\x82 *   \xe2\x94\x82 Subject              \xe2\x94\x82 Sender               \xe2\x94\x82 2024-01-01 00:00:00'))
    end)

    it('returns empty for header line', function()
      assert.are.equal('', email._get_email_id_from_line(' ID     \xe2\x94\x82 FLGS \xe2\x94\x82 SUBJECT              \xe2\x94\x82 FROM                 \xe2\x94\x82 DATE               '))
    end)

    it('returns empty for separator line', function()
      assert.are.equal('', email._get_email_id_from_line('\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\xbc\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80'))
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
end)
