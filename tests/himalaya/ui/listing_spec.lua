describe('himalaya.ui.listing', function()
  local listing

  before_each(function()
    package.loaded['himalaya.ui.listing'] = nil
    listing = require('himalaya.ui.listing')
  end)

  it('exposes a setup function', function()
    assert.is_function(listing.setup)
  end)

  it('defines highlight groups', function()
    listing.define_highlights()
    local hl = vim.api.nvim_get_hl(0, { name = 'HimalayaHead' })
    assert.is_truthy(hl.bold)
  end)

  describe('get_email_id_from_line', function()
    it('extracts numeric ID from a listing line', function()
      local id = listing.get_email_id_from_line('123│flags│subject│sender│date')
      assert.are.equal('123', id)
    end)

    it('returns empty string for blank or non-numeric line', function()
      assert.are.equal('', listing.get_email_id_from_line(''))
      assert.are.equal('', listing.get_email_id_from_line('no-numbers-here'))
    end)
  end)

  describe('effective_page_size', function()
    it('returns winheight minus 1 when winbar is empty', function()
      local height = vim.fn.winheight(0)
      vim.wo.winbar = ''
      local ps = listing.effective_page_size()
      assert.are.equal(math.max(1, height - 1), ps)
    end)

    it('clamps to minimum of 1', function()
      -- Even with a tiny window, effective_page_size must be >= 1
      local ps = listing.effective_page_size()
      assert.is_true(ps >= 1)
    end)
  end)

  describe('gutter_width', function()
    local buf, winid

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      winid = vim.api.nvim_get_current_win()
    end)

    after_each(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('returns 0 when no number/sign/fold columns', function()
      vim.wo[winid].number = false
      vim.wo[winid].relativenumber = false
      vim.wo[winid].foldcolumn = '0'
      vim.wo[winid].signcolumn = 'no'
      assert.are.equal(0, listing.gutter_width(winid, buf))
    end)

    it('includes numberwidth when number is set', function()
      vim.wo[winid].number = true
      vim.wo[winid].relativenumber = false
      vim.wo[winid].foldcolumn = '0'
      vim.wo[winid].signcolumn = 'no'
      local width = listing.gutter_width(winid, buf)
      assert.is_true(width >= vim.wo[winid].numberwidth)
    end)

    it('includes signcolumn width when signcolumn is yes', function()
      vim.wo[winid].number = false
      vim.wo[winid].relativenumber = false
      vim.wo[winid].foldcolumn = '0'
      vim.wo[winid].signcolumn = 'yes'
      assert.are.equal(2, listing.gutter_width(winid, buf))
    end)
  end)

  describe('apply_header', function()
    local buf, winid

    before_each(function()
      for k in pairs(package.loaded) do
        if k:match('^himalaya') then
          package.loaded[k] = nil
        end
      end

      package.loaded['himalaya.keybinds'] = {
        define = function() end,
        shared_listing_keybinds = function() end,
      }
      package.loaded['himalaya.domain.email'] = {}
      package.loaded['himalaya.domain.folder'] = {}
      package.loaded['himalaya.perf'] = { start = function() end, stop = function() end }
      package.loaded['himalaya.ui.win'] = {
        find_by_bufnr = function()
          return winid
        end,
      }

      listing = require('himalaya.ui.listing')

      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      winid = vim.api.nvim_get_current_win()
    end)

    after_each(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('sets winbar with HimalayaHead highlight prefix', function()
      listing.apply_header(buf, 'ID│Flags│Subject│Sender│Date')
      local bar = vim.wo[winid].winbar
      assert.is_truthy(bar:find('HimalayaHead', 1, true))
      assert.is_truthy(bar:find('ID', 1, true))
    end)
  end)

  describe('apply_highlights', function()
    local buf

    before_each(function()
      for k in pairs(package.loaded) do
        if k:match('^himalaya') then
          package.loaded[k] = nil
        end
      end

      package.loaded['himalaya.keybinds'] = {
        define = function() end,
        shared_listing_keybinds = function() end,
      }
      package.loaded['himalaya.domain.email'] = {}
      package.loaded['himalaya.domain.folder'] = {}
      package.loaded['himalaya.perf'] = { start = function() end, stop = function() end }
      package.loaded['himalaya.ui.win'] = { find_by_bufnr = function() end }

      listing = require('himalaya.ui.listing')

      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '  1│   │subj│sender│date',
        '  2│   │subj│sender│date',
        '  3│   │subj│sender│date',
      })
    end)

    after_each(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('applies 9 extmarks on unseen lines (5 columns + 4 separators)', function()
      listing.apply_highlights(buf, {
        { flags = {} },
        { flags = { 'Seen' } },
        { flags = { 'Flagged' } },
      })
      local ns = vim.api.nvim_create_namespace('himalaya_seen')
      -- Line 1 (unseen): 5 columns + 4 separators = 9
      local marks1 = vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 0, -1 }, {})
      assert.are.equal(9, #marks1)
    end)

    it('applies 4 extmarks on seen lines (separators only)', function()
      listing.apply_highlights(buf, {
        { flags = {} },
        { flags = { 'Seen' } },
        { flags = { 'Flagged' } },
      })
      local ns = vim.api.nvim_create_namespace('himalaya_seen')
      -- Line 2 (seen): 4 separators only
      local marks2 = vim.api.nvim_buf_get_extmarks(buf, ns, { 1, 0 }, { 1, -1 }, {})
      assert.are.equal(4, #marks2)
    end)

    it('applies 4 extmarks on nil-flags lines (separators only)', function()
      listing.apply_highlights(buf, {
        { flags = {} },
        { flags = { 'Seen' } },
        {},
      })
      local ns = vim.api.nvim_create_namespace('himalaya_seen')
      -- Line 3 (nil flags): 4 separators only
      local marks3 = vim.api.nvim_buf_get_extmarks(buf, ns, { 2, 0 }, { 2, -1 }, {})
      assert.are.equal(4, #marks3)
    end)

    it('clears previous extmarks before applying', function()
      local ns = vim.api.nvim_create_namespace('himalaya_seen')

      listing.apply_highlights(buf, {
        { flags = {} },
        { flags = {} },
        { flags = {} },
      })
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      -- 3 unseen lines × 9 extmarks = 27
      assert.are.equal(27, #marks)

      -- Second pass: first line now seen — should drop to 4 + 9 + 9 = 22
      listing.apply_highlights(buf, {
        { flags = { 'Seen' } },
        { flags = {} },
        { flags = {} },
      })
      marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(22, #marks)
    end)

    it('mark_line_as_seen removes column extmarks, keeps separators', function()
      listing.apply_highlights(buf, {
        { flags = {} },
        { flags = {} },
        { flags = {} },
      })
      local ns = vim.api.nvim_create_namespace('himalaya_seen')

      -- Line 1 should have 9 extmarks (unseen)
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 0, -1 }, {})
      assert.are.equal(9, #marks)

      -- Mark line 1 as seen
      listing.mark_line_as_seen(buf, 0)

      -- Now line 1 should have 4 extmarks (separators only)
      marks = vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 0, -1 }, {})
      assert.are.equal(4, #marks)

      -- Other lines unchanged
      local marks2 = vim.api.nvim_buf_get_extmarks(buf, ns, { 1, 0 }, { 1, -1 }, {})
      assert.are.equal(9, #marks2)
    end)
  end)

  describe('setup', function()
    local buf
    local define_bindings

    before_each(function()
      for k in pairs(package.loaded) do
        if k:match('^himalaya') then
          package.loaded[k] = nil
        end
      end

      define_bindings = {}

      package.loaded['himalaya.keybinds'] = {
        define = function(_, bindings)
          for _, b in ipairs(bindings) do
            define_bindings[#define_bindings + 1] = b[4] -- collect binding names
          end
        end,
        shared_listing_keybinds = function() end,
      }
      package.loaded['himalaya.domain.email'] = {
        read = function() end,
        set_list_envelopes_query = function() end,
        apply_search_preset = function() end,
        resize_listing = function() end,
        cancel_resize = function() end,
        cleanup = function() end,
      }
      package.loaded['himalaya.domain.email.probe'] = {
        cleanup = function() end,
      }
      package.loaded['himalaya.domain.folder'] = {
        select_previous_page = function() end,
        select_next_page = function() end,
      }
      package.loaded['himalaya.perf'] = { start = function() end, stop = function() end }
      package.loaded['himalaya.ui.win'] = { find_by_bufnr = function() end }
      package.loaded['himalaya.config'] = {
        get = function()
          return { keymaps = {} }
        end,
      }

      listing = require('himalaya.ui.listing')

      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
    end)

    after_each(function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it('sets buffer options (buftype=nofile, modifiable=false)', function()
      listing.setup(buf)
      assert.are.equal('nofile', vim.bo[buf].buftype)
      assert.is_false(vim.bo[buf].modifiable)
    end)

    it('creates autocmds in HimalayaListing augroup', function()
      listing.setup(buf)
      local autocmds = vim.api.nvim_get_autocmds({ group = 'HimalayaListing' })
      local events = {}
      for _, ac in ipairs(autocmds) do
        events[ac.event] = true
      end
      assert.is_true(events['VimResized'] or false)
      assert.is_true(events['WinResized'] or false)
      assert.is_true(events['BufWipeout'] or false)
    end)
  end)
end)
