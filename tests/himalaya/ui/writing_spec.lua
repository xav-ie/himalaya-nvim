describe('himalaya.ui.writing', function()
  local writing
  local bufnr
  local config_stub

  local noop = function() end

  before_each(function()
    for key in pairs(package.loaded) do
      if key:match('^himalaya') then
        package.loaded[key] = nil
      end
    end

    config_stub = { keymaps = {} }
    package.loaded['himalaya.config'] = {
      get = function()
        return config_stub
      end,
    }
    package.loaded['himalaya.domain.email.compose'] = {
      send = noop,
      save_draft = noop,
      process_draft = noop,
    }
    package.loaded['himalaya.ui.win'] = {
      find_by_bufnr = function(b)
        return vim.fn.bufwinid(b)
      end,
    }

    writing = require('himalaya.ui.writing')

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_del_augroup_by_name, 'himalaya_write_' .. bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('exposes a setup function', function()
    assert.is_function(writing.setup)
  end)

  it('setup() sets filetype=mail', function()
    writing.setup(bufnr)
    assert.equals('mail', vim.bo[bufnr].filetype)
  end)

  it('setup() sets foldmethod=expr', function()
    writing.setup(bufnr)
    assert.equals('expr', vim.wo.foldmethod)
  end)

  it('setup() sets completefunc when complete_contact_cmd configured', function()
    config_stub.complete_contact_cmd = 'some-command'
    writing.setup(bufnr)
    assert.equals("v:lua.require'himalaya.domain.email'.complete_contact", vim.bo[bufnr].completefunc)
  end)

  it('setup() does not set completefunc when config has no complete_contact_cmd', function()
    writing.setup(bufnr)
    assert.equals('', vim.bo[bufnr].completefunc)
  end)

  it('setup() sets winbar with account context', function()
    vim.b[bufnr].himalaya_account = 'personal'
    vim.api.nvim_buf_set_name(bufnr, 'Himalaya/reply [42]')
    writing.setup(bufnr)
    local winid = vim.fn.bufwinid(bufnr)
    assert.is_truthy(vim.wo[winid].winbar:find('%[personal%]'))
    assert.is_truthy(vim.wo[winid].winbar:find('reply'))
  end)

  it('setup() creates BufWriteCmd, BufLeave, and BufHidden autocmds', function()
    writing.setup(bufnr)
    local autocmds = vim.api.nvim_get_autocmds({ group = 'himalaya_write_' .. bufnr })
    local events = {}
    for _, au in ipairs(autocmds) do
      events[au.event] = true
    end
    assert.is_not_nil(events['BufWriteCmd'])
    assert.is_not_nil(events['BufLeave'])
    assert.is_not_nil(events['BufHidden'])
  end)

  it('setup() detects forward kind from buffer name', function()
    vim.b[bufnr].himalaya_account = 'work'
    vim.api.nvim_buf_set_name(bufnr, 'Himalaya/forward [99]')
    writing.setup(bufnr)
    local winid = vim.fn.bufwinid(bufnr)
    assert.is_truthy(vim.wo[winid].winbar:find('forward'))
  end)

  it('BufWriteCmd autocmd calls compose.send', function()
    local send_called_with = nil
    package.loaded['himalaya.domain.email.compose'] = {
      send = function(b)
        send_called_with = b
      end,
      save_draft = noop,
      process_draft = noop,
    }
    package.loaded['himalaya.ui.writing'] = nil
    writing = require('himalaya.ui.writing')
    writing.setup(bufnr)
    -- set modified so BufWriteCmd triggers properly
    vim.bo[bufnr].modified = true
    vim.api.nvim_exec_autocmds('BufWriteCmd', { buffer = bufnr })
    assert.are.equal(bufnr, send_called_with)
  end)

  it('BufLeave autocmd calls compose.save_draft', function()
    local draft_saved = false
    package.loaded['himalaya.domain.email.compose'] = {
      send = noop,
      save_draft = function()
        draft_saved = true
      end,
      process_draft = noop,
    }
    package.loaded['himalaya.ui.writing'] = nil
    writing = require('himalaya.ui.writing')
    writing.setup(bufnr)
    vim.api.nvim_exec_autocmds('BufLeave', { buffer = bufnr })
    assert.is_true(draft_saved)
  end)

  it('BufHidden autocmd calls compose.process_draft with buffer', function()
    local process_buf = nil
    package.loaded['himalaya.domain.email.compose'] = {
      send = noop,
      save_draft = noop,
      process_draft = function(b)
        process_buf = b
      end,
    }
    package.loaded['himalaya.ui.writing'] = nil
    writing = require('himalaya.ui.writing')
    writing.setup(bufnr)
    vim.api.nvim_exec_autocmds('BufHidden', { buffer = bufnr })
    assert.are.equal(bufnr, process_buf)
  end)
end)
