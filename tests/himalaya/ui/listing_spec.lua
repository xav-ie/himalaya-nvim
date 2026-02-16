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
end)
