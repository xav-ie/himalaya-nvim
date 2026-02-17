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
    assert.is_truthy(vim.tbl_contains(result, 'Seen'))
    assert.is_truthy(vim.tbl_contains(result, 'Answered'))
    assert.is_truthy(vim.tbl_contains(result, 'Flagged'))
    assert.is_truthy(vim.tbl_contains(result, 'Deleted'))
    assert.is_truthy(vim.tbl_contains(result, 'Drafts'))
  end)

  it('includes custom flags from config', function()
    config.setup({ custom_flags = { 'Important', 'Urgent' } })
    local result = flags.complete_list()
    assert.is_truthy(vim.tbl_contains(result, 'Important'))
    assert.is_truthy(vim.tbl_contains(result, 'Urgent'))
    assert.is_truthy(vim.tbl_contains(result, 'Seen'))
  end)
end)
