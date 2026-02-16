describe('himalaya.config', function()
  local config

  before_each(function()
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
  end)

  it('returns defaults when setup not called', function()
    local c = config.get()
    assert.are.equal('himalaya', c.executable)
    assert.is_nil(c.config_path)
    assert.is_nil(c.folder_picker)
    assert.are.equal(false, c.telescope_preview)
    assert.is_nil(c.complete_contact_cmd)
    assert.are.same({}, c.custom_flags)
    assert.are.equal(true, c.always_confirm)
  end)

  it('deep merges user overrides', function()
    config.setup({ executable = '/usr/bin/himalaya', always_confirm = false })
    local c = config.get()
    assert.are.equal('/usr/bin/himalaya', c.executable)
    assert.are.equal(false, c.always_confirm)
    assert.are.same({}, c.custom_flags)
  end)

  it('merges custom_flags correctly', function()
    config.setup({ custom_flags = { 'important', 'urgent' } })
    local c = config.get()
    assert.are.same({ 'important', 'urgent' }, c.custom_flags)
  end)
end)
