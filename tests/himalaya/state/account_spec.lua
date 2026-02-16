describe('himalaya.state.account', function()
  local account

  before_each(function()
    package.loaded['himalaya.state.account'] = nil
    account = require('himalaya.state.account')
  end)

  it('defaults to empty string', function()
    assert.are.equal('', account.current())
  end)

  it('stores selected account', function()
    account.select('work')
    assert.are.equal('work', account.current())
  end)

  it('can switch accounts', function()
    account.select('work')
    account.select('personal')
    assert.are.equal('personal', account.current())
  end)
end)
