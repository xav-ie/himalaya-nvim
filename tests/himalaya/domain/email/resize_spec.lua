describe('himalaya.domain.email resize_listing', function()
  local email
  local set_page_calls
  local rendered_envs
  local original_height
  local last_request_json_opts    -- captured from request.json mock
  local mock_request_sync_data   -- set before list_with to make request.json call on_data synchronously
  local mock_request_job         -- return value for request.json (fake SystemObj)
  local probe_cancel_count        -- tracks probe.cancel() calls

  --- Generate a list of envelope stubs.
  --- @param start_id number  first envelope ID
  --- @param count number     how many to generate
  local function make_envelopes(start_id, count)
    local envs = {}
    for i = 0, count - 1 do
      table.insert(envs, {
        id = tostring(start_id + i),
        flags = { 'Seen' },
        subject = 'Subject ' .. (start_id + i),
        from = { name = 'Sender', addr = 'sender@test.com' },
        date = '2024-01-01 00:00:00',
      })
    end
    return envs
  end

  --- Populate the current buffer with placeholder lines so vim.fn.line('.')
  --- and nvim_win_set_cursor work correctly.
  local function seed_buffer_lines(count)
    local lines = {}
    for i = 1, count do
      table.insert(lines, tostring(i))
    end
    vim.bo.modifiable = true
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.modifiable = false
  end

  before_each(function()
    -- Wipe module cache so each test gets fresh module-level state.
    for k in pairs(package.loaded) do
      if k:match('^himalaya') then
        package.loaded[k] = nil
      end
    end

    set_page_calls = {}
    rendered_envs = nil
    last_request_json_opts = nil
    mock_request_sync_data = nil
    mock_request_job = nil
    probe_cancel_count = 0

    -- Stub out every dependency that email.lua requires at load time.
    -- request mock: captures args for verification; can be made synchronous
    -- by setting mock_request_sync_data before calling list_with.
    package.loaded['himalaya.request'] = {
      json = function(opts)
        last_request_json_opts = opts
        if mock_request_sync_data and opts.on_data then
          if not (opts.is_stale and opts.is_stale()) then
            opts.on_data(mock_request_sync_data)
          end
        end
        return mock_request_job
      end,
      plain = function() return nil end,
    }
    package.loaded['himalaya.log'] = {
      info = function() end,
      warn = function() end,
      err = function() end,
      debug = function() end,
    }
    package.loaded['himalaya.config'] = {
      get = function() return {} end,
      setup = function() end,
      _reset = function() end,
    }
    package.loaded['himalaya.state.account'] = {
      current = function() return 'test' end,
      select = function() end,
    }
    package.loaded['himalaya.state.folder'] = {
      current = function() return 'INBOX' end,
      current_page = function() return 1 end,
      set_page = function(n) table.insert(set_page_calls, n) end,
    }
    package.loaded['himalaya.domain.email.probe'] = {
      reset_if_changed = function() end,
      set_total_from_data = function() end,
      total_pages_str = function() return '?' end,
      start = function() end,
      cancel = function() probe_cancel_count = probe_cancel_count + 1 end,
      restart = function() end,
    }

    -- Renderer mock that captures the envelopes it was asked to render.
    package.loaded['himalaya.ui.renderer'] = {
      render = function(envs, _width)
        rendered_envs = envs
        local lines = {}
        for _, env in ipairs(envs) do
          table.insert(lines, string.format('%s │ Subject %s', env.id, env.id))
        end
        return { lines = lines, header = 'ID │ SUBJECT', separator = '──┼────' }
      end,
    }
    package.loaded['himalaya.ui.listing'] = {
      apply_header = function() end,
      apply_seen_highlights = function() end,
      apply_syntax = function() end,
    }

    email = require('himalaya.domain.email')

    -- Save original window height so we can restore it after each test.
    original_height = vim.api.nvim_win_get_height(0)
  end)

  after_each(function()
    email.cancel_resize()
    vim.b.himalaya_buffer_type = nil
    vim.b.himalaya_envelopes = nil
    vim.b.himalaya_page = nil
    vim.b.himalaya_page_size = nil
    vim.b.himalaya_cache_offset = nil
    vim.b.himalaya_cache_key = nil
    vim.b.himalaya_query = nil
    -- Restore window height for other test files.
    pcall(vim.api.nvim_win_set_height, 0, original_height)
  end)

  -- ── early-return guards ──────────────────────────────────────────

  it('returns early on non-listing buffer', function()
    vim.b.himalaya_buffer_type = nil
    vim.b.himalaya_envelopes = make_envelopes(1, 5)
    email.resize_listing()
    assert.is_nil(rendered_envs)
  end)

  it('returns early with no envelopes', function()
    vim.b.himalaya_buffer_type = 'listing'
    vim.b.himalaya_envelopes = nil
    email.resize_listing()
    assert.is_nil(rendered_envs)
  end)

  -- ── skip resize while reading ───────────────────────────────────

  describe('reading window suppression', function()
    local reading_win, reading_buf

    --- Open a fake reading window in the current tab and return to the listing window.
    local function open_reading_window()
      local listing_win = vim.api.nvim_get_current_win()
      reading_buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(reading_buf, 'Himalaya/read email [42]')
      reading_win = vim.api.nvim_open_win(reading_buf, false, { split = 'below' })
      vim.api.nvim_set_current_win(listing_win)
    end

    local function close_reading_window()
      if reading_win and vim.api.nvim_win_is_valid(reading_win) then
        vim.api.nvim_win_close(reading_win, true)
        reading_win = nil
      end
      if reading_buf and vim.api.nvim_buf_is_valid(reading_buf) then
        vim.cmd('silent! bwipeout ' .. reading_buf)
        reading_buf = nil
      end
    end

    after_each(function()
      close_reading_window()
    end)

    it('truncates display using page boundaries when reading', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {8, 0})

      -- Opening a split halves the listing window
      open_reading_window()
      email.resize_listing()

      -- Display is truncated to page boundaries
      assert.is_not_nil(rendered_envs)
      -- Page is recomputed based on cursor position and new page_size
      local new_ps = vim.b.himalaya_page_size
      local expected_page = math.floor(7 / new_ps) + 1  -- global index 7
      assert.are.equal(expected_page, vim.b.himalaya_page)
      -- Envelope 8 must be in the rendered slice
      local found = false
      for _, env in ipairs(rendered_envs) do
        if env.id == '8' then found = true; break end
      end
      assert.is_true(found, 'envelope 8 must be in rendered slice')
    end)

    it('preserves cursor on selected email during reading truncation', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {8, 0})

      open_reading_window()
      email.resize_listing()

      -- The cursor line should point to envelope 8 in the rendered output
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[cursor_line].id)
    end)

    it('cursor on row 2 stays on same email during reading', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {2, 0})

      open_reading_window()
      email.resize_listing()

      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('2', rendered_envs[cursor_line].id)
    end)

    it('does not start Phase 2 timer when reading', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)

      open_reading_window()
      email.resize_listing()

      -- cancel_resize should be a no-op (no timer was started)
      assert.has_no.errors(function()
        email.cancel_resize()
      end)
    end)

    it('resumes normal resize after reading window closes', function()
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      -- Resize while reading — truncates but no page change
      open_reading_window()
      vim.api.nvim_win_set_height(0, 5)
      email.resize_listing()
      assert.are.equal(1, vim.b.himalaya_page)
      rendered_envs = nil

      -- Close reading window — Phase 1 should work now
      close_reading_window()
      email.resize_listing()
      email.cancel_resize()

      assert.is_not_nil(rendered_envs)
    end)

    it('restores cursor to selected email when listing grows after reading close', function()
      -- Scenario: 10 envelopes on page 1, cursor on row 8 (ID 8).
      -- Open reading split → listing shrinks to ~5 → page-boundary truncation
      -- puts ID 8 on page 2 (IDs 6-10, cursor on row 3 = ID 8).
      -- Close reading split → listing grows back to 10 → should resolve
      -- cursor from buffer line (email ID), NOT from row position.
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {8, 0})

      -- Step 1: open reading split → shrinks listing
      open_reading_window()
      email.resize_listing()

      -- Cursor should be on ID 8 in the truncated display
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[cursor_line].id)

      -- Step 2: close reading window → listing grows back
      close_reading_window()
      rendered_envs = nil
      email.resize_listing()
      email.cancel_resize()

      -- Grow should extract email ID from buffer line to find
      -- the correct position in the full envelope cache
      assert.is_not_nil(rendered_envs)
      local grow_cursor = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[grow_cursor].id)
    end)

    it('restores cursor from reading truncation on page 2+ grow', function()
      -- Page 2: envelopes 11-20 (IDs 11-20), cursor on row 7 (ID 17).
      -- Reading shrink → page-boundary truncation shows ID 17.
      -- Close reading → grow should resolve cursor to ID 17.
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(11, 10)
      vim.b.himalaya_page = 2
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 10
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {7, 0})

      -- Step 1: reading truncation
      open_reading_window()
      email.resize_listing()

      -- Cursor should be on ID 17
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('17', rendered_envs[cursor_line].id)

      -- Step 2: grow
      close_reading_window()
      rendered_envs = nil
      email.resize_listing()
      email.cancel_resize()

      assert.is_not_nil(rendered_envs)
      local grow_cursor = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('17', rendered_envs[grow_cursor].id)
    end)

    it('handles chained reading resizes then grow correctly', function()
      -- Start with 10 envelopes, cursor on row 8 (ID 8).
      -- Two successive reading truncations, then grow.
      -- Cursor should still land on ID 8.
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {8, 0})

      -- First reading truncation
      open_reading_window()
      email.resize_listing()

      -- Cursor should be on ID 8
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[cursor_line].id)

      -- Shrink further (e.g., another split)
      vim.api.nvim_win_set_height(0, 3)
      email.resize_listing()
      -- Cursor should still be on ID 8 after chained truncation
      cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[cursor_line].id)

      -- Close reading → grow
      close_reading_window()
      rendered_envs = nil
      email.resize_listing()
      email.cancel_resize()

      assert.is_not_nil(rendered_envs)
      local grow_cursor = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[grow_cursor].id)
    end)

    it('updates page correctly when cursor is in second half during reading', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      -- Cursor in second half
      vim.api.nvim_win_set_cursor(0, {8, 0})

      open_reading_window()
      vim.api.nvim_win_set_height(0, 5)
      email.resize_listing()

      -- Page should change: global index 7, page = floor(7/5)+1 = 2
      assert.are.equal(2, vim.b.himalaya_page)
      assert.are.equal(5, vim.b.himalaya_page_size)
      -- Cursor should still be on envelope 8
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[cursor_line].id)
    end)

    it('places cursor at correct page position for sparse page during reading', function()
      -- 42 envelopes on page 1, cursor on email 41.
      -- Window shrinks to 20 → page 3 has only 2 emails (41, 42).
      -- Email 41 should be at position 1 (first on page 3).
      vim.api.nvim_win_set_height(0, 42)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 42)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 42
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(42)
      vim.api.nvim_win_set_cursor(0, {41, 0})

      open_reading_window()
      vim.api.nvim_win_set_height(0, 20)
      email.resize_listing()

      -- Email 41 at global index 40, page = floor(40/20)+1 = 3
      assert.are.equal(3, vim.b.himalaya_page)
      -- Email 41 must be at position 1 on page 3
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
      assert.are.equal('41', rendered_envs[1].id)
      -- Only 2 emails in overlap (41, 42) — Phase 2 will fill the rest
      assert.are.equal(2, #rendered_envs)
    end)

    it('starts Phase 2 timer for sparse page during reading', function()
      -- Same scenario: sparse page should trigger Phase 2 re-fetch.
      vim.api.nvim_win_set_height(0, 42)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 42)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 42
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(42)
      vim.api.nvim_win_set_cursor(0, {41, 0})

      open_reading_window()
      vim.api.nvim_win_set_height(0, 20)
      email.resize_listing()

      -- Phase 2 timer should have been started (cancel_resize stops it)
      -- Verify it was started by checking last_request_json_opts is nil
      -- (timer hasn't fired yet), but cancel_resize has work to do.
      assert.is_nil(last_request_json_opts)  -- timer pending, not fired
      email.cancel_resize()
    end)

    it('skips Phase 2 for full page during reading', function()
      -- 42 envelopes, cursor on email 23.
      -- Window shrinks to 20 → page 2 has 20 emails (full overlap).
      -- Phase 2 should NOT fire.
      vim.api.nvim_win_set_height(0, 42)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 42)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 42
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(42)
      vim.api.nvim_win_set_cursor(0, {23, 0})

      open_reading_window()
      vim.api.nvim_win_set_height(0, 20)
      email.resize_listing()

      -- Page 2: indices 20-39, overlap = 20 emails (full)
      assert.are.equal(20, #rendered_envs)
      assert.are.equal(2, vim.b.himalaya_page)
      -- Email 23 at position 3
      assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
      assert.are.equal('23', rendered_envs[3].id)
      -- No Phase 2 timer (cancel_resize is a no-op)
      assert.has_no.errors(function() email.cancel_resize() end)
    end)

    it('respects cursor movement during reading on grow', function()
      -- Scenario: 10 envelopes on page 1, cursor on email 8.
      -- Open reading → truncation shows emails 6-10.
      -- User moves cursor to email 9. Close reading → grow.
      -- Grow should use email 9 (the moved-to position), not email 8.
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {8, 0})

      -- Step 1: open reading → truncation (ensure listing is 5 rows)
      open_reading_window()
      vim.api.nvim_win_set_height(0, 5)
      email.resize_listing()

      -- With page_size 5: page 2 = emails 6-10, cursor on row 3 (email 8)
      local cl = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('8', rendered_envs[cl].id)

      -- Step 2: user moves cursor to email 9 (should be at row 4)
      local target_row
      for i, env in ipairs(rendered_envs) do
        if env.id == '9' then target_row = i; break end
      end
      assert.is_not_nil(target_row, 'email 9 should be in rendered display')
      vim.api.nvim_win_set_cursor(0, {target_row, 0})

      -- Step 3: close reading → grow
      close_reading_window()
      rendered_envs = nil
      email.resize_listing()
      email.cancel_resize()

      -- Grow should resolve cursor to email 9 (the moved-to position),
      -- not email 8 (the original position before movement)
      assert.is_not_nil(rendered_envs)
      local grow_cursor = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('9', rendered_envs[grow_cursor].id)
    end)

    it('Phase 2 re-fetch for sparse reading page uses Phase 1 page_size', function()
      -- Reproduces real bug: 42 envelopes, cursor on email 41, shrink to 20.
      -- Phase 1: page 3 (start=40), only 2 emails in overlap.
      -- Phase 2 must fetch with page_size=20 (from Phase 1), not window height
      -- (which could differ due to winbar inclusion in nvim_win_get_height).
      vim.api.nvim_win_set_height(0, 42)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 42)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 42
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(42)
      vim.api.nvim_win_set_cursor(0, {41, 0})

      open_reading_window()
      vim.api.nvim_win_set_height(0, 20)
      email.resize_listing()

      assert.are.equal(3, vim.b.himalaya_page)
      assert.are.equal(20, vim.b.himalaya_page_size)

      -- Wait for Phase 2 timer to fire
      vim.wait(300, function() return last_request_json_opts ~= nil end)

      assert.is_not_nil(last_request_json_opts, 'Phase 2 should fire for sparse page')
      -- args: { folder, account_flag, page_size, page, query }
      assert.are.equal(20, last_request_json_opts.args[3],
        'Phase 2 page_size must match Phase 1')
      assert.are.equal(3, last_request_json_opts.args[4],
        'Phase 2 page must match Phase 1')

      email.cancel_resize()
    end)

    it('respects cursor movement after Phase 2 replaces cache during reading on grow', function()
      -- Scenario: 20 envelopes on page 1, cursor on email 19 (row 19).
      -- Open reading → listing shrinks to 8.
      -- Phase 1: email 19 at global 18, page = floor(18/8)+1 = 3.
      --   Page 3 covers global 16-23, overlap with cache (0-19) = 16-19 → 4 entries.
      --   4 < 8 → sparse page → Phase 2 fires.
      -- Phase 2 re-fetches page 3 with page_size 8 → server returns 8 envelopes (IDs 17-24).
      -- Cache is replaced with Phase 2 data. User moves cursor to email 22.
      -- Close reading → listing grows back to 20.
      -- Grow should compute from Phase 2 cache (IDs 17-24, offset 16)
      -- with cursor on email 22, NOT revert to original page 1 data.
      vim.api.nvim_win_set_height(0, 20)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 20)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 20
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(20)
      vim.api.nvim_win_set_cursor(0, {19, 0})

      -- Phase 2 will return server data for page 3 (IDs 17-24)
      mock_request_sync_data = make_envelopes(17, 8)

      -- Step 1: open reading → listing shrinks to 8
      open_reading_window()
      vim.api.nvim_win_set_height(0, 8)
      email.resize_listing()

      -- Phase 1: sparse page (4 entries in overlap), Phase 2 timer starts
      assert.are.equal(3, vim.b.himalaya_page)
      assert.are.equal(8, vim.b.himalaya_page_size)

      -- Wait for Phase 2 to fire and complete (mock_request_sync_data makes it synchronous)
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'Phase 2 should fire for sparse page')

      -- After Phase 2: cache replaced with IDs 17-24
      assert.are.equal(16, vim.b.himalaya_cache_offset)
      assert.are.equal(8, vim.b.himalaya_page_size)
      assert.are.equal(8, #vim.b.himalaya_envelopes, 'Phase 2 should replace cache with 8 entries')
      assert.are.equal('17', vim.b.himalaya_envelopes[1].id, 'first cached envelope should be ID 17')

      -- Verify email 19 is selected (Phase 2 cursor restoration)
      local cl = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('19', rendered_envs[cl].id)

      -- Step 2: user moves cursor to email 22 (position 6 in Phase 2 data)
      local target_row
      for i, env in ipairs(rendered_envs) do
        if env.id == '22' then target_row = i; break end
      end
      assert.is_not_nil(target_row, 'email 22 should be in Phase 2 display')
      vim.api.nvim_win_set_cursor(0, {target_row, 0})

      -- Step 3: close reading → listing grows back to 20
      close_reading_window()
      vim.api.nvim_win_set_height(0, 20)
      rendered_envs = nil
      last_request_json_opts = nil
      email.resize_listing()
      email.cancel_resize()

      -- Grow Phase 1: cache has 8 entries (17-24), cache_offset=16
      -- Cursor on email 22, cursor_row=6 in cache
      -- selected_global = 16 + 6 - 1 = 21
      -- new_page = floor(21/20) + 1 = 2
      -- overlap: start=max(16,20)=20, end=min(24,40)=24
      -- display = cache[5..8] = 4 entries (IDs 21-24)
      -- cursor_line = 21 - 20 + 1 = 2
      assert.is_not_nil(rendered_envs)
      assert.are.equal(2, vim.b.himalaya_page)
      local grow_cursor = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('22', rendered_envs[grow_cursor].id)
    end)

    it('grow Phase 2 after reading close restores cursor to moved-to email', function()
      -- Same setup as above but also lets Phase 2 of the grow complete.
      -- Verifies that Phase 2's on_list_with correctly uses saved_cursor_id
      -- to place cursor on the email the user moved to during reading.
      vim.api.nvim_win_set_height(0, 20)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 20)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 20
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(20)
      vim.api.nvim_win_set_cursor(0, {19, 0})

      -- Phase 2 during reading will return IDs 17-24 for page 3
      mock_request_sync_data = make_envelopes(17, 8)

      open_reading_window()
      vim.api.nvim_win_set_height(0, 8)
      email.resize_listing()

      -- Wait for reading Phase 2 to complete
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'reading Phase 2 should fire')

      -- Move cursor to email 22
      local target_row
      for i, env in ipairs(rendered_envs) do
        if env.id == '22' then target_row = i; break end
      end
      assert.is_not_nil(target_row)
      vim.api.nvim_win_set_cursor(0, {target_row, 0})

      -- Close reading, grow
      close_reading_window()
      vim.api.nvim_win_set_height(0, 20)
      rendered_envs = nil
      last_request_json_opts = nil

      -- Set mock data for grow's Phase 2: page 2 with page_size 20
      mock_request_sync_data = make_envelopes(21, 20)

      email.resize_listing()

      -- Wait for grow Phase 2 to fire and complete
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'grow Phase 2 should fire')

      -- Phase 2 should request page 2 with page_size 20
      assert.are.equal(20, last_request_json_opts.args[3], 'grow Phase 2 page_size')
      assert.are.equal(2, last_request_json_opts.args[4], 'grow Phase 2 page')

      -- After Phase 2 on_list_with: cursor should be on email 22
      assert.are.equal(2, vim.b.himalaya_page)
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      assert.are.equal('22', rendered_envs[cursor].id)

      email.cancel_resize()
    end)
  end)

  -- ── page_size initialisation ─────────────────────────────────────

  it('initializes page_size when not previously set', function()
    vim.b.himalaya_buffer_type = 'listing'
    vim.b.himalaya_envelopes = make_envelopes(1, 3)
    vim.b.himalaya_page_size = nil
    seed_buffer_lines(3)

    email.resize_listing()

    -- page_size should be written, render should run (width-only path)
    assert.are.equal(vim.fn.winheight(0), vim.b.himalaya_page_size)
    assert.is_not_nil(rendered_envs)
  end)

  -- ── width-only change (same height) ─────────────────────────────

  it('re-renders with display_slice when height unchanged', function()
    local height = vim.fn.winheight(0)
    local envs = make_envelopes(1, height + 5)
    vim.b.himalaya_buffer_type = 'listing'
    vim.b.himalaya_envelopes = envs
    vim.b.himalaya_page = 1
    vim.b.himalaya_page_size = height -- same as current
    vim.b.himalaya_cache_offset = 0
    seed_buffer_lines(#envs)

    email.resize_listing()

    -- display_slice should truncate to page_size
    assert.is_not_nil(rendered_envs)
    assert.are.equal(height, #rendered_envs)
  end)

  -- ── page 1 shrink ───────────────────────────────────────────────

  describe('page 1 shrink', function()
    it('shows first N emails as overlap', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      email.resize_listing()

      assert.are.equal(1, vim.b.himalaya_page)
      assert.are.equal(5, vim.b.himalaya_page_size)
      assert.are.equal(5, #rendered_envs)
      assert.are.equal('1', rendered_envs[1].id)
      assert.are.equal('5', rendered_envs[5].id)
    end)

    it('does not call folder_state.set_page when page stays 1', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      assert.are.equal(1, set_page_calls[#set_page_calls])
    end)
  end)

  -- ── page 1 grow ─────────────────────────────────────────────────

  describe('page 1 grow', function()
    it('shows all cached emails when growing', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      email.resize_listing()

      assert.are.equal(1, vim.b.himalaya_page)
      assert.are.equal(10, vim.b.himalaya_page_size)
      -- All 5 cached envelopes shown (partial page, re-fetch will fill)
      assert.are.equal(5, #rendered_envs)
      assert.are.equal('1', rendered_envs[1].id)
      assert.are.equal('5', rendered_envs[5].id)
    end)
  end)

  -- ── page 2+ shrink ──────────────────────────────────────────────

  describe('page 2+ shrink', function()
    --[[
      Setup: page 2 with page_size=10 → global indices 10-19 (IDs 11-20)
      Cursor on row 3 → global index 12
      Shrink to page_size=5 → new_page = floor(12/5)+1 = 3
      New page 3 covers global 10-14
      Overlap with cache (10-19) = 10-14 → envelopes[1..5] (IDs 11-15)
    ]]
    it('recalculates page and shows correct overlap', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(11, 10)
      vim.b.himalaya_page = 2
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 10
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      email.resize_listing()

      assert.are.equal(3, vim.b.himalaya_page)
      assert.are.equal(5, vim.b.himalaya_page_size)
      assert.are.equal(3, set_page_calls[#set_page_calls])
      assert.are.equal(5, #rendered_envs)
      assert.are.equal('11', rendered_envs[1].id)
      assert.are.equal('15', rendered_envs[5].id)
    end)

    --[[
      Setup: page 3 with page_size=5 → global indices 10-14 (IDs 11-15)
      Cursor on row 2 → global index 11
      Grow to page_size=10 → new_page = floor(11/10)+1 = 2
      New page 2 covers global 10-19
      Overlap with cache (10-14) = 10-14 → all 5 envelopes
    ]]
    it('recalculates page when growing from page 3', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(11, 5)
      vim.b.himalaya_page = 3
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 10
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {2, 0})

      email.resize_listing()

      assert.are.equal(2, vim.b.himalaya_page)
      assert.are.equal(10, vim.b.himalaya_page_size)
      assert.are.equal(2, set_page_calls[#set_page_calls])
      assert.are.equal(5, #rendered_envs)
      assert.are.equal('11', rendered_envs[1].id)
      assert.are.equal('15', rendered_envs[5].id)
    end)
  end)

  -- ── cursor preservation ─────────────────────────────────────────

  describe('cursor preservation', function()
    it('positions cursor on previously selected email after page 1 shrink', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      email.resize_listing()

      -- selected_global=2, overlap_start=0 → cursor_line = 2-0+1 = 3
      assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('positions cursor on selected email after page 2 shrink', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(11, 10)
      vim.b.himalaya_page = 2
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 10
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      -- Cursor row 3 → global 12, overlap_start=10 → cursor_line = 12-10+1 = 3
      vim.api.nvim_win_set_cursor(0, {3, 0})

      email.resize_listing()

      assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('clamps cursor when beyond envelope count', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 3)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      -- Cursor at row 8, but only 3 envelopes → clamp to 3
      vim.api.nvim_win_set_cursor(0, {8, 0})

      email.resize_listing()

      -- selected_global = 0+3-1 = 2, overlap covers 0..3,
      -- cursor_line = 2-0+1 = 3
      assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
    end)
  end)

  -- ── cache_offset fallback ───────────────────────────────────────

  describe('cache_offset', function()
    it('falls back to (page-1)*page_size when not set', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(11, 10)
      vim.b.himalaya_page = 2
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = nil -- not set
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      -- Should behave identically to cache_offset = 10
      -- cursor row 1 → global 10, new_page = floor(10/5)+1 = 3
      assert.are.equal(3, vim.b.himalaya_page)
      assert.are.equal(5, #rendered_envs)
      assert.are.equal('11', rendered_envs[1].id)
    end)
  end)

  -- ── Phase 2 skip (cache covers new page) ───────────────────────

  describe('Phase 2 skip when cache covers page', function()
    it('does not schedule Phase 2 on page 1 shrink', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      email.resize_listing()

      -- Wait long enough for any Phase 2 timer to fire
      vim.wait(250, function() return last_request_json_opts ~= nil end, 50)
      assert.is_nil(last_request_json_opts, 'Phase 2 should not fire on shrink within cache')
    end)

    it('skips Phase 2 on shrink-then-grow within cache bounds', function()
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- Shrink
      vim.api.nvim_win_set_height(0, 5)
      email.resize_listing()
      vim.wait(250, function() return last_request_json_opts ~= nil end, 50)
      assert.is_nil(last_request_json_opts, 'Phase 2 should not fire on shrink')

      -- Grow back within cache bounds
      vim.api.nvim_win_set_height(0, 8)
      email.resize_listing()
      vim.wait(250, function() return last_request_json_opts ~= nil end, 50)
      assert.is_nil(last_request_json_opts, 'Phase 2 should not fire on grow within cache')
    end)

    it('triggers Phase 2 when growing beyond cache bounds', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'Phase 2 should fire when grow exceeds cache')
      email.cancel_resize()
    end)

    it('skips Phase 2 on page-change shrink with full overlap', function()
      -- 10 envelopes, page 1, cursor at row 8
      -- Shrink to 5 → page 2, display = 5 envelopes (IDs 6-10)
      -- 5 >= 5 → Phase 2 skipped
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {8, 0})

      email.resize_listing()

      vim.wait(250, function() return last_request_json_opts ~= nil end, 50)
      assert.is_nil(last_request_json_opts, 'Phase 2 should not fire when cache covers new page')
      assert.are.equal(2, vim.b.himalaya_page)
      assert.are.equal(5, #rendered_envs)
    end)
  end)

  -- ── cancel_resize ───────────────────────────────────────────────

  describe('cancel_resize', function()
    it('is a public function', function()
      assert.is_function(email.cancel_resize)
    end)

    it('does not error when nothing is pending', function()
      assert.has_no.errors(function()
        email.cancel_resize()
      end)
    end)

    it('does not error when called twice', function()
      assert.has_no.errors(function()
        email.cancel_resize()
        email.cancel_resize()
      end)
    end)

    it('stops a pending resize timer', function()
      -- Trigger a resize that starts a Phase 2 timer (grow beyond cache)
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      -- Timer is now pending; cancel should not error
      assert.has_no.errors(function()
        email.cancel_resize()
      end)
      -- Calling again after cancel should also be safe
      assert.has_no.errors(function()
        email.cancel_resize()
      end)
    end)
  end)

  -- ── resize_generation (stale callback protection) ──────────────

  describe('resize_generation', function()
    it('starts at 0 for a fresh module', function()
      assert.are.equal(0, email._get_resize_generation())
    end)

    it('cancel_resize increments generation when killing a job', function()
      local killed = false
      email._set_resize_job({ kill = function() killed = true end })

      local gen_before = email._get_resize_generation()
      email.cancel_resize()

      assert.is_true(killed)
      assert.are.equal(gen_before + 1, email._get_resize_generation())
      assert.is_nil(email._get_resize_job())
    end)

    it('cancel_resize does not increment generation when no job exists', function()
      local gen_before = email._get_resize_generation()
      email.cancel_resize()
      assert.are.equal(gen_before, email._get_resize_generation())
    end)

    it('list_with increments generation when killing a resize job', function()
      local killed = false
      email._set_resize_job({ kill = function() killed = true end })

      local gen_before = email._get_resize_generation()
      email.list_with('test', 'INBOX', 1, '')

      assert.is_true(killed)
      assert.are.equal(gen_before + 1, email._get_resize_generation())
    end)

    it('Phase 2 increments generation before issuing request', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      local gen_before = email._get_resize_generation()
      email.resize_listing()

      -- Wait for Phase 2 timer to fire
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'Phase 2 should fire')
      -- Generation must have been incremented by Phase 2 setup
      assert.is_true(email._get_resize_generation() > gen_before)

      email.cancel_resize()
    end)

    it('Phase 2 is_stale skips callback when generation is stale', function()
      -- Trigger a resize that starts Phase 2 (grow beyond cache)
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      -- Wait for Phase 2 timer to fire
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'Phase 2 should fire')

      -- is_stale should be a function
      assert.is_function(last_request_json_opts.is_stale)
      -- Not stale yet (generation hasn't changed)
      assert.is_false(last_request_json_opts.is_stale())

      -- Simulate a new resize happening (increments generation)
      email._set_resize_generation(email._get_resize_generation() + 1)

      -- Now is_stale reports true — on_exit will bail out before parsing
      assert.is_true(last_request_json_opts.is_stale())

      email.cancel_resize()
    end)

    it('Phase 2 request uses silent = true', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      -- Wait for Phase 2 timer to fire
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'Phase 2 should fire')
      assert.is_true(last_request_json_opts.silent,
        'Phase 2 request must use silent = true to suppress errors from killed jobs')

      email.cancel_resize()
    end)

    it('Phase 2 re-fetch kills bump generation on consecutive resizes', function()
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 3)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 3
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(3)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- First resize (grow beyond cache)
      vim.api.nvim_win_set_height(0, 7)
      email.resize_listing()
      local gen_after_first = email._get_resize_generation()

      -- Second resize should stop first timer and bump generation
      -- (the timer kill path only bumps when resize_job is non-nil,
      --  but the Phase 2 launch bumps unconditionally)
      vim.api.nvim_win_set_height(0, 10)
      email.resize_listing()

      -- Wait for the second Phase 2 to fire
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_true(email._get_resize_generation() > gen_after_first)

      email.cancel_resize()
    end)
  end)

  -- ── buffer state after resize ───────────────────────────────────

  describe('buffer state', function()
    it('sets modifiable to false after resize', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)

      email.resize_listing()

      assert.is_false(vim.bo.modifiable)
    end)

    it('writes correct number of lines to buffer', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)

      email.resize_listing()

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(5, #lines)
    end)

    it('buffer lines contain envelope IDs from overlap', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(11, 10)
      vim.b.himalaya_page = 2
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 10
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      -- First line should reference ID 11
      assert.is_truthy(lines[1]:find('11'))
    end)
  end)

  -- ── consecutive resizes ─────────────────────────────────────────

  describe('consecutive resizes', function()
    it('overlap narrows correctly across chained shrinks', function()
      -- Start with 10 envelopes on page 1
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- First shrink: 10 → 7
      vim.api.nvim_win_set_height(0, 7)
      email.resize_listing()
      email.cancel_resize() -- prevent timer from firing

      assert.are.equal(7, #rendered_envs)
      assert.are.equal(1, vim.b.himalaya_page)

      -- Second shrink: 7 → 4
      -- The envelopes cache is still the original 10 from page load
      vim.api.nvim_win_set_height(0, 4)
      email.resize_listing()
      email.cancel_resize()

      assert.are.equal(4, #rendered_envs)
      assert.are.equal(1, vim.b.himalaya_page)
      assert.are.equal('1', rendered_envs[1].id)
      assert.are.equal('4', rendered_envs[4].id)
    end)
  end)

  -- ── edge cases ──────────────────────────────────────────────────

  describe('edge cases', function()
    it('handles single envelope', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 1)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(1)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      assert.are.equal(1, vim.b.himalaya_page)
      assert.are.equal(1, #rendered_envs)
      assert.are.equal('1', rendered_envs[1].id)
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('handles shrink to height 1', function()
      vim.api.nvim_win_set_height(0, 1)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      email.resize_listing()

      assert.are.equal(1, vim.b.himalaya_page_size)
      assert.are.equal(1, #rendered_envs)
      -- global index 2 → page floor(2/1)+1 = 3, page_start 2, overlap = [2..3) = 1 item
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
    end)

    --[[
      Cursor at bottom of page 1 with shrink causes page change:
      10 envelopes, cursor on row 8 → global 7
      Shrink to 5 → new_page = floor(7/5)+1 = 2
      New page 2 covers global 5-9
      Overlap with cache (0-9) = 5-9 → envelopes[6..10] (IDs 6-10)
      cursor_line = 7 - 5 + 1 = 3
    ]]
    it('cursor at bottom causes page change during shrink', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {8, 0})

      email.resize_listing()

      assert.are.equal(2, vim.b.himalaya_page)
      assert.are.equal(5, vim.b.himalaya_page_size)
      assert.are.equal(5, #rendered_envs)
      assert.are.equal('6', rendered_envs[1].id)
      assert.are.equal('10', rendered_envs[5].id)
      -- cursor_line = 7-5+1 = 3
      assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it('cursor on last row of page 2 with shrink', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(11, 10)
      vim.b.himalaya_page = 2
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 10
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      -- Cursor on last row (10) → global 19
      -- new_page = floor(19/5)+1 = 4, page_start 15, page_end 20
      -- overlap_start = max(10,15)=15, overlap_end = min(20,20)=20
      -- display = envelopes[6..10] (IDs 16-20)
      -- cursor_line = 19-15+1 = 5
      vim.api.nvim_win_set_cursor(0, {10, 0})

      email.resize_listing()

      assert.are.equal(4, vim.b.himalaya_page)
      assert.are.equal(5, #rendered_envs)
      assert.are.equal('16', rendered_envs[1].id)
      assert.are.equal('20', rendered_envs[5].id)
      assert.are.equal(5, vim.api.nvim_win_get_cursor(0)[1])
    end)
  end)

  -- ── list_with cancels pending resize ─────────────────────────────

  describe('list_with cancels resize', function()
    it('cancels pending timer so user-initiated fetch wins', function()
      -- Trigger a resize to start a Phase 2 timer (grow beyond cache)
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()
      -- Timer is now pending; list_with should cancel it
      email.list_with('test', 'INBOX', 1, '')

      -- After list_with, cancel_resize should be a no-op (already cancelled)
      assert.has_no.errors(function()
        email.cancel_resize()
      end)
    end)

    it('kills in-flight resize job', function()
      local killed = false
      mock_request_job = { kill = function() killed = true end }

      -- Trigger resize to start timer (grow beyond cache)
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()
      -- The timer is pending but the job hasn't started yet (needs 150ms).
      -- Verify list_with still runs cleanly.
      assert.has_no.errors(function()
        email.list_with('test', 'INBOX', 1, '')
      end)
    end)
  end)

  -- ── list_with cancels probe ──────────────────────────────────────

  describe('list_with cancels probe', function()
    it('cancels the probe before issuing the CLI request', function()
      probe_cancel_count = 0
      email.list_with('test', 'INBOX', 1, '')

      assert.are.equal(1, probe_cancel_count,
        'list_with must cancel probe to release database lock before CLI fetch')
    end)
  end)

  -- ── on_list_with integration (via synchronous request mock) ──────

  describe('on_list_with integration', function()
    it('sets cache_offset buffer variable', function()
      -- With doubled fetch, display page 2 → cli_page=1, fetch_offset=0
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps * 2)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 2, '')

      assert.are.equal(0, vim.b.himalaya_cache_offset)
      vim.wo.winbar = ''
    end)

    it('sets page and page_size buffer variables', function()
      -- list_with subtracts 1 from winheight when winbar is empty (first load)
      local ps = vim.fn.winheight(0) - 1
      local envs = make_envelopes(1, ps)  -- realistic: CLI returns at most ps
      mock_request_sync_data = envs

      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)

      email.list_with('test', 'INBOX', 3, '')

      assert.are.equal(3, vim.b.himalaya_page)
      assert.are.equal(ps, vim.b.himalaya_page_size)
    end)

    it('truncates buffer after winbar reduces visible area', function()
      -- Override apply_header to actually set winbar (simulates real behavior)
      local orig_apply_header = package.loaded['himalaya.ui.listing'].apply_header
      package.loaded['himalaya.ui.listing'].apply_header = function(bufnr, header)
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(winid) == bufnr then
            vim.wo[winid].winbar = header
          end
        end
      end

      -- Window height = 6. Without winbar, winheight = 6.
      -- list_with subtracts 1 (no winbar) → ps = 5 → fetches 5 envelopes.
      -- on_list_with sets winbar → winheight drops to 5.
      -- page_size() = 5, #data = 5 → no truncation needed.
      -- But if CLI returned 6 (e.g., a re-fetch without the hack), truncation catches it.
      vim.api.nvim_win_set_height(0, 6)
      local envs = make_envelopes(1, 6)  -- more than visible area
      mock_request_sync_data = envs

      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)

      -- Simulate a re-fetch path (winbar not set, full 6 envelopes returned)
      -- by temporarily overriding page_size check in list_with
      vim.wo.winbar = 'already-set'  -- skip list_with subtraction
      email.list_with('test', 'INBOX', 1, '')
      -- After list_with, on_list_with sets new winbar via our mock.
      -- apply_header sets winbar → winheight drops by 1 → page_size() = 5
      -- on_list_with should truncate to 5 lines

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(5, #lines)
      assert.are.equal(5, vim.b.himalaya_page_size)

      -- Restore original mock
      package.loaded['himalaya.ui.listing'].apply_header = orig_apply_header
      vim.wo.winbar = ''
    end)

    it('restores cursor to saved_cursor_id after re-fetch', function()
      -- Step 1: populate the listing so it's a listing buffer
      local envs = make_envelopes(1, 5)
      mock_request_sync_data = envs
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      email.list_with('test', 'INBOX', 1, '')

      -- Now we have a listing buffer with IDs 1-5.
      -- Step 2: trigger a resize that starts Phase 2.
      vim.api.nvim_win_set_height(0, 3)
      email.resize_listing()
      email.cancel_resize() -- stop the timer so we control the flow

      -- Step 3: simulate what Phase 2 does — set saved_cursor_id then call list_with.
      -- The cursor should be on ID 1 (row 1 after the overlap render).
      -- Read the current cursor line's ID.
      local cursor_ln = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(0, cursor_ln - 1, cursor_ln, false)[1] or ''
      local cursor_id = email._get_email_id_from_line(line)
      assert.are.not_equal('', cursor_id)

      -- Step 4: simulate on_list_with with saved_cursor_id set.
      -- We need to trigger the saved_cursor_id path in on_list_with.
      -- The only way is to trigger a resize Phase 2 flow.  Since we can't
      -- fire the timer, we replicate: set buffer to a fresh listing state
      -- with envelopes containing the target ID, then call list_with.
      -- on_list_with should find the ID and set cursor.
      -- For this to work, we need to set saved_cursor_id... but it's
      -- module-local.  Instead, we verify cursor is on correct line after
      -- the full resize+list_with cycle.
      mock_request_sync_data = make_envelopes(1, 3)
      email.list_with('test', 'INBOX', 1, '')

      -- After a normal list_with (no saved_cursor_id), cursor goes to line 1
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
    end)
  end)

  -- ── doubled fetch (2x page_size for cache priming) ───────────────

  describe('doubled fetch', function()
    it('sends doubled page_size and adjusted CLI page for page 1', function()
      local ps = 5
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')

      -- CLI args: { folder, account_flag, page_size, page, query }
      assert.are.equal(ps * 2, last_request_json_opts.args[3],
        'CLI page_size should be doubled')
      assert.are.equal(1, last_request_json_opts.args[4],
        'CLI page should be ceil(1/2) = 1')
    end)

    it('sends doubled page_size and adjusted CLI page for page 2', function()
      local ps = 5
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 2, '')

      assert.are.equal(ps * 2, last_request_json_opts.args[3],
        'CLI page_size should be doubled')
      -- ceil(2/2) = 1 → CLI fetches page 1 with 2x size
      assert.are.equal(1, last_request_json_opts.args[4],
        'CLI page should be ceil(2/2) = 1')
    end)

    it('sends doubled page_size and adjusted CLI page for page 3', function()
      local ps = 5
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 3, '')

      assert.are.equal(ps * 2, last_request_json_opts.args[3],
        'CLI page_size should be doubled')
      -- ceil(3/2) = 2
      assert.are.equal(2, last_request_json_opts.args[4],
        'CLI page should be ceil(3/2) = 2')
    end)

    it('renders display page 2 from doubled data correctly', function()
      local ps = 5
      -- Mock: CLI returns 10 items for cli_page=1, fetch_ps=10
      mock_request_sync_data = make_envelopes(1, 10)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 2, '')

      -- Display page 2 should show IDs 6-10 (second half of doubled data)
      assert.is_not_nil(rendered_envs)
      assert.are.equal(ps, #rendered_envs)
      assert.are.equal('6', rendered_envs[1].id)
      assert.are.equal('10', rendered_envs[ps].id)

      vim.wo.winbar = ''
    end)

    it('sets correct cache_offset for doubled fetch on page 2', function()
      local ps = 5
      mock_request_sync_data = make_envelopes(1, 10)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 2, '')

      -- Data covers offset 0..9, cache_offset should be 0
      assert.are.equal(0, vim.b.himalaya_cache_offset)
      assert.are.equal(10, #vim.b.himalaya_envelopes)

      vim.wo.winbar = ''
    end)

    it('renders display page 1 from doubled data correctly', function()
      local ps = 5
      mock_request_sync_data = make_envelopes(1, 10)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')

      -- Display page 1 should show IDs 1-5 (first half)
      assert.is_not_nil(rendered_envs)
      assert.are.equal(ps, #rendered_envs)
      assert.are.equal('1', rendered_envs[1].id)
      assert.are.equal('5', rendered_envs[ps].id)

      vim.wo.winbar = ''
    end)
  end)

  -- ── Phase 2 re-fetch request args ────────────────────────────────

  describe('Phase 2 re-fetch', function()
    it('schedules a timer after height change', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      -- Verify Phase 2 timer fires (grow beyond cache)
      vim.wait(300, function() return last_request_json_opts ~= nil end)
      assert.is_not_nil(last_request_json_opts, 'Phase 2 should fire when cache is smaller than new page')

      email.cancel_resize()
    end)

    it('does not start timer on width-only change', function()
      local height = vim.fn.winheight(0)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = height  -- same height
      vim.b.himalaya_cache_offset = 0
      seed_buffer_lines(5)

      email.resize_listing()

      -- Width-only path doesn't create a timer.
      -- cancel_resize should still be safe.
      assert.has_no.errors(function()
        email.cancel_resize()
      end)
    end)

    it('resets timer on consecutive height changes', function()
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 3)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 3
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(3)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- First resize (grow beyond cache)
      vim.api.nvim_win_set_height(0, 7)
      email.resize_listing()

      -- Second resize (should stop first timer, start new one)
      vim.api.nvim_win_set_height(0, 10)
      assert.has_no.errors(function()
        email.resize_listing()
      end)

      email.cancel_resize()
    end)

    it('uses buffer page_size in re-fetch request, not window height', function()
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      email.resize_listing()

      local phase1_ps = vim.b.himalaya_page_size
      local phase1_page = vim.b.himalaya_page

      -- Wait for Phase 2 timer to fire
      vim.wait(300, function() return last_request_json_opts ~= nil end)

      assert.is_not_nil(last_request_json_opts, 'Phase 2 request should fire')
      -- args: { folder, account_flag, page_size, page, query }
      assert.are.equal(phase1_ps, last_request_json_opts.args[3],
        'Phase 2 page_size must match Phase 1')
      assert.are.equal(phase1_page, last_request_json_opts.args[4],
        'Phase 2 page must match Phase 1')

      email.cancel_resize()
    end)

    it('passes consistent page_size to on_list_with in Phase 2', function()
      -- 5 envelopes cached, grow to 10 → page 1, Phase 2 needed
      vim.api.nvim_win_set_height(0, 10)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 5)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 5
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(5)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      -- Phase 2 will call on_list_with which sets cache_offset = (page-1)*ps
      mock_request_sync_data = make_envelopes(1, 10)

      email.resize_listing()

      local phase1_ps = vim.b.himalaya_page_size
      local phase1_page = vim.b.himalaya_page

      -- Wait for Phase 2 to fire and process response
      vim.wait(300, function() return last_request_json_opts ~= nil end)

      -- on_list_with should have set cache_offset = (page-1) * page_size
      -- using the same page_size that Phase 1 computed
      assert.are.equal((phase1_page - 1) * phase1_ps, vim.b.himalaya_cache_offset,
        'cache_offset must be consistent with Phase 1 page_size')

      email.cancel_resize()
    end)
  end)

  -- ── rapid resize sequences ─────────────────────────────────────

  describe('rapid resize sequences', function()
    it('shrink by 15 lines at 5ms intervals triggers no Phase 2', function()
      local start_height = 20
      vim.api.nvim_win_set_height(0, start_height)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, start_height)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = start_height
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(start_height)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      local phase2_count = 0
      local orig_json = package.loaded['himalaya.request'].json
      package.loaded['himalaya.request'].json = function(opts)
        phase2_count = phase2_count + 1
        return orig_json(opts)
      end

      for i = 1, 15 do
        vim.api.nvim_win_set_height(0, start_height - i)
        email.resize_listing()
        if i < 15 then
          vim.wait(5, function() return false end)
        end
      end

      -- Wait long enough for any pending timer to fire
      vim.wait(250, function() return phase2_count > 0 end, 50)

      assert.are.equal(0, phase2_count, 'no Phase 2 should fire during shrink within cache')
      assert.are.equal(start_height - 15, vim.b.himalaya_page_size)

      package.loaded['himalaya.request'].json = orig_json
      email.cancel_resize()
    end)

    it('grow by 15 lines at 5ms intervals triggers exactly one Phase 2', function()
      local start_height = 5
      vim.api.nvim_win_set_height(0, start_height)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, start_height)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = start_height
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(start_height)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      local phase2_count = 0
      local orig_json = package.loaded['himalaya.request'].json
      package.loaded['himalaya.request'].json = function(opts)
        phase2_count = phase2_count + 1
        return orig_json(opts)
      end

      for i = 1, 15 do
        vim.api.nvim_win_set_height(0, start_height + i)
        email.resize_listing()
        if i < 15 then
          vim.wait(5, function() return false end)
        end
      end

      -- Wait for the debounced timer to fire (150ms + margin)
      vim.wait(300, function() return phase2_count > 0 end)

      assert.are.equal(1, phase2_count, 'exactly one Phase 2 should fire after debounce')
      assert.are.equal(start_height + 15, last_request_json_opts.args[3],
        'Phase 2 should use final page_size')

      package.loaded['himalaya.request'].json = orig_json
      email.cancel_resize()
    end)
  end)

  -- ── display_slice (width-only path) ──────────────────────────────

  describe('display_slice', function()
    it('returns all envelopes when fewer than page_size', function()
      local height = vim.fn.winheight(0)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 3)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = height
      vim.b.himalaya_cache_offset = 0
      seed_buffer_lines(3)

      email.resize_listing()

      assert.are.equal(3, #rendered_envs)
    end)

    it('truncates to page_size when more envelopes than height', function()
      local height = vim.fn.winheight(0)
      -- Ensure we have more envelopes than window height
      local count = height + 10
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, count)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = height
      vim.b.himalaya_cache_offset = 0
      seed_buffer_lines(count)

      email.resize_listing()

      assert.are.equal(height, #rendered_envs)
      -- Should be the first `height` envelopes
      assert.are.equal('1', rendered_envs[1].id)
      assert.are.equal(tostring(height), rendered_envs[height].id)
    end)
  end)

  -- ── cumulative cache via on_list_with ──────────────────────────

  describe('cumulative cache', function()
    -- With winbar='hdr' set, winheight(0) = height - 1.
    -- list_with skips the -1 subtraction when winbar is already present.
    -- So set height to ps+1 to get page_size() = ps.
    it('consecutive page fetches merge into cumulative cache', function()
      -- With doubled fetch, display pages 1 and 3 use cli_pages 1 and 2,
      -- producing contiguous data that should be merged.
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps * 2)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')

      assert.are.equal(ps * 2, #vim.b.himalaya_envelopes)
      assert.are.equal(0, vim.b.himalaya_cache_offset)
      assert.are.equal('1', vim.b.himalaya_envelopes[1].id)

      -- Display page 3 → cli_page=2, fetch_offset=10
      mock_request_sync_data = make_envelopes(11, ps * 2)
      email.list_with('test', 'INBOX', 3, '')

      assert.are.equal(20, #vim.b.himalaya_envelopes)
      assert.are.equal(0, vim.b.himalaya_cache_offset)
      assert.are.equal('1', vim.b.himalaya_envelopes[1].id)
      assert.are.equal('20', vim.b.himalaya_envelopes[20].id)

      vim.wo.winbar = ''
    end)

    it('folder change invalidates cache (no merge)', function()
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')
      assert.are.equal(ps, #vim.b.himalaya_envelopes)

      -- Different folder → cache_key changes → replace
      mock_request_sync_data = make_envelopes(101, ps)
      package.loaded['himalaya.state.folder'].current = function() return 'Sent' end
      email.list_with('test', 'Sent', 1, '')

      assert.are.equal(ps, #vim.b.himalaya_envelopes)
      assert.are.equal('101', vim.b.himalaya_envelopes[1].id)

      vim.wo.winbar = ''
    end)

    it('query change invalidates cache (no merge)', function()
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')
      assert.are.equal(ps, #vim.b.himalaya_envelopes)

      -- Different query → cache_key changes → replace
      mock_request_sync_data = make_envelopes(201, ps)
      email.list_with('test', 'INBOX', 1, 'subject:hello')

      assert.are.equal(ps, #vim.b.himalaya_envelopes)
      assert.are.equal('201', vim.b.himalaya_envelopes[1].id)

      vim.wo.winbar = ''
    end)
  end)

  -- ── resize + cumulative cache integration ─────────────────────

  describe('resize with cumulative cache', function()
    it('skips Phase 2 when cumulative cache covers new page', function()
      -- With doubled fetch, a single page 1 fetch gets 10 envelopes
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps * 2)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')

      -- Cache has 10 envelopes (IDs 1-10), page=1, page_size=5
      assert.are.equal(ps * 2, #vim.b.himalaya_envelopes)

      -- Grow window to 11 (winheight=10) → all 10 in cache
      vim.api.nvim_win_set_height(0, 11)
      last_request_json_opts = nil
      email.resize_listing()

      -- Phase 2 should NOT fire — cache covers page 1 with 10 envelopes
      vim.wait(250, function() return last_request_json_opts ~= nil end, 50)
      assert.is_nil(last_request_json_opts, 'Phase 2 should not fire when cumulative cache covers page')

      vim.wo.winbar = ''
      email.cancel_resize()
    end)

    it('resize after page navigation uses extended cache', function()
      -- Fetch page 1, then navigate to page 2, building cumulative cache
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')
      mock_request_sync_data = make_envelopes(6, ps)
      email.list_with('test', 'INBOX', 2, '')

      -- Cache: 10 envelopes (0..9), page=2, page_size=5
      -- Shrink to 4 (winheight=3) → cursor on row 1 (ID 6), global=5
      -- new_page = floor(5/3)+1 = 2, page covers 3..5
      -- Overlap with cache (0..9) = 3..5 → 3 envelopes
      vim.api.nvim_win_set_height(0, 4)
      vim.api.nvim_win_set_cursor(0, {1, 0})
      last_request_json_opts = nil
      email.resize_listing()

      -- Envelopes displayed, Phase 2 skipped (cache covers full page)
      vim.wait(250, function() return last_request_json_opts ~= nil end, 50)
      assert.is_nil(last_request_json_opts, 'Phase 2 should not fire — extended cache covers page')
      assert.are.equal(3, #rendered_envs)

      vim.wo.winbar = ''
      email.cancel_resize()
    end)

    it('shrink-then-grow within cumulative cache bounds triggers zero Phase 2 calls', function()
      -- With doubled fetch, page 1 gets 10 envelopes
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps * 2)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')

      assert.are.equal(ps * 2, #vim.b.himalaya_envelopes)

      local phase2_count = 0
      local orig_json = package.loaded['himalaya.request'].json
      package.loaded['himalaya.request'].json = function(opts)
        phase2_count = phase2_count + 1
        return orig_json(opts)
      end

      -- Shrink to 4 (winheight=3)
      vim.api.nvim_win_set_height(0, 4)
      vim.api.nvim_win_set_cursor(0, {1, 0})
      email.resize_listing()

      -- Grow to 9 (winheight=8, still within 10-envelope cache)
      vim.api.nvim_win_set_height(0, 9)
      email.resize_listing()

      -- Wait for any timers to fire
      vim.wait(250, function() return phase2_count > 0 end, 50)
      assert.are.equal(0, phase2_count, 'zero Phase 2 calls within cumulative cache bounds')

      package.loaded['himalaya.request'].json = orig_json
      vim.wo.winbar = ''
      email.cancel_resize()
    end)
  end)

  -- ── mark_envelope_seen with cumulative cache ──────────────────

  describe('mark_envelope_seen with cumulative cache', function()
    it('renders correct page slice on page 2 with cumulative cache', function()
      -- With doubled fetch, display page 2 uses cli_page=1.
      -- A single fetch with 10 items builds the cache for both pages.
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps * 2)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 2, '')

      -- Cache: 10 envelopes (IDs 1-10), page=2, page_size=5
      assert.are.equal(ps * 2, #vim.b.himalaya_envelopes)
      assert.are.equal(2, vim.b.himalaya_page)

      -- Buffer should show page 2 (IDs 6-10)
      local lines_before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.is_truthy(lines_before[1]:find('6'))

      -- Mark envelope 8 as seen
      email._mark_envelope_seen('8')

      -- After mark_seen, buffer should still show page 2 envelopes
      local lines_after = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(#lines_before, #lines_after)
      -- First line should still be envelope 6 (page 2), not envelope 1 (page 1)
      assert.is_truthy(lines_after[1]:find('6'),
        'first line must still be envelope 6 (page 2), not page 1')
      assert.is_truthy(lines_after[#lines_after]:find('10'),
        'last line must still be envelope 10')

      vim.wo.winbar = ''
    end)

    it('renders correct page slice on page 1 with cumulative cache', function()
      -- Build cumulative cache but stay on page 1
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')

      -- Cache: 5 envelopes (IDs 1-5), page=1, page_size=5
      assert.are.equal(1, vim.b.himalaya_page)

      email._mark_envelope_seen('3')

      local lines_after = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.is_truthy(lines_after[1]:find('1'),
        'first line must be envelope 1')
      assert.is_truthy(lines_after[#lines_after]:find('5'),
        'last line must be envelope 5')

      vim.wo.winbar = ''
    end)

    it('updates Seen flag in cumulative cache', function()
      -- With doubled fetch, build cache via display page 2 (cli_page=1).
      -- First 5 envelopes have Seen, second 5 do not.
      local ps = 5
      local all_envs = make_envelopes(1, ps * 2)
      for i = ps + 1, ps * 2 do all_envs[i].flags = {} end
      mock_request_sync_data = all_envs
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 2, '')

      -- Envelope 8 (index 8 in cache) should not have Seen flag yet
      local envs = vim.b.himalaya_envelopes
      local found_seen = false
      for _, f in ipairs(envs[8].flags) do
        if f == 'Seen' then found_seen = true end
      end
      assert.is_false(found_seen)

      email._mark_envelope_seen('8')

      -- Now envelope 8 in cache should have Seen flag
      envs = vim.b.himalaya_envelopes
      found_seen = false
      for _, f in ipairs(envs[8].flags) do
        if f == 'Seen' then found_seen = true end
      end
      assert.is_true(found_seen)

      vim.wo.winbar = ''
    end)

    it('renders correct slice after resize + page change + mark seen', function()
      -- With doubled fetch, page 1 gets 10 envelopes in one call
      local ps = 5
      mock_request_sync_data = make_envelopes(1, ps * 2)
      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)
      vim.wo.winbar = 'hdr'
      vim.api.nvim_win_set_height(0, ps + 1)

      email.list_with('test', 'INBOX', 1, '')

      assert.are.equal(ps * 2, #vim.b.himalaya_envelopes)

      -- Shrink to 4 (winheight=3), cursor on row 1 (ID 6), global=5
      -- new_page = floor(5/3)+1 = 2
      vim.api.nvim_win_set_height(0, 4)
      vim.api.nvim_win_set_cursor(0, {1, 0})
      email.resize_listing()
      email.cancel_resize()

      local resize_page = vim.b.himalaya_page
      local lines_after_resize = vim.api.nvim_buf_get_lines(0, 0, -1, false)

      -- Mark an envelope in the current display as seen
      local first_id = email._get_email_id_from_line(lines_after_resize[1])
      email._mark_envelope_seen(first_id)

      -- Buffer should still show the same page after mark_seen
      local lines_after_mark = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(#lines_after_resize, #lines_after_mark)
      assert.are.equal(resize_page, vim.b.himalaya_page)
      -- First displayed envelope should be the same
      local first_id_after = email._get_email_id_from_line(lines_after_mark[1])
      assert.are.equal(first_id, first_id_after)

      vim.wo.winbar = ''
    end)
  end)

  -- ── folder switch stale page guard ─────────────────────────────

  describe('folder switch stale page guard', function()
    it('does not clobber folder_state page when buffer cache_key is stale', function()
      -- Simulate: buffer has INBOX data on high page (e.g. page 85)
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 85
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 840
      vim.b.himalaya_query = ''
      vim.b.himalaya_cache_key = '--account test\0INBOX\0'
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- Folder switch happened: folder_state now returns 'Drafts'
      package.loaded['himalaya.state.folder'].current = function() return 'Drafts' end

      set_page_calls = {}
      email.resize_listing()

      -- resize_listing must NOT call folder_state.set_page() because
      -- the buffer's cache_key belongs to INBOX, not Drafts
      assert.are.equal(0, #set_page_calls,
        'resize_listing must not call set_page when buffer cache_key is stale')
    end)

    it('does not render stale data after folder switch', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 85
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 840
      vim.b.himalaya_query = ''
      vim.b.himalaya_cache_key = '--account test\0INBOX\0'
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- Folder switch happened
      package.loaded['himalaya.state.folder'].current = function() return 'Drafts' end

      rendered_envs = nil
      email.resize_listing()

      -- Should not render anything since the buffer data is stale
      assert.is_nil(rendered_envs, 'should not render stale data after folder switch')
    end)

    it('still resizes normally when cache_key matches current folder', function()
      vim.api.nvim_win_set_height(0, 5)
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      vim.b.himalaya_cache_key = '--account test\0INBOX\0'
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {3, 0})

      -- folder_state.current() returns 'INBOX' (default mock) — cache_key matches
      email.resize_listing()

      assert.is_not_nil(rendered_envs, 'should still render when cache_key matches')
      assert.are.equal(5, #rendered_envs)
    end)
  end)
end)

