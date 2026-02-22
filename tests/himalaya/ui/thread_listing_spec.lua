describe('himalaya.ui.thread_listing', function()
  local thread_listing
  local define_spy, shared_spy
  local define_highlights_spy, apply_syntax_spy
  local bufnr

  before_each(function()
    -- Clear all himalaya modules so we get a fresh require
    for key, _ in pairs(package.loaded) do
      if key:find('^himalaya%.') then
        package.loaded[key] = nil
      end
    end

    -- Stub load-time dependencies

    define_spy = spy.new(function() end)
    shared_spy = spy.new(function() end)
    package.loaded['himalaya.keybinds'] = {
      define = define_spy,
      shared_listing_keybinds = shared_spy,
    }

    package.loaded['himalaya.domain.email.thread_listing'] = {
      read = function() end,
      previous_page = function() end,
      next_page = function() end,
      set_thread_query = function() end,
      toggle_to_flat = function() end,
      toggle_reverse = function() end,
      resize = function() end,
    }

    package.loaded['himalaya.ui.win'] = {
      find_by_bufnr = function()
        return nil
      end,
    }

    -- Lazy-loaded inside setup() and apply_syntax()
    define_highlights_spy = spy.new(function() end)
    apply_syntax_spy = spy.new(function() end)
    package.loaded['himalaya.ui.listing'] = {
      define_highlights = define_highlights_spy,
      apply_syntax = apply_syntax_spy,
    }

    package.loaded['himalaya.perf'] = {
      start = function() end,
      stop = function() end,
    }

    -- Stubs needed by shared_listing_keybinds (in case real keybinds is loaded)
    package.loaded['himalaya.domain.email'] = {
      read = function() end,
      download_attachments = function() end,
      select_folder_then_copy = function() end,
      select_folder_then_move = function() end,
      delete = function() end,
      mark_seen = function() end,
      mark_unseen = function() end,
      flag_add = function() end,
      flag_remove = function() end,
    }
    package.loaded['himalaya.domain.folder'] = {
      select = function() end,
    }
    package.loaded['himalaya.domain.email.compose'] = {
      write = function() end,
      reply = function() end,
      reply_all = function() end,
      forward = function() end,
    }
    package.loaded['himalaya.config'] = {
      get = function()
        return {}
      end,
    }

    thread_listing = require('himalaya.ui.thread_listing')

    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('sets buffer options: buftype=nofile, modifiable=false, cursorline=true', function()
    thread_listing.setup(bufnr)

    assert.are.equal('nofile', vim.bo[bufnr].buftype)
    assert.is_false(vim.bo[bufnr].modifiable)

    -- cursorline is window-local, set via nvim_buf_call; check against the window showing the buf
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      assert.is_true(vim.wo[winid].cursorline)
    end
  end)

  it('defines HimalayaTree highlight linked to Comment', function()
    thread_listing.setup(bufnr)

    local hl = vim.api.nvim_get_hl(0, { name = 'HimalayaTree' })
    assert.is_truthy(hl.link)
    assert.are.equal('Comment', hl.link)
  end)

  it('registers 6 thread-specific keybinds via keybinds.define', function()
    thread_listing.setup(bufnr)

    assert.spy(define_spy).was_called()
    local call_args = define_spy.calls[1].vals
    local bindings = call_args[2]
    assert.are.equal(6, #bindings)

    local expected_keys = { '<cr>', 'gp', 'gn', 'g/', 'gt', 'gT' }
    for i, expected in ipairs(expected_keys) do
      assert.are.equal(expected, bindings[i][2])
    end
  end)

  it('creates VimResized and WinResized autocmds in HimalayaThreadListing augroup', function()
    thread_listing.setup(bufnr)

    local autocmds = vim.api.nvim_get_autocmds({ group = 'HimalayaThreadListing' })
    local events = {}
    for _, ac in ipairs(autocmds) do
      events[ac.event] = true
    end
    assert.is_true(events['VimResized'] or false)
    assert.is_true(events['WinResized'] or false)
  end)

  it('calls listing.define_highlights()', function()
    thread_listing.setup(bufnr)

    assert.spy(define_highlights_spy).was_called(1)
  end)
end)
