describe('himalaya.domain.email.thread_listing', function()
  local thread_listing

  before_each(function()
    package.loaded['himalaya.domain.email.thread_listing'] = nil
    thread_listing = require('himalaya.domain.email.thread_listing')
  end)

  describe('render_page', function()
    it('restores cursor when restore_cursor option is provided', function()
      local rows = {}
      for i = 1, 10 do
        rows[i] = {
          env = { id = tostring(i), subject = 'S' .. i, from = { name = 'A' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      -- Create a buffer mimicking an already-rendered thread listing
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      -- Initial render (cursor goes to line 1)
      thread_listing.render_page(1)
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])

      -- Now render again with cursor restoration at line 5
      -- (simulates resize: re-render but keep cursor position)
      thread_listing.render_page(1, { restore_cursor = { 5, 0 } })
      local line_count = vim.api.nvim_buf_line_count(0)
      local expected = math.min(5, line_count)
      assert.are.equal(expected, vim.api.nvim_win_get_cursor(0)[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('goes to line 1 when no restore_cursor option', function()
      local rows = {}
      for i = 1, 5 do
        rows[i] = {
          env = { id = tostring(i), subject = 'S' .. i, from = { name = 'A' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      thread_listing.render_page(1)
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('resize', function()
    it('preserves cursor position on current page', function()
      local rows = {}
      for i = 1, 10 do
        rows[i] = {
          env = { id = tostring(i), subject = 'S' .. i, from = { name = 'A' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      -- Initial render
      thread_listing.render_page(1)

      -- Move cursor to line 5
      local line_count = vim.api.nvim_buf_line_count(0)
      if line_count >= 5 then
        vim.api.nvim_win_set_cursor(0, {5, 0})
        assert.are.equal(5, vim.api.nvim_win_get_cursor(0)[1])

        -- Resize should preserve cursor at line 5
        thread_listing.resize()
        assert.are.equal(5, vim.api.nvim_win_get_cursor(0)[1])
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('is a no-op when no display rows are loaded', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {'a','b','c'})
      vim.api.nvim_win_set_cursor(0, {2, 0})

      thread_listing.resize()

      assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
