describe('himalaya.keybinds', function()
  local keybinds = require('himalaya.keybinds')

  it('defines buffer-local keymaps', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)

    local called = false
    keybinds.define(buf, {
      { 'n', 'gx', function() called = true end, 'test-action' },
    })

    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local found = false
    for _, map in ipairs(maps) do
      if map.lhs == 'gx' then
        found = true
        break
      end
    end
    assert.is_true(found)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
