describe('himalaya.ui.renderer', function()
  local renderer
  local config

  before_each(function()
    package.loaded['himalaya.ui.renderer'] = nil
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
    renderer = require('himalaya.ui.renderer')
  end)

  describe('format_flags', function()
    it('returns * for unseen (no Seen flag)', function()
      assert.are.equal('*', renderer.format_flags({ flags = {} }))
    end)

    it('returns empty for seen envelope', function()
      assert.are.equal('', renderer.format_flags({ flags = { 'Seen' } }))
    end)

    it('returns R for answered', function()
      assert.are.equal('R', renderer.format_flags({ flags = { 'Seen', 'Answered' } }))
    end)

    it('returns ! for flagged', function()
      assert.are.equal('!', renderer.format_flags({ flags = { 'Seen', 'Flagged' } }))
    end)

    it('returns @ for attachment', function()
      assert.are.equal('@', renderer.format_flags({ flags = { 'Seen' }, has_attachment = true }))
    end)

    it('combines multiple flags', function()
      assert.are.equal('* R ! @', renderer.format_flags({
        flags = { 'Answered', 'Flagged' },
        has_attachment = true,
      }))
    end)
  end)

  describe('format_from', function()
    it('returns empty for nil', function()
      assert.are.equal('', renderer.format_from(nil))
    end)

    it('prefers name over addr', function()
      assert.are.equal('Alice', renderer.format_from({ name = 'Alice', addr = 'a@b.com' }))
    end)

    it('falls back to addr when name is empty', function()
      assert.are.equal('a@b.com', renderer.format_from({ name = '', addr = 'a@b.com' }))
    end)

    it('falls back to addr when name is missing', function()
      assert.are.equal('a@b.com', renderer.format_from({ addr = 'a@b.com' }))
    end)

    it('returns empty when both are missing', function()
      assert.are.equal('', renderer.format_from({}))
    end)
  end)

  describe('fit', function()
    it('pads short strings', function()
      assert.are.equal('hi    ', renderer.fit('hi', 6))
    end)

    it('returns exact-width strings unchanged', function()
      assert.are.equal('hello', renderer.fit('hello', 5))
    end)

    it('truncates long strings with ~', function()
      local result = renderer.fit('hello world', 6)
      assert.are.equal(6, vim.fn.strdisplaywidth(result))
      assert.is_truthy(result:find('~'))
    end)

    it('returns empty for zero width', function()
      assert.are.equal('', renderer.fit('hello', 0))
    end)

    it('produces correct display width for multi-byte', function()
      local result = renderer.fit('héllo', 4)
      assert.are.equal(4, vim.fn.strdisplaywidth(result))
    end)
  end)

  describe('render', function()
    it('produces header + data lines', function()
      local envelopes = {
        {
          id = '1',
          flags = {},
          has_attachment = false,
          subject = 'Test subject',
          from = { name = 'Alice', addr = 'alice@example.com' },
          date = '2024-01-15 09:30:00',
        },
      }
      local lines = renderer.render(envelopes, 80)
      assert.are.equal(2, #lines)
      -- Header contains column names
      assert.is_truthy(lines[1]:find('ID'))
      assert.is_truthy(lines[1]:find('FLGS'))
      assert.is_truthy(lines[1]:find('SUBJECT'))
      assert.is_truthy(lines[1]:find('FROM'))
      assert.is_truthy(lines[1]:find('DATE'))
      -- Data line contains the envelope data
      assert.is_truthy(lines[2]:find('1'))
      assert.is_truthy(lines[2]:find('Alice'))
    end)

    it('uses pipe delimiters', function()
      local envelopes = {
        {
          id = '42',
          flags = { 'Seen' },
          subject = 'Hello',
          from = { name = 'Bob', addr = 'bob@test.com' },
          date = '2024-02-01 14:00:00',
        },
      }
      local lines = renderer.render(envelopes, 80)
      -- Lines start and end with |
      for _, line in ipairs(lines) do
        assert.is_truthy(line:match('^|'))
        assert.is_truthy(line:match('|$'))
      end
    end)

    it('handles from as array', function()
      local envelopes = {
        {
          id = '5',
          flags = { 'Seen' },
          subject = 'Multi sender',
          from = { { name = 'Carol', addr = 'carol@test.com' } },
          date = '2024-03-01 10:00:00',
        },
      }
      local lines = renderer.render(envelopes, 80)
      assert.is_truthy(lines[2]:find('Carol'))
    end)

    it('shows unseen flag as *', function()
      local envelopes = {
        {
          id = '7',
          flags = {},
          subject = 'Unread',
          from = { name = 'Dave', addr = 'dave@test.com' },
          date = '2024-04-01 08:00:00',
        },
      }
      local lines = renderer.render(envelopes, 80)
      assert.is_truthy(lines[2]:find('%*'))
    end)
  end)

  describe('nerd mode', function()
    before_each(function()
      config.setup({ use_nerd = true })
    end)

    it('uses nerd symbols for unseen', function()
      local result = renderer.format_flags({ flags = {} })
      assert.is_truthy(result:find('\xef\x93\xb5'))
    end)

    it('uses nerd symbols for answered', function()
      local result = renderer.format_flags({ flags = { 'Seen', 'Answered' } })
      assert.is_truthy(result:find('\xef\x84\x92'))
    end)

    it('uses nerd symbols for flagged', function()
      local result = renderer.format_flags({ flags = { 'Seen', 'Flagged' } })
      assert.is_truthy(result:find('󰈿'))
    end)

    it('uses nerd symbols for attachment', function()
      local result = renderer.format_flags({ flags = { 'Seen' }, has_attachment = true })
      assert.is_truthy(result:find('\xef\x83\x86'))
    end)

    it('uses nerd header in render', function()
      local lines = renderer.render({}, 80)
      assert.is_truthy(lines[1]:find('\xef\x80\xa4'))
    end)
  end)
end)
