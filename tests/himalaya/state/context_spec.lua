describe('himalaya.state.context', function()
  local context

  before_each(function()
    package.loaded['himalaya.state.context'] = nil
    package.loaded['himalaya.ui.win'] = nil

    -- Default: no listing buffer found
    package.loaded['himalaya.ui.win'] = {
      find_by_buftype = function()
        return nil, nil, nil
      end,
    }

    context = require('himalaya.state.context')

    vim.b.himalaya_account = nil
    vim.b.himalaya_folder = nil
  end)

  describe('resolve', function()
    it('returns buffer vars when set', function()
      vim.b.himalaya_account = 'work'
      vim.b.himalaya_folder = 'Sent'
      local account, folder = context.resolve()
      assert.are.equal('work', account)
      assert.are.equal('Sent', folder)
    end)

    it('falls back to listing buffer in current tab', function()
      local listing_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(listing_buf, 'himalaya_account', 'personal')
      vim.api.nvim_buf_set_var(listing_buf, 'himalaya_folder', 'Drafts')

      package.loaded['himalaya.ui.win'] = {
        find_by_buftype = function()
          return vim.api.nvim_get_current_win(), listing_buf, 'listing'
        end,
      }

      local account, folder = context.resolve()
      assert.are.equal('personal', account)
      assert.are.equal('Drafts', folder)

      vim.api.nvim_buf_delete(listing_buf, { force = true })
    end)

    it('falls back to defaults when nothing is set', function()
      local account, folder = context.resolve()
      assert.are.equal('', account)
      assert.are.equal('INBOX', folder)
    end)

    it('uses buffer account but falls back to listing folder', function()
      vim.b.himalaya_account = 'work'

      local listing_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(listing_buf, 'himalaya_account', 'personal')
      vim.api.nvim_buf_set_var(listing_buf, 'himalaya_folder', 'Archive')

      package.loaded['himalaya.ui.win'] = {
        find_by_buftype = function()
          return vim.api.nvim_get_current_win(), listing_buf, 'listing'
        end,
      }

      local account, folder = context.resolve()
      assert.are.equal('work', account)
      assert.are.equal('Archive', folder)

      vim.api.nvim_buf_delete(listing_buf, { force = true })
    end)
  end)

  describe('stamp', function()
    it('sets both vars on the buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      context.stamp(buf, 'acct', 'Trash')
      assert.are.equal('acct', vim.b[buf].himalaya_account)
      assert.are.equal('Trash', vim.b[buf].himalaya_folder)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
