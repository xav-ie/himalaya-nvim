describe('himalaya.domain.folder', function()
  local folder_domain
  local folder_state

  before_each(function()
    package.loaded['himalaya.domain.folder'] = nil
    package.loaded['himalaya.state.folder'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.config'] = nil
    require('himalaya.config')._reset()
    folder_domain = require('himalaya.domain.folder')
    folder_state = require('himalaya.state.folder')
  end)

  it('exposes open_picker, select, and set functions', function()
    assert.is_function(folder_domain.open_picker)
    assert.is_function(folder_domain.select)
    assert.is_function(folder_domain.set)
  end)

  it('set updates folder state', function()
    folder_state.set('Sent')
    assert.are.equal('Sent', folder_state.current())
    assert.are.equal(1, folder_state.current_page())
  end)
end)
