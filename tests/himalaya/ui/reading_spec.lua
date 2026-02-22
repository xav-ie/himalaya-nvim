describe('himalaya.ui.reading', function()
  local reading
  local bufnr

  local noop = function() end

  before_each(function()
    for key in pairs(package.loaded) do
      if key:match('^himalaya') then
        package.loaded[key] = nil
      end
    end

    package.loaded['himalaya.domain.email'] = {
      download_attachments = noop,
      select_folder_then_copy = noop,
      select_folder_then_move = noop,
      delete = noop,
      open_browser = noop,
      read = noop,
    }
    package.loaded['himalaya.domain.email.compose'] = {
      write = noop,
      reply = noop,
      reply_all = noop,
      forward = noop,
    }
    package.loaded['himalaya.ui.win'] = {
      find_by_buftype = noop,
    }
    package.loaded['himalaya.config'] = {
      get = function()
        return { keymaps = {} }
      end,
    }

    reading = require('himalaya.ui.reading')

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('exposes a setup function', function()
    assert.is_function(reading.setup)
  end)

  it('setup() sets buffer options', function()
    reading.setup(bufnr)
    assert.equals('wipe', vim.bo[bufnr].bufhidden)
    assert.equals('nofile', vim.bo[bufnr].buftype)
    assert.equals('mail', vim.bo[bufnr].filetype)
    assert.is_false(vim.bo[bufnr].modifiable)
  end)

  it('setup() sets foldmethod=expr', function()
    reading.setup(bufnr)
    assert.equals('expr', vim.wo.foldmethod)
  end)

  it('setup() registers reading keybinds', function()
    reading.setup(bufnr)
    local maps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
    local expected_keys = { 'gw', 'gr', 'gR', 'gf', 'ga', 'gC', 'gM', 'gD', 'go', 'gn', 'gp', '?' }
    for _, key in ipairs(expected_keys) do
      local found = false
      for _, map in ipairs(maps) do
        if map.lhs == key then
          found = true
          break
        end
      end
      assert.is_true(found, 'expected keybind ' .. key .. ' to be registered')
    end
  end)

  it('setup() registers exactly 12 normal-mode keybinds', function()
    reading.setup(bufnr)
    local maps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
    local count = 0
    for _, map in ipairs(maps) do
      if map.desc and map.desc:find('^Himalaya:') then
        count = count + 1
      end
    end
    assert.equals(12, count)
  end)
end)
