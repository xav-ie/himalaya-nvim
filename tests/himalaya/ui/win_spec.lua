describe('himalaya.ui.win', function()
  local win

  before_each(function()
    package.loaded['himalaya.ui.win'] = nil
    win = require('himalaya.ui.win')
  end)

  describe('find_by_name', function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, 'himalaya://test-mailbox/INBOX')
      vim.api.nvim_set_current_buf(buf)
    end)

    after_each(function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it('returns winid when buffer name contains the pattern', function()
      local winid = win.find_by_name('test-mailbox')
      assert.are.equal(vim.api.nvim_get_current_win(), winid)
    end)

    it('matches a substring anywhere in the buffer name', function()
      local winid = win.find_by_name('INBOX')
      assert.are.equal(vim.api.nvim_get_current_win(), winid)
    end)

    it('returns nil when no buffer name matches', function()
      local winid = win.find_by_name('nonexistent-pattern')
      assert.is_nil(winid)
    end)
  end)

  describe('find_by_buftype', function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
    end)

    after_each(function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it('returns winid, bufnr, and type when buffer has matching type', function()
      vim.api.nvim_buf_set_var(buf, 'himalaya_buffer_type', 'email-listing')
      local winid, bufnr, bt = win.find_by_buftype('email-listing')
      assert.are.equal(vim.api.nvim_get_current_win(), winid)
      assert.are.equal(buf, bufnr)
      assert.are.equal('email-listing', bt)
    end)

    it('accepts a table of types and matches the first hit', function()
      vim.api.nvim_buf_set_var(buf, 'himalaya_buffer_type', 'email-reading')
      local winid, bufnr, bt = win.find_by_buftype({ 'email-listing', 'email-reading' })
      assert.are.equal(vim.api.nvim_get_current_win(), winid)
      assert.are.equal(buf, bufnr)
      assert.are.equal('email-reading', bt)
    end)

    it('returns nil when no buffer has a matching type', function()
      vim.api.nvim_buf_set_var(buf, 'himalaya_buffer_type', 'email-writing')
      local winid = win.find_by_buftype('email-listing')
      assert.is_nil(winid)
    end)

    it('returns nil when no buffer has the variable set', function()
      local winid = win.find_by_buftype('email-listing')
      assert.is_nil(winid)
    end)
  end)

  describe('find_by_bufnr', function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
    end)

    after_each(function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it('returns winid when buffer is displayed in current tabpage', function()
      local winid = win.find_by_bufnr(buf)
      assert.are.equal(vim.api.nvim_get_current_win(), winid)
    end)

    it('returns nil for a buffer not displayed in any window', function()
      local hidden = vim.api.nvim_create_buf(false, true)
      local winid = win.find_by_bufnr(hidden)
      assert.is_nil(winid)
      vim.api.nvim_buf_delete(hidden, { force = true })
    end)
  end)
end)
