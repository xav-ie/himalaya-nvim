describe('himalaya.pickers.init', function()
  before_each(function()
    package.loaded['himalaya.pickers.init'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['telescope'] = nil
    package.loaded['fzf-lua'] = nil

    local config = require('himalaya.config')
    config._reset()
  end)

  describe('detect()', function()
    it('returns config override when folder_picker is set', function()
      local config = require('himalaya.config')
      config.setup({ folder_picker = 'fzf' })

      local pickers = require('himalaya.pickers.init')
      assert.are.equal('fzf', pickers.detect())
    end)

    it('detects telescope when available', function()
      package.loaded['telescope'] = {}

      local pickers = require('himalaya.pickers.init')
      assert.are.equal('telescope', pickers.detect())
    end)

    it('detects fzf-lua when only fzf-lua is available', function()
      package.loaded['fzf-lua'] = {}

      local pickers = require('himalaya.pickers.init')
      assert.are.equal('fzflua', pickers.detect())
    end)

    it('detects fzf when only fzf#run is available', function()
      local orig_exists = vim.fn.exists
      vim.fn.exists = function(name)
        if name == '*fzf#run' then
          return 1
        end
        return orig_exists(name)
      end

      local pickers = require('himalaya.pickers.init')
      local result = pickers.detect()
      vim.fn.exists = orig_exists

      assert.are.equal('fzf', result)
    end)

    it('falls back to native when nothing is available', function()
      local orig_exists = vim.fn.exists
      vim.fn.exists = function(name)
        if name == '*fzf#run' then
          return 0
        end
        return orig_exists(name)
      end

      local pickers = require('himalaya.pickers.init')
      local result = pickers.detect()
      vim.fn.exists = orig_exists

      assert.are.equal('native', result)
    end)
  end)

  describe('select()', function()
    it('delegates to the detected picker module', function()
      package.loaded['telescope'] = {}
      local called = false
      package.loaded['himalaya.pickers.telescope'] = {
        select = function()
          called = true
        end,
      }

      local pickers = require('himalaya.pickers.init')
      pickers.select(function() end, { { name = 'INBOX' } })

      assert.is_true(called)
    end)

    it('respects config override for picker selection', function()
      local config = require('himalaya.config')
      config.setup({ folder_picker = 'fzf' })

      local called = false
      package.loaded['himalaya.pickers.fzf'] = {
        select = function()
          called = true
        end,
      }

      local pickers = require('himalaya.pickers.init')
      pickers.select(function() end, { { name = 'INBOX' } })

      assert.is_true(called)
    end)
  end)
end)
