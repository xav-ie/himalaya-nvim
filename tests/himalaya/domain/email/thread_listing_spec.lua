describe('himalaya.domain.email.thread_listing', function()
  local thread_listing

  before_each(function()
    package.loaded['himalaya.domain.email.thread_listing'] = nil
    thread_listing = require('himalaya.domain.email.thread_listing')
  end)

  describe('resize', function()
    it('preserves cursor position on current page', function()
      -- Set up module state with some display rows
      local rows = {}
      for i = 1, 10 do
        rows[i] = {
          env = { id = tostring(i), subject = 'S' .. i, from = { name = 'A' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0, is_last_child = true, prefix = '', thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      -- Create buffer with enough lines and set cursor to line 5
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {'a','b','c','d','e','f','g','h','i','j'})
      vim.api.nvim_win_set_cursor(0, {5, 0})

      -- Mock render_page to simulate cursor reset (like the real one does)
      local original_render = thread_listing.render_page
      thread_listing.render_page = function(page)
        vim.api.nvim_win_set_cursor(0, {1, 0})
      end

      -- Resize should preserve cursor
      thread_listing.resize()

      assert.are.equal(5, vim.api.nvim_win_get_cursor(0)[1])

      -- Cleanup
      thread_listing.render_page = original_render
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('is a no-op when no display rows are loaded', function()
      -- No state set — all_display_rows is nil
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
