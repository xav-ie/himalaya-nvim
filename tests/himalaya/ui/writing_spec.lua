describe('himalaya.ui.writing', function()
  local writing

  before_each(function()
    package.loaded['himalaya.ui.writing'] = nil
    writing = require('himalaya.ui.writing')
  end)

  it('exposes a setup function', function()
    assert.is_function(writing.setup)
  end)
end)
