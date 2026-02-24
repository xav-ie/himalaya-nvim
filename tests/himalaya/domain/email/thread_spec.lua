describe('himalaya.domain.email.thread', function()
  local thread = require('himalaya.domain.email.thread')

  it('returns truthy for lines starting with >', function()
    assert.is_truthy(thread.fold('> quoted text'))
    assert.is_truthy(thread.fold('>> double quoted'))
  end)

  it('returns falsy for lines not starting with >', function()
    assert.is_falsy(thread.fold('normal text'))
    assert.is_falsy(thread.fold(''))
    assert.is_falsy(thread.fold('  > indented quote'))
  end)
end)
