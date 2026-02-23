describe('himalaya.keybinds', function()
  local keybinds, config, buf

  before_each(function()
    package.loaded['himalaya.keybinds'] = nil
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
    keybinds = require('himalaya.keybinds')
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    -- Close any floating windows left open by show_help tests
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local win_cfg = vim.api.nvim_win_get_config(winid)
      if win_cfg.relative and win_cfg.relative ~= '' then
        pcall(vim.api.nvim_win_close, winid, true)
      end
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  --- Helper: collect all lhs strings for a mode on a buffer.
  local function mapped_keys(b, mode)
    local set = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(b, mode)) do
      set[map.lhs] = true
    end
    return set
  end

  --- Helper: assert a list of keys are all mapped.
  local function assert_keys(b, mode, keys)
    local set = mapped_keys(b, mode)
    for _, k in ipairs(keys) do
      assert.is_true(set[k] ~= nil, mode .. ' ' .. k .. ' should be mapped')
    end
  end

  --- Define a single test binding.
  local function bind(name, key, mode)
    keybinds.define(buf, {
      { mode or 'n', key or 'gx', function() end, name or 'test-action' },
    })
  end

  describe('define', function()
    it('creates buffer-local and Plug mappings', function()
      bind('test-action', 'gx')

      assert.is_true(mapped_keys(buf, 'n')['gx'] ~= nil)

      -- Global Plug mapping
      local found = false
      for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
        if map.lhs == '<Plug>(himalaya-test-action)' then
          assert.are.equal('Himalaya: test-action', map.desc)
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it('respects user override key', function()
      config.setup({ keymaps = { ['test-action'] = 'gz' } })
      bind('test-action', 'gx')

      local keys = mapped_keys(buf, 'n')
      assert.is_true(keys['gz'] ~= nil)
      assert.is_nil(keys['gx'])
    end)

    it('disables keymap when user sets false', function()
      config.setup({ keymaps = { ['test-action'] = false } })
      bind('test-action', 'gx')

      assert.is_nil(mapped_keys(buf, 'n')['gx'])
    end)

    it('defines multiple bindings at once', function()
      keybinds.define(buf, {
        { 'n', 'ga', function() end, 'action-a' },
        { 'n', 'gb', function() end, 'action-b' },
        { 'n', 'gc', function() end, 'action-c' },
      })
      assert_keys(buf, 'n', { 'ga', 'gb', 'gc' })
    end)
  end)

  describe('visual_range', function()
    before_each(function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b', 'c', 'd' })
    end)

    it('passes line range to the wrapped function', function()
      local captured
      local wrapped = keybinds.visual_range(function(first, last)
        captured = { first, last }
      end)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      wrapped()
      assert.are.same({ 2, 2 }, captured)
    end)

    it('swaps reversed range so first <= last', function()
      local captured
      local wrapped = keybinds.visual_range(function(first, last)
        captured = { first, last }
      end)

      -- Stub vim.fn.line to simulate an inverted visual selection
      local orig_line = vim.fn.line
      vim.fn.line = function(mark)
        if mark == 'v' then
          return 4
        end
        if mark == '.' then
          return 2
        end
        return orig_line(mark)
      end

      wrapped()
      vim.fn.line = orig_line

      assert.are.same({ 2, 4 }, captured)
    end)
  end)

  describe('show_help', function()
    it('opens a float listing keybind names', function()
      bind('test-action', 'gx')
      bind('other-action', 'gy')

      local wins_before = #vim.api.nvim_tabpage_list_wins(0)
      keybinds.show_help()

      assert.are.equal(wins_before + 1, #vim.api.nvim_tabpage_list_wins(0))

      local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.truthy(content:find('test%-action'))
      assert.truthy(content:find('other%-action'))
    end)

    it('shows fallback message when no keybinds exist', function()
      keybinds.show_help()
      local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.truthy(content:find('No Himalaya keybinds'))
    end)

    it('sets q and <Esc> to close the float', function()
      bind('test-action', 'gx')
      keybinds.show_help()
      local float_buf = vim.api.nvim_get_current_buf()
      assert_keys(float_buf, 'n', { 'q', '<Esc>' })
    end)
  end)

  describe('shared_listing_keybinds', function()
    before_each(function()
      package.loaded['himalaya.domain.email.compose'] = {
        write = function() end,
        reply = function() end,
        reply_all = function() end,
        forward = function() end,
      }
      package.loaded['himalaya.domain.email'] = {
        download_attachments = function() end,
        select_folder_then_copy = function() end,
        select_folder_then_move = function() end,
        delete = function() end,
        mark_seen = function() end,
        mark_unseen = function() end,
        flag_add = function() end,
        flag_remove = function() end,
        open_browser = function() end,
      }
      package.loaded['himalaya.keybinds'] = nil
      keybinds = require('himalaya.keybinds')
    end)

    it('defines all normal-mode shared bindings', function()
      keybinds.shared_listing_keybinds(buf)
      assert_keys(buf, 'n', {
        'gw',
        'gr',
        'gR',
        'gf',
        'ga',
        'gA',
        'gC',
        'gM',
        'dd',
        'gs',
        'gS',
        'gFa',
        'gFr',
        'gm',
        'go',
        '?',
      })
    end)

    it('defines all visual-mode shared bindings', function()
      keybinds.shared_listing_keybinds(buf)
      assert_keys(buf, 'v', { 'gC', 'gM', 'd', 'gs', 'gS', 'gFa', 'gFr' })
    end)
  end)
end)
