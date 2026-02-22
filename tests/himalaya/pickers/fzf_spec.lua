describe('himalaya.pickers.fzf', function()
  local fzf

  before_each(function()
    package.loaded['himalaya.pickers.fzf'] = nil
    fzf = require('himalaya.pickers.fzf')
  end)

  it('extracts folder names and calls fzf#run with expected options', function()
    local called_with = nil
    vim.fn['fzf#run'] = function(opts)
      called_with = opts
    end

    local folders = {
      { name = 'INBOX' },
      { name = 'Sent' },
      { name = 'Drafts' },
    }
    fzf.select(function() end, folders)

    assert.is_not_nil(called_with)
    assert.are.same({ 'INBOX', 'Sent', 'Drafts' }, called_with.source)
    assert.are.equal('25%', called_with.down)
    assert.is_function(called_with.sink)
  end)

  it('passes callback as sink so fzf selection reaches caller', function()
    local selected = nil
    vim.fn['fzf#run'] = function(opts)
      opts.sink('Sent')
    end

    fzf.select(function(val)
      selected = val
    end, { { name = 'INBOX' }, { name = 'Sent' } })

    assert.are.equal('Sent', selected)
  end)
end)
