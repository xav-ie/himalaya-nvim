describe('himalaya.domain.folder', function()
  local folder_domain
  local folder_state

  before_each(function()
    package.loaded['himalaya.domain.folder'] = nil
    package.loaded['himalaya.state.folder'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.config'] = nil
    require('himalaya.config')._reset()
    folder_domain = require('himalaya.domain.folder')
    folder_state = require('himalaya.state.folder')
  end)

  it('exposes open_picker, select, and set functions', function()
    assert.is_function(folder_domain.open_picker)
    assert.is_function(folder_domain.select)
    assert.is_function(folder_domain.set)
  end)

  it('set updates folder state', function()
    folder_state.set('Sent')
    assert.are.equal('Sent', folder_state.current())
    assert.are.equal(1, folder_state.current_page())
  end)

  describe('select_previous_page', function()
    it('shows warning on first page', function()
      local cmds = {}
      local orig_cmd = vim.cmd
      vim.cmd = function(s)
        table.insert(cmds, s)
      end
      folder_domain.select_previous_page()
      vim.cmd = orig_cmd
      assert.are.equal(1, #cmds)
      assert.is_truthy(cmds[1]:find('Already on first page'))
    end)
  end)

  describe('select_next_page', function()
    it('shows warning when page is partial', function()
      -- Simulate a listing buffer with page_size set and fewer lines than page_size
      vim.b.himalaya_page_size = 20
      local orig_count = vim.api.nvim_buf_line_count
      vim.api.nvim_buf_line_count = function()
        return 10
      end

      local cmds = {}
      local orig_cmd = vim.cmd
      vim.cmd = function(s)
        table.insert(cmds, s)
      end
      folder_domain.select_next_page()
      vim.cmd = orig_cmd
      vim.api.nvim_buf_line_count = orig_count
      vim.b.himalaya_page_size = nil

      assert.are.equal(1, #cmds)
      assert.is_truthy(cmds[1]:find('Already on last page'))
    end)

    it('does nothing without page_size', function()
      vim.b.himalaya_page_size = nil
      local cmds = {}
      local orig_cmd = vim.cmd
      vim.cmd = function(s)
        table.insert(cmds, s)
      end
      folder_domain.select_next_page()
      vim.cmd = orig_cmd
      assert.are.equal(0, #cmds)
    end)
  end)
end)
