describe('himalaya.domain.email.flags', function()
  local flags
  local config

  before_each(function()
    package.loaded['himalaya.domain.email.flags'] = nil
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
    flags = require('himalaya.domain.email.flags')
  end)

  it('returns default flags', function()
    local result = flags.complete_list()
    assert.is_truthy(vim.tbl_contains(result, 'seen'))
    assert.is_truthy(vim.tbl_contains(result, 'answered'))
    assert.is_truthy(vim.tbl_contains(result, 'flagged'))
    assert.is_truthy(vim.tbl_contains(result, 'deleted'))
    assert.is_truthy(vim.tbl_contains(result, 'drafts'))
  end)

  it('includes custom flags from config', function()
    config.setup({ custom_flags = { 'important', 'urgent' } })
    local result = flags.complete_list()
    assert.is_truthy(vim.tbl_contains(result, 'important'))
    assert.is_truthy(vim.tbl_contains(result, 'urgent'))
    assert.is_truthy(vim.tbl_contains(result, 'seen'))
  end)
end)
