describe('himalaya.pickers.telescope', function()
  local telescope_mod
  local captured_finder_opts
  local captured_picker_opts
  local mock_replace_fn

  before_each(function()
    package.loaded['himalaya.pickers.telescope'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['telescope.actions'] = nil
    package.loaded['telescope.actions.state'] = nil
    package.loaded['telescope.finders'] = nil
    package.loaded['telescope.pickers'] = nil
    package.loaded['telescope.sorters'] = nil
    package.loaded['telescope.previewers'] = nil

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

  it('entry_maker produces name-based fields', function()
    telescope_mod.select(function() end, { { name = 'INBOX' } })

    local entry = captured_finder_opts.entry_maker({ name = 'Sent' })
    assert.are.equal('Sent', entry.value)
    assert.are.equal('Sent', entry.display)
    assert.are.equal('Sent', entry.ordinal)
  end)

  it('sets previewer when telescope_preview is enabled', function()
    local config = require('himalaya.config')
    config.setup({ telescope_preview = true })

    telescope_mod.select(function() end, { { name = 'INBOX' } })

    assert.is_not_nil(captured_picker_opts.previewer)
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
