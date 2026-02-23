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
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      -- Initial render (cursor goes to line 1)
      thread_listing.render_page(1)
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])

      -- Now render again with cursor restoration at line 5
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
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
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

  describe('cleanup', function()
    it('clears state so resize becomes a no-op', function()
      local rows = {}
      for i = 1, 5 do
        rows[i] = {
          env = { id = tostring(i), subject = 'S' .. i, from = { name = 'A' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      -- Render once so buffer has content
      thread_listing.render_page(1)
      -- Cleanup then overwrite buffer with sentinel
      thread_listing.cleanup()
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'unchanged' })
      vim.bo[bufnr].modifiable = false

      -- resize should be a no-op since all_display_rows is nil
      thread_listing.resize()
      assert.are.equal('unchanged', vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('resize', function()
    it('follows selected email across page boundary on shrink', function()
      local rows = {}
      for i = 1, 30 do
        rows[i] = {
          env = {
            id = tostring(i),
            subject = 'Subject' .. i,
            from = { name = 'A' },
            date = '2024-01-01 10:00:00+00:00',
          },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      -- Render page 1 at current window height
      thread_listing.render_page(1)
      local initial_line_count = vim.api.nvim_buf_line_count(0)

      -- Select the last visible email and record its ID
      vim.api.nvim_win_set_cursor(0, { initial_line_count, 0 })
      local target_id = vim.api.nvim_get_current_line():match('%d+')

      -- Shrink window to 5 rows — the selected email should move to a later page
      vim.api.nvim_win_set_height(0, 5)
      thread_listing.resize()

      -- Verify cursor is still on the same email
      local after_id = vim.api.nvim_get_current_line():match('%d+')
      assert.are.equal(target_id, after_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('follows selected email when window grows', function()
      local rows = {}
      for i = 1, 30 do
        rows[i] = {
          env = {
            id = tostring(i),
            subject = 'Subject' .. i,
            from = { name = 'A' },
            date = '2024-01-01 10:00:00+00:00',
          },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      -- Start with small window, render page 1
      vim.api.nvim_win_set_height(0, 5)
      thread_listing.render_page(1)

      -- Move cursor to line 3 and record the email ID
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      local target_id = vim.api.nvim_get_current_line():match('%d+')

      -- Grow window — same page, email should stay
      vim.api.nvim_win_set_height(0, 20)
      thread_listing.resize()

      local after_id = vim.api.nvim_get_current_line():match('%d+')
      assert.are.equal(target_id, after_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('follows email from page 2 across resize', function()
      local rows = {}
      for i = 1, 30 do
        rows[i] = {
          env = {
            id = tostring(i),
            subject = 'Subject' .. i,
            from = { name = 'A' },
            date = '2024-01-01 10:00:00+00:00',
          },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      -- Set small window, navigate to page 2
      vim.api.nvim_win_set_height(0, 5)
      thread_listing.render_page(1)
      thread_listing.render_page(2)

      -- Select first email on page 2
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local target_id = vim.api.nvim_get_current_line():match('%d+')

      -- Grow window so page 2's emails would now be on page 1
      vim.api.nvim_win_set_height(0, 20)
      thread_listing.resize()

      -- Email should still be under cursor
      local after_id = vim.api.nvim_get_current_line():match('%d+')
      assert.are.equal(target_id, after_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('preserves cursor on width-only change', function()
      local rows = {}
      for i = 1, 10 do
        rows[i] = {
          env = { id = tostring(i), subject = 'S' .. i, from = { name = 'A' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.b.himalaya_buffer_type = 'thread-listing'
      vim.bo.buftype = 'nofile'

      thread_listing.render_page(1)

      local line_count = vim.api.nvim_buf_line_count(0)
      if line_count >= 5 then
        vim.api.nvim_win_set_cursor(0, { 5, 0 })
        local target_id = vim.api.nvim_get_current_line():match('%d+')

        -- Resize (same height, just re-render)
        thread_listing.resize()

        local after_id = vim.api.nvim_get_current_line():match('%d+')
        assert.are.equal(target_id, after_id)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('toggle_to_flat clears state and deregisters resize autocmds', function()
      local rows = {}
      for i = 1, 5 do
        rows[i] = {
          env = { id = tostring(i), subject = 'S' .. i, from = { name = 'A' }, date = '2024-01-01 10:00:00+00:00' },
          depth = 0,
          is_last_child = true,
          prefix = '',
          thread_idx = 1,
        }
      end
      thread_listing._set_state(rows, 1)

      -- Register autocmds like the UI setup does
      local augroup = vim.api.nvim_create_augroup('HimalayaThreadListing', { clear = true })
      vim.api.nvim_create_autocmd('VimResized', { group = augroup, callback = function() end })
      local before = vim.api.nvim_get_autocmds({ group = 'HimalayaThreadListing' })
      assert.is_true(#before > 0)

      -- Stub email.list to avoid async request
      local email_mod = require('himalaya.domain.email')
      local orig_list = email_mod.list
      email_mod.list = function() end

      thread_listing.toggle_to_flat()

      -- Augroup should be cleared
      local after = vim.api.nvim_get_autocmds({ group = 'HimalayaThreadListing' })
      assert.are.equal(0, #after)

      -- resize should be a no-op (all_display_rows cleared)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'unchanged' })
      thread_listing.resize()
      assert.are.equal('unchanged', vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1])

      email_mod.list = orig_list
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('is a no-op when no display rows are loaded', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a', 'b', 'c' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      thread_listing.resize()

      assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
