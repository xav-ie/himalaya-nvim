describe('himalaya.pickers.native', function()
  local native = require('himalaya.pickers.native')

  it('exposes a select function', function()
    assert.is_function(native.select)
  end)

  it('calls vim.ui.select with folder names', function()
    local select_called_with = {}
    local orig = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      select_called_with = { items = items, opts = opts }
      on_choice('Sent')
    end

    local selected = nil
    local folders = {
      { name = 'INBOX' },
      { name = 'Sent' },
      { name = 'Drafts' },
    }
    native.select(function(folder) selected = folder end, folders)

    vim.ui.select = orig

    assert.are.same({ 'INBOX', 'Sent', 'Drafts' }, select_called_with.items)
    assert.are.equal('Sent', selected)
  end)

  it('does nothing when selection is nil (cancelled)', function()
    local orig = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      on_choice(nil)
    end

    local selected = nil
    native.select(function(folder) selected = folder end, { { name = 'INBOX' } })

    vim.ui.select = orig
    assert.is_nil(selected)
  end)
end)
