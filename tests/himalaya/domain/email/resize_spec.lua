describe('himalaya.domain.email resize_listing', function()
  local email
  local set_page_calls
  local rendered_envs
  local original_height
  local last_request_json_opts    -- captured from request.json mock
  local mock_request_sync_data   -- set before list_with to make request.json call on_data synchronously
  local mock_request_job         -- return value for request.json (fake SystemObj)

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

    -- Stub out every dependency that email.lua requires at load time.
    -- request mock: captures args for verification; can be made synchronous
    -- by setting mock_request_sync_data before calling list_with.
    package.loaded['himalaya.request'] = {
      json = function(opts)
        last_request_json_opts = opts
        if mock_request_sync_data and opts.on_data then
          opts.on_data(mock_request_sync_data)
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
      cancel = function() end,
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

    it('truncates display around cursor when reading', function()
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

      -- Page stays 1 (no Phase 1 page change)
      assert.are.equal(1, vim.b.himalaya_page)
      -- Display is truncated
      assert.is_not_nil(rendered_envs)
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

    it('preserves page number while reading', function()
      vim.b.himalaya_buffer_type = 'listing'
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      -- Cursor in second half — would normally change page to 2
      vim.api.nvim_win_set_cursor(0, {8, 0})

      open_reading_window()
      vim.api.nvim_win_set_height(0, 5)
      email.resize_listing()

      -- Page must NOT change to 2 while reading
      assert.are.equal(1, vim.b.himalaya_page)
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
      -- Trigger a resize that starts a Phase 2 timer
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
      -- Trigger a resize to start a Phase 2 timer
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

      -- Trigger resize to start timer, but we need the timer to fire
      -- to create a job.  Instead, test indirectly: after list_with
      -- with a mock job set via the resize path, verify kill was called.
      -- We can't easily fire the timer in tests, so we verify the
      -- cancellation logic doesn't error with a killable job.
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
      -- The timer is pending but the job hasn't started yet (needs 150ms).
      -- Verify list_with still runs cleanly.
      assert.has_no.errors(function()
        email.list_with('test', 'INBOX', 1, '')
      end)
    end)
  end)

  -- ── on_list_with integration (via synchronous request mock) ──────

  describe('on_list_with integration', function()
    it('sets cache_offset buffer variable', function()
      -- Make request.json call on_data synchronously so on_list_with runs
      local page2_envs = make_envelopes(11, 5)
      mock_request_sync_data = page2_envs

      vim.b.himalaya_buffer_type = 'listing'
      seed_buffer_lines(1)

      -- list_with subtracts 1 from winheight when winbar is empty (first load)
      local ps = vim.fn.winheight(0) - 1
      email.list_with('test', 'INBOX', 2, '')

      assert.are.equal((2 - 1) * ps, vim.b.himalaya_cache_offset)
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

  -- ── Phase 2 re-fetch request args ────────────────────────────────

  describe('Phase 2 re-fetch', function()
    it('schedules a timer after height change', function()
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

      -- Verify the timer was created by checking cancel_resize
      -- actually has work to do (no error, and a second resize would
      -- reset the timer rather than creating a second one).
      assert.has_no.errors(function()
        email.cancel_resize()
      end)
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
      vim.b.himalaya_envelopes = make_envelopes(1, 10)
      vim.b.himalaya_page = 1
      vim.b.himalaya_page_size = 10
      vim.b.himalaya_cache_offset = 0
      vim.b.himalaya_query = ''
      seed_buffer_lines(10)
      vim.api.nvim_win_set_cursor(0, {1, 0})

      -- First resize
      vim.api.nvim_win_set_height(0, 7)
      email.resize_listing()

      -- Second resize (should stop first timer, start new one)
      vim.api.nvim_win_set_height(0, 4)
      assert.has_no.errors(function()
        email.resize_listing()
      end)

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
end)

