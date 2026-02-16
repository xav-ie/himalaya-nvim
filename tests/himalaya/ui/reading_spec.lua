describe('himalaya.ui.reading', function()
  local reading

  before_each(function()
    package.loaded['himalaya.ui.reading'] = nil
    reading = require('himalaya.ui.reading')
  end)

  it('exposes a setup function', function()
    assert.is_function(reading.setup)
  end)
end)
