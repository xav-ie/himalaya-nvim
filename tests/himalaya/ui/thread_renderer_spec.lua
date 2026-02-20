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
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
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
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
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
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        },
        {
          env = { id = '2', subject = 'Reply', from = { name = 'Bob' }, date = '2024-01-02 10:00:00+00:00' },
          depth = 1, is_last_child = true, prefix = '\xe2\x94\x94\xe2\x94\x80', thread_idx = 1,
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
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      assert.is_truthy(result.header:find('\xe2\x94\x82'))  -- │
      assert.is_truthy(result.separator:find('\xe2\x94\x80'))  -- ─
      assert.is_truthy(result.separator:find('\xe2\x94\xbc'))  -- ┼
    end)

    it('handles empty input', function()
      local result = thread_renderer.render({}, 80)
      assert.are.equal(0, #result.lines)
      assert.is_truthy(result.header:find('ID'))
    end)

    it('handles from as table with name', function()
      local rows = {
        {
          env = { id = '5', subject = 'Multi', from = { name = 'Carol', addr = 'carol@test.com' }, date = '2024-03-01 10:00:00+00:00' },
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 80)
      assert.is_truthy(result.lines[1]:find('Carol'))
    end)

    it('works without gutters', function()
      config.setup({ gutters = false })
      local rows = {
        {
          env = { id = '1', subject = 'Test', from = { name = 'Alice' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        },
      }
      local result = thread_renderer.render(rows, 60)
      assert.are.equal(1, #result.lines)
      -- Without gutters, no leading space
      assert.is_falsy(result.header:match('^ '))
      -- Still uses │ separator
      assert.is_truthy(result.lines[1]:find('\xe2\x94\x82'))
    end)
  end)
end)
