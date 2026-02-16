describe('himalaya.state.folder', function()
  local folder

  before_each(function()
    package.loaded['himalaya.state.folder'] = nil
    folder = require('himalaya.state.folder')
  end)

  it('defaults to INBOX', function()
    assert.are.equal('INBOX', folder.current())
  end)

  it('defaults to page 1', function()
    assert.are.equal(1, folder.current_page())
  end)

  it('sets folder and resets page', function()
    folder.next_page()
    folder.set('Sent')
    assert.are.equal('Sent', folder.current())
    assert.are.equal(1, folder.current_page())
  end)

  it('increments page', function()
    folder.next_page()
    assert.are.equal(2, folder.current_page())
    folder.next_page()
    assert.are.equal(3, folder.current_page())
  end)

  it('decrements page but not below 1', function()
    folder.next_page()
    folder.next_page()
    assert.are.equal(3, folder.current_page())
    folder.previous_page()
    assert.are.equal(2, folder.current_page())
    folder.previous_page()
    assert.are.equal(1, folder.current_page())
    folder.previous_page()
    assert.are.equal(1, folder.current_page())
  end)
end)
