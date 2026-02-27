describe('himalaya.pickers.telescope', function()
  local telescope_mod
  local captured_finder_opts
  local captured_picker_opts
  local mock_replace_fn
  local buffers_to_cleanup = {}

  before_each(function()
    package.loaded['himalaya.pickers.telescope'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['telescope.actions'] = nil
    package.loaded['telescope.actions.state'] = nil
    package.loaded['telescope.finders'] = nil
    package.loaded['telescope.pickers'] = nil
    package.loaded['telescope.sorters'] = nil
    package.loaded['telescope.previewers'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.domain.email'] = nil

    captured_finder_opts = nil
    captured_picker_opts = nil
    mock_replace_fn = nil

    package.loaded['telescope.actions'] = {
      select_default = {
        replace = function(_self, fn)
          mock_replace_fn = fn
        end,
      },
      close = function() end,
    }

    package.loaded['telescope.actions.state'] = {
      get_selected_entry = function()
        return { display = 'INBOX', value = 'INBOX', ordinal = 'INBOX' }
      end,
    }

    package.loaded['telescope.finders'] = {
      new_table = function(opts)
        captured_finder_opts = opts
        return opts
      end,
    }

    package.loaded['telescope.pickers'] = {
      new = function(_base, opts)
        captured_picker_opts = opts
        return { find = function() end }
      end,
    }

    package.loaded['telescope.sorters'] = {
      get_generic_fuzzy_sorter = function()
        return 'mock_sorter'
      end,
    }

    package.loaded['telescope.previewers'] = {
      display_content = {
        new = function()
          return 'mock_previewer'
        end,
      },
    }

    local config = require('himalaya.config')
    config._reset()

    telescope_mod = require('himalaya.pickers.telescope')
  end)

  after_each(function()
    for _, buf in ipairs(buffers_to_cleanup) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    buffers_to_cleanup = {}
  end)

  it('entry_maker produces name-based fields', function()
    telescope_mod.select(function() end, { { name = 'INBOX' } })

    local entry = captured_finder_opts.entry_maker({ name = 'Sent' })
    assert.are.equal('Sent', entry.value)
    assert.are.equal('Sent', entry.display)
    assert.are.equal('Sent', entry.ordinal)
  end)

  it('does not set previewer when telescope_preview is disabled', function()
    telescope_mod.select(function() end, { { name = 'INBOX' } })
    assert.is_nil(captured_picker_opts.previewer)
  end)

  it('sets previewer when telescope_preview is enabled', function()
    local config = require('himalaya.config')
    config.setup({ telescope_preview = true })

    telescope_mod.select(function() end, { { name = 'INBOX' } })

    assert.is_not_nil(captured_picker_opts.previewer)
  end)

  it('preview entry_maker returns entries with preview_command', function()
    local config = require('himalaya.config')
    config.setup({ telescope_preview = true })

    telescope_mod.select(function() end, { { name = 'INBOX' } })

    local entry = captured_finder_opts.entry_maker({ name = 'Drafts' })
    assert.are.equal('Drafts', entry.value)
    assert.are.equal('Drafts', entry.display)
    assert.are.equal('Drafts', entry.ordinal)
    assert.is_function(entry.preview_command)
  end)

  it('preview_command calls email.list_with for the folder', function()
    local config = require('himalaya.config')
    config.setup({ telescope_preview = true })

    local list_with_args = nil
    package.loaded['himalaya.state.account'] = {
      default = function()
        return 'test-account'
      end,
    }
    package.loaded['himalaya.domain.email'] = {
      list_with = function(account, folder, page, query)
        list_with_args = { account = account, folder = folder, page = page, query = query }
        return {}
      end,
    }

    telescope_mod.select(function() end, { { name = 'INBOX' } })

    local entry = captured_finder_opts.entry_maker({ name = 'Drafts' })
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(buffers_to_cleanup, bufnr)
    entry.preview_command(entry, bufnr)

    assert.is_not_nil(list_with_args)
    assert.are.equal('test-account', list_with_args.account)
    assert.are.equal('Drafts', list_with_args.folder)
    assert.are.equal(1, list_with_args.page)
    assert.are.equal('', list_with_args.query)
  end)

  it('preview_command displays errors in buffer on failure', function()
    local config = require('himalaya.config')
    config.setup({ telescope_preview = true })

    package.loaded['himalaya.state.account'] = {
      default = function()
        return 'test-account'
      end,
    }
    package.loaded['himalaya.domain.email'] = {
      list_with = function()
        error('connection failed')
      end,
    }

    telescope_mod.select(function() end, { { name = 'INBOX' } })

    local entry = captured_finder_opts.entry_maker({ name = 'Drafts' })
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(buffers_to_cleanup, bufnr)
    entry.preview_command(entry, bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.is_true(#lines > 0)
    assert.is_truthy(lines[1]:match('^Errors: '))
    assert.is_truthy(lines[1]:match('connection failed'))
  end)

  it('attach_mappings calls callback with selection display', function()
    local selected = nil
    telescope_mod.select(function(val)
      selected = val
    end, { { name = 'INBOX' } })

    captured_picker_opts.attach_mappings(999)
    mock_replace_fn()

    assert.are.equal('INBOX', selected)
  end)
end)
