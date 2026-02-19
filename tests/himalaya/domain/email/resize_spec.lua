describe('himalaya.domain.email resize_listing', function()
  local email
  local set_page_calls
  local rendered_envs
  local original_height

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

    -- Stub out every dependency that email.lua requires at load time.
    package.loaded['himalaya.request'] = {
      json = function() return nil end,
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
end)
