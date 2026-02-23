describe('himalaya.ui.reading', function()
  local reading
  local bufnr

  local noop = function() end

  before_each(function()
    for key in pairs(package.loaded) do
      if key:match('^himalaya') then
        package.loaded[key] = nil
      end
    end

    package.loaded['himalaya.domain.email'] = {
      download_attachments = noop,
      select_folder_then_copy = noop,
      select_folder_then_move = noop,
      delete = noop,
      open_browser = noop,
      read = noop,
    }
    package.loaded['himalaya.domain.account'] = {
      select = noop,
    }
    package.loaded['himalaya.domain.email.compose'] = {
      write = noop,
      reply = noop,
      reply_all = noop,
      forward = noop,
    }
    package.loaded['himalaya.ui.win'] = {
      find_by_buftype = noop,
      find_by_bufnr = function(b)
        return vim.fn.bufwinid(b)
      end,
    }
    package.loaded['himalaya.config'] = {
      get = function()
        return { keymaps = {} }
      end,
    }

    reading = require('himalaya.ui.reading')

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('exposes a setup function', function()
    assert.is_function(reading.setup)
  end)

  it('setup() sets buffer options', function()
    reading.setup(bufnr)
    assert.equals('wipe', vim.bo[bufnr].bufhidden)
    assert.equals('nofile', vim.bo[bufnr].buftype)
    assert.equals('mail', vim.bo[bufnr].filetype)
    assert.is_false(vim.bo[bufnr].modifiable)
  end)

  it('setup() sets foldmethod=expr', function()
    reading.setup(bufnr)
    assert.equals('expr', vim.wo.foldmethod)
  end)

  it('setup() registers reading keybinds', function()
    reading.setup(bufnr)
    local maps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
    local expected_keys = { 'gw', 'gr', 'gR', 'gf', 'ga', 'gA', 'gC', 'gM', 'gD', 'go', 'gn', 'gp', '?' }
    for _, key in ipairs(expected_keys) do
      local found = false
      for _, map in ipairs(maps) do
        if map.lhs == key then
          found = true
          break
        end
      end
      assert.is_true(found, 'expected keybind ' .. key .. ' to be registered')
    end
  end)

  it('setup() sets winbar with account/folder context', function()
    vim.b[bufnr].himalaya_account = 'work'
    vim.b[bufnr].himalaya_folder = 'INBOX'
    vim.b[bufnr].himalaya_current_email_id = '42'
    reading.setup(bufnr)
    local winid = vim.fn.bufwinid(bufnr)
    assert.is_truthy(vim.wo[winid].winbar:find('%[work%]'))
    assert.is_truthy(vim.wo[winid].winbar:find('%[INBOX%]'))
    assert.is_truthy(vim.wo[winid].winbar:find('42'))
  end)

  it('setup() registers exactly 12 normal-mode keybinds', function()
    reading.setup(bufnr)
    local maps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
    local count = 0
    for _, map in ipairs(maps) do
      if map.desc and map.desc:find('^Himalaya:') then
        count = count + 1
      end
    end
    assert.equals(13, count)
  end)

  describe('navigate_email via keybinds', function()
    local listing_bufnr
    local listing_winid
    local orig_winid
    local email_read_called

    before_each(function()
      email_read_called = false

      -- Remember the window that has the reading buffer
      orig_winid = vim.api.nvim_get_current_win()

      -- Create a listing buffer with multiple lines
      listing_bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[listing_bufnr].buftype = 'nofile'
      vim.b[listing_bufnr].himalaya_buftype = 'listing'
      vim.api.nvim_buf_set_lines(listing_bufnr, 0, -1, false, {
        'line 1',
        'line 2',
        'line 3',
      })

      -- Open listing buffer in a split so it has its own window
      vim.cmd('split')
      listing_winid = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(listing_winid, listing_bufnr)
      vim.api.nvim_win_set_cursor(listing_winid, { 2, 0 })

      -- Switch back to the original window (which still has bufnr)
      vim.api.nvim_set_current_win(orig_winid)

      -- Re-stub modules for this context
      package.loaded['himalaya.domain.email'] = {
        download_attachments = noop,
        select_folder_then_copy = noop,
        select_folder_then_move = noop,
        delete = noop,
        open_browser = noop,
        read = function()
          email_read_called = true
        end,
      }
      package.loaded['himalaya.ui.win'] = {
        find_by_buftype = function()
          if vim.api.nvim_win_is_valid(listing_winid) then
            return listing_winid, listing_bufnr
          end
          return nil
        end,
        find_by_bufnr = function(b)
          return vim.fn.bufwinid(b)
        end,
      }

      -- Re-require to pick up new stubs
      package.loaded['himalaya.ui.reading'] = nil
      reading = require('himalaya.ui.reading')
    end)

    after_each(function()
      -- Close extra split first
      if listing_winid and vim.api.nvim_win_is_valid(listing_winid) then
        vim.api.nvim_win_close(listing_winid, true)
      end
      if listing_bufnr and vim.api.nvim_buf_is_valid(listing_bufnr) then
        vim.api.nvim_buf_delete(listing_bufnr, { force = true })
      end
    end)

    it('gn navigates to next email', function()
      reading.setup(bufnr)
      -- Current window has bufnr, keymaps are buffer-local
      vim.cmd('normal gn')
      assert.is_true(email_read_called)
      local row = vim.api.nvim_win_get_cursor(listing_winid)[1]
      assert.are.equal(3, row)
    end)

    it('gp navigates to previous email', function()
      reading.setup(bufnr)
      vim.cmd('normal gp')
      assert.is_true(email_read_called)
      local row = vim.api.nvim_win_get_cursor(listing_winid)[1]
      assert.are.equal(1, row)
    end)

    it('gn does nothing at last line', function()
      vim.api.nvim_win_set_cursor(listing_winid, { 3, 0 })
      reading.setup(bufnr)
      vim.cmd('normal gn')
      assert.is_false(email_read_called)
      local row = vim.api.nvim_win_get_cursor(listing_winid)[1]
      assert.are.equal(3, row)
    end)

    it('gp does nothing at first line', function()
      vim.api.nvim_win_set_cursor(listing_winid, { 1, 0 })
      reading.setup(bufnr)
      vim.cmd('normal gp')
      assert.is_false(email_read_called)
      local row = vim.api.nvim_win_get_cursor(listing_winid)[1]
      assert.are.equal(1, row)
    end)

    it('navigate_email returns early when no listing window found', function()
      package.loaded['himalaya.ui.win'] = {
        find_by_buftype = function()
          return nil
        end,
        find_by_bufnr = function(b)
          return vim.fn.bufwinid(b)
        end,
      }
      package.loaded['himalaya.ui.reading'] = nil
      reading = require('himalaya.ui.reading')
      reading.setup(bufnr)
      -- Should not error
      vim.cmd('normal gn')
      assert.is_false(email_read_called)
    end)
  end)

  describe('ga keybind', function()
    it('calls account.select when triggered', function()
      local account_selected = false
      package.loaded['himalaya.domain.account'] = {
        select = function()
          account_selected = true
        end,
      }
      package.loaded['himalaya.ui.reading'] = nil
      reading = require('himalaya.ui.reading')
      reading.setup(bufnr)
      vim.cmd('normal ga')
      assert.is_true(account_selected)
    end)
  end)
end)
