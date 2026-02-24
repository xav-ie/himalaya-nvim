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
    it('puts ! in slot 1 for flagged', function()
      assert.are.equal('!       ', renderer.format_flags({ flags = { 'Seen', 'Flagged' } }))
    end)

    it('puts * in slot 2 for unseen', function()
      assert.are.equal('  *     ', renderer.format_flags({ flags = {} }))
    end)

    it('puts R in slot 3 for answered', function()
      assert.are.equal('    R   ', renderer.format_flags({ flags = { 'Seen', 'Answered' } }))
    end)

    it('puts @ in slot 4 for attachment', function()
      assert.are.equal('      @ ', renderer.format_flags({ flags = { 'Seen' }, has_attachment = true }))
    end)

    it('returns all spaces for seen envelope', function()
      assert.are.equal('        ', renderer.format_flags({ flags = { 'Seen' } }))
    end)

    it('fills all slots when all flags present', function()
      assert.are.equal(
        '! * R @ ',
        renderer.format_flags({
          flags = { 'Answered', 'Flagged' },
          has_attachment = true,
        })
      )
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

  describe('format_from_initials', function()
    it('extracts initials from multi-word name', function()
      assert.are.equal('AS', renderer.format_from_initials({ name = 'Alice Smith' }))
    end)

    it('extracts single initial from single name', function()
      assert.are.equal('A', renderer.format_from_initials({ name = 'Alice' }))
    end)

    it('handles hyphenated names', function()
      assert.are.equal('JP', renderer.format_from_initials({ name = 'Jean-Luc Picard' }))
    end)

    it('caps at 2 characters for 3+ word names', function()
      assert.are.equal('AB', renderer.format_from_initials({ name = 'Alice Bob Carol' }))
    end)

    it('falls back to first char of addr', function()
      assert.are.equal('a', renderer.format_from_initials({ addr = 'alice@foo.com' }))
    end)

    it('returns empty for nil', function()
      assert.are.equal('', renderer.format_from_initials(nil))
    end)

    it('returns empty for empty table', function()
      assert.are.equal('', renderer.format_from_initials({}))
    end)

    it('falls back to addr when name is empty', function()
      assert.are.equal('b', renderer.format_from_initials({ name = '', addr = 'bob@test.com' }))
    end)

    it('falls back to addr when name is vim.NIL', function()
      assert.are.equal('c', renderer.format_from_initials({ name = vim.NIL, addr = 'charlie@test.com' }))
    end)

    it('uppercases initials', function()
      assert.are.equal('AB', renderer.format_from_initials({ name = 'alice bob' }))
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
      assert.are.equal('hello~', result)
    end)

    it('truncates ASCII to exact content', function()
      assert.are.equal('abcde~', renderer.fit('abcdefghij', 6))
      assert.are.equal('a~', renderer.fit('abcdefghij', 2))
      assert.are.equal('~', renderer.fit('abcdefghij', 1))
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
    it('produces header + separator + data lines', function()
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
      local result = renderer.render(envelopes, 80)
      assert.are.equal(1, #result.lines)
      -- Header contains column names
      assert.is_truthy(result.header:find('ID'))
      assert.is_truthy(result.header:find('FLGS'))
      assert.is_truthy(result.header:find('SUBJECT'))
      assert.is_truthy(result.header:find('FROM'))
      assert.is_truthy(result.header:find('DATE'))
      -- Separator line contains box-drawing chars
      assert.is_truthy(result.separator:find('\xe2\x94\x80')) -- ─
      assert.is_truthy(result.separator:find('\xe2\x94\xbc')) -- ┼
      -- Data line contains the envelope data
      assert.is_truthy(result.lines[1]:find('1'))
      assert.is_truthy(result.lines[1]:find('Alice'))
    end)

    it('uses box-drawing separators', function()
      local envelopes = {
        {
          id = '42',
          flags = { 'Seen' },
          subject = 'Hello',
          from = { name = 'Bob', addr = 'bob@test.com' },
          date = '2024-02-01 14:00:00',
        },
      }
      local result = renderer.render(envelopes, 80)
      -- Header and data lines use │ separators, no left/right borders
      assert.is_truthy(result.header:find('\xe2\x94\x82')) -- │
      assert.is_truthy(result.header:match('^ ')) -- starts with space, not border
      assert.is_truthy(result.lines[1]:find('\xe2\x94\x82'))
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
      local result = renderer.render(envelopes, 80)
      assert.is_truthy(result.lines[1]:find('Carol'))
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
      local result = renderer.render(envelopes, 80)
      assert.is_truthy(result.lines[1]:find('%*'))
    end)
  end)

  describe('custom flags', function()
    before_each(function()
      config.setup({
        flags = {
          header = '\xef\x80\xa4',
          flagged = '\xf3\xb0\x88\xbf',
          unseen = '\xef\x93\xb5',
          answered = '\xef\x84\x92',
          attachment = '\xef\x83\x86',
        },
      })
    end)

    it('puts custom flagged icon in slot 1', function()
      local result = renderer.format_flags({ flags = { 'Seen', 'Flagged' } })
      assert.is_truthy(result:find('\xf3\xb0\x88\xbf'))
    end)

    it('puts custom unseen icon in slot 2', function()
      local result = renderer.format_flags({ flags = {} })
      assert.is_truthy(result:find('\xef\x93\xb5'))
    end)

    it('puts custom answered icon in slot 3', function()
      local result = renderer.format_flags({ flags = { 'Seen', 'Answered' } })
      assert.is_truthy(result:find('\xef\x84\x92'))
    end)

    it('puts custom attachment icon in slot 4', function()
      local result = renderer.format_flags({ flags = { 'Seen' }, has_attachment = true })
      assert.is_truthy(result:find('\xef\x83\x86'))
    end)

    it('uses custom header in render', function()
      local result = renderer.render({}, 80)
      assert.are.equal(0, #result.lines)
      assert.is_truthy(result.header:find('\xef\x80\xa4'))
    end)
  end)

  describe('compute_layout narrow mode', function()
    it('sets narrow=true and from_w=4 at narrow width', function()
      local envelopes = {
        { id = '1', flags = {}, subject = 'Test', from = { name = 'Alice' }, date = '2024-01-15 09:30:00' },
      }
      -- Width 40 should force from_w < 12
      local layout = renderer.compute_layout(envelopes, 40, function(item)
        return item
      end)
      assert.is_true(layout.narrow)
      assert.are.equal(2, layout.from_w)
    end)

    it('sets narrow=false at normal width', function()
      local envelopes = {
        { id = '1', flags = {}, subject = 'Test', from = { name = 'Alice' }, date = '2024-01-15 09:30:00' },
      }
      local layout = renderer.compute_layout(envelopes, 80, function(item)
        return item
      end)
      assert.is_false(layout.narrow)
    end)

    it('uses FR header label when narrow', function()
      local envelopes = {
        { id = '1', flags = {}, subject = 'Test', from = { name = 'Alice' }, date = '2024-01-15 09:30:00' },
      }
      local layout = renderer.compute_layout(envelopes, 40, function(item)
        return item
      end)
      assert.is_truthy(layout.header:find('FR'))
      assert.is_falsy(layout.header:find('FROM'))
    end)
  end)

  describe('render narrow mode', function()
    it('uses initials at narrow width', function()
      local envelopes = {
        {
          id = '1',
          flags = { 'Seen' },
          subject = 'Test subject',
          from = { name = 'Alice Smith', addr = 'alice@example.com' },
          date = '2024-01-15 09:30:00',
        },
      }
      local result = renderer.render(envelopes, 40)
      assert.is_truthy(result.lines[1]:find('AS'))
      assert.is_falsy(result.lines[1]:find('Alice Smith'))
    end)
  end)

  describe('hidden flag', function()
    it('omits unseen slot when set to false', function()
      config.setup({ flags = { unseen = false } })
      local result = renderer.format_flags({ flags = {} })
      -- 3 remaining slots × 2 chars = 6
      assert.are.equal(6, #result)
      -- unseen marker should not appear
      assert.is_falsy(result:find('%*'))
    end)
  end)
end)
