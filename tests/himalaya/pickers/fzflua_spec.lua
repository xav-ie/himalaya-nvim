describe('himalaya.pickers.fzflua', function()
  local fzflua_picker
  local fzf_exec_called_with

  before_each(function()
    package.loaded['himalaya.pickers.fzflua'] = nil
    package.loaded['fzf-lua'] = nil
    fzf_exec_called_with = nil

    package.loaded['fzf-lua'] = {
      fzf_exec = function(items, opts)
        fzf_exec_called_with = { items = items, opts = opts }
      end,
    }

    fzflua_picker = require('himalaya.pickers.fzflua')
  end)

  it('calls fzf_exec with folder names and prompt', function()
    local folders = {
      { name = 'INBOX' },
      { name = 'Sent' },
    }
    fzflua_picker.select(function() end, folders)

    assert.is_not_nil(fzf_exec_called_with)
    assert.are.same({ 'INBOX', 'Sent' }, fzf_exec_called_with.items)
    assert.are.equal('Folders> ', fzf_exec_called_with.opts.prompt)
  end)

  it('default action unwraps selected[1] and calls callback', function()
    local selected = nil
    fzflua_picker.select(function(val)
      selected = val
    end, { { name = 'INBOX' } })

    fzf_exec_called_with.opts.actions['default']({ 'Sent' })
    assert.are.equal('Sent', selected)
  end)
end)
