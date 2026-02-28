describe('himalaya.ui.thread_renderer', function()
  local thread_renderer
  local config

  before_each(function()
    package.loaded['himalaya.ui.thread_renderer'] = nil
    package.loaded['himalaya.ui.renderer'] = nil
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
    thread_renderer = require('himalaya.ui.thread_renderer')
  end)

  describe('render', function()
    it('produces header with 5 columns including FLGS', function()
      local result = thread_renderer.render({}, 80)
      assert.are.equal(0, #result.lines)
      assert.is_truthy(result.header:find('ID'))
      assert.is_truthy(result.header:find('FLGS'))
      assert.is_truthy(result.header:find('SUBJECT'))
      assert.is_truthy(result.header:find('FROM'))
      assert.is_truthy(result.header:find('DATE'))
    end)

    it('renders data lines with envelope data', function()
      local rows = {
        {
          env = { id = '42', subject = 'Test Subject', from = { name = 'Alice' }, date = '2024-01-15 09:30:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      assert.are.equal(1, #result.lines)
      assert.is_truthy(result.lines[1]:find('42'))
      assert.is_truthy(result.lines[1]:find('Test Subject'))
      assert.is_truthy(result.lines[1]:find('Alice'))
    end)

    it('renders empty flags column for thread envelopes', function()
      local rows = {
        {
          env = { id = '1', subject = 'Test', from = { name = 'Alice' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      -- Count box-drawing separators (│) in a data line — should be 4 for 5 columns
      local sep_count = 0
      for _ in result.lines[1]:gmatch('\xe2\x94\x82') do
        sep_count = sep_count + 1
      end
      assert.are.equal(4, sep_count)
    end)

    it('includes tree prefix in subject column', function()
      local rows = {
        {
          env = { id = '1', subject = 'Root', from = { name = 'Alice' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
        {
          env = { id = '2', subject = 'Reply', from = { name = 'Bob' }, date = '2024-01-02 10:00:00+00:00' },
          depth = 1,
          is_last_child = true,
          prefix = '\xe2\x94\x94\xe2\x94\x80',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      assert.are.equal(2, #result.lines)
      -- Second line should contain the └─ prefix followed by subject text
      assert.is_truthy(result.lines[2]:find('\xe2\x94\x94'))
      assert.is_truthy(result.lines[2]:find('Reply'))
    end)

    it('uses box-drawing separators', function()
      local rows = {
        {
          env = { id = '1', subject = 'Test', from = { name = 'Alice' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      assert.is_truthy(result.header:find('\xe2\x94\x82')) -- │
      assert.is_truthy(result.separator:find('\xe2\x94\x80')) -- ─
      assert.is_truthy(result.separator:find('\xe2\x94\xbc')) -- ┼
    end)

    it('handles empty input', function()
      local result = thread_renderer.render({}, 80)
      assert.are.equal(0, #result.lines)
      assert.is_truthy(result.header:find('ID'))
    end)

    it('handles from as table with name', function()
      local rows = {
        {
          env = {
            id = '5',
            subject = 'Multi',
            from = { name = 'Carol', addr = 'carol@test.com' },
            date = '2024-03-01 10:00:00+00:00',
          },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      assert.is_truthy(result.lines[1]:find('Carol'))
    end)

    it('renders actual flags when envelope has enriched flag data', function()
      local rows = {
        {
          env = {
            id = '1',
            subject = 'Unseen',
            from = { name = 'Alice' },
            date = '2024-01-01 10:00:00+00:00',
            flags = {},
            has_attachment = false,
          },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
        {
          env = {
            id = '2',
            subject = 'Seen',
            from = { name = 'Bob' },
            date = '2024-01-02 10:00:00+00:00',
            flags = { 'Seen', 'Answered' },
            has_attachment = true,
          },
          depth = 1,
          is_last_child = true,
          prefix = '\xe2\x94\x94\xe2\x94\x80',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 100)
      -- Unseen email (no Seen flag): unseen symbol '*' should appear
      assert.is_truthy(result.lines[1]:find('*', 1, true))
      -- Seen+Answered email: answered symbol 'R' and attachment '@' should appear
      assert.is_truthy(result.lines[2]:find('R', 1, true))
      assert.is_truthy(result.lines[2]:find('@', 1, true))
      -- Seen email should NOT have unseen symbol '*'
      -- Extract flags column (between first and second │ separators)
      local flags_col = result.lines[2]:match('\xe2\x94\x82(.-)' .. '\xe2\x94\x82')
      assert.is_falsy(flags_col and flags_col:find('*', 1, true))
    end)

    it('renders empty flags when envelope lacks flag data', function()
      local rows = {
        {
          env = { id = '1', subject = 'NoFlags', from = { name = 'Alice' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      -- Extract flags column (between first and second │ separators)
      local flags_col = result.lines[1]:match('\xe2\x94\x82(.-)' .. '\xe2\x94\x82')
      -- Should be all spaces (no flag symbols)
      assert.is_truthy(flags_col and flags_col:match('^%s+$'))
    end)

    it('uses initials at narrow width', function()
      local rows = {
        {
          env = { id = '1', subject = 'Test', from = { name = 'Alice Smith' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 40)
      assert.is_truthy(result.lines[1]:find('AS'))
      assert.is_falsy(result.lines[1]:find('Alice Smith'))
    end)

    it('works without gutters', function()
      config.setup({ gutters = false })
      local rows = {
        {
          env = { id = '1', subject = 'Test', from = { name = 'Alice' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 60)
      assert.are.equal(1, #result.lines)
      -- Without gutters, no leading space
      assert.is_falsy(result.header:match('^ '))
      -- Still uses │ separator
      assert.is_truthy(result.lines[1]:find('\xe2\x94\x82'))
    end)

    describe('compact_flags', function()
      it('produces 3 seps when compacted', function()
        config.setup({ compact_flags = 'always' })
        local rows = {
          {
            env = {
              id = '1',
              subject = 'Test',
              from = { name = 'Alice' },
              date = '2024-01-01 10:00:00+00:00',
              flags = {},
              has_attachment = false,
            },
            depth = 0,
            is_last_child = true,
            prefix = '',
            thread_idx = 1,
          },
        }
        local result = thread_renderer.render(rows, 80)
        assert.is_true(result.flags_compacted)
        local sep_count = 0
        for _ in result.lines[1]:gmatch('\xe2\x94\x82') do
          sep_count = sep_count + 1
        end
        assert.are.equal(3, sep_count)
        -- Header should not have FLGS
        assert.is_falsy(result.header:find('FLGS'))
      end)

      it('prepends flags before tree prefix when compacted', function()
        config.setup({ compact_flags = 'always' })
        local rows = {
          {
            env = {
              id = '1',
              subject = 'Root',
              from = { name = 'Alice' },
              date = '2024-01-01 10:00:00+00:00',
              flags = { 'Seen' },
              has_attachment = false,
            },
            depth = 0,
            is_last_child = true,
            prefix = '',
            thread_idx = 1,
          },
          {
            env = {
              id = '2',
              subject = 'Reply',
              from = { name = 'Bob' },
              date = '2024-01-02 10:00:00+00:00',
              flags = {},
              has_attachment = false,
            },
            depth = 1,
            visual_depth = 1,
            is_last_child = true,
            prefix = '\xe2\x94\x94\xe2\x94\x80',
            thread_idx = 1,
          },
        }
        local result = thread_renderer.render(rows, 100)
        -- First line (seen root): subject should start with 'Root' (no flag padding)
        local root_col = result.lines[1]:match('\xe2\x94\x82(.-)' .. '\xe2\x94\x82')
        assert.is_truthy(root_col)
        assert.is_truthy(root_col:match('^%s?Root'))

        -- Second line (unseen reply) should have * after tree prefix └─, directly before subject
        local subject_col = result.lines[2]:match('\xe2\x94\x82(.-)' .. '\xe2\x94\x82')
        assert.is_truthy(subject_col)
        -- tree connector '└' should appear before unseen flag '*'
        local star_pos = subject_col:find('*', 1, true)
        local tree_pos = subject_col:find('\xe2\x94\x94')
        assert.is_truthy(star_pos)
        assert.is_truthy(tree_pos)
        assert.is_true(tree_pos < star_pos)
      end)

      it('returns flags_compacted=false by default', function()
        local rows = {
          {
            env = { id = '1', subject = 'Test', from = { name = 'Alice' }, date = '2024-01-01 10:00:00+00:00' },
            depth = 0,
            is_last_child = true,
            prefix = '',
            thread_idx = 1,
          },
        }
        local result = thread_renderer.render(rows, 80)
        assert.is_false(result.flags_compacted)
      end)
    end)
  end)
end)
