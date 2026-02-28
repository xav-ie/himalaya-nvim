describe('himalaya.domain.email.flags', function()
  local flags
  local config

  before_each(function()
    package.loaded['himalaya.domain.email.flags'] = nil
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
    flags = require('himalaya.domain.email.flags')
  end)

  it('returns default flags', function()
    local result = flags.complete_list()
    assert.is_truthy(vim.tbl_contains(result, 'Seen'))
    assert.is_truthy(vim.tbl_contains(result, 'Answered'))
    assert.is_truthy(vim.tbl_contains(result, 'Flagged'))
    assert.is_truthy(vim.tbl_contains(result, 'Deleted'))
    assert.is_truthy(vim.tbl_contains(result, 'Draft'))
  end)

  it('includes custom flags from config', function()
    config.setup({ custom_flags = { 'Important', 'Urgent' } })
    local result = flags.complete_list()
    assert.is_truthy(vim.tbl_contains(result, 'Important'))
    assert.is_truthy(vim.tbl_contains(result, 'Urgent'))
    assert.is_truthy(vim.tbl_contains(result, 'Seen'))
  end)

  describe('is_unseen', function()
    it('returns false when flags is nil (unknown state)', function()
      assert.is_false(flags.is_unseen({}))
    end)

    it('returns true when Seen flag is absent', function()
      assert.is_true(flags.is_unseen({ flags = { 'Answered' } }))
    end)

    it('returns false when Seen flag is present', function()
      assert.is_false(flags.is_unseen({ flags = { 'Seen' } }))
    end)

    it('returns false when Seen is among multiple flags', function()
      assert.is_false(flags.is_unseen({ flags = { 'Answered', 'Seen', 'Flagged' } }))
    end)
  end)

  describe('is_seen', function()
    it('returns false when flags is nil', function()
      assert.is_false(flags.is_seen({}))
    end)

    it('returns true when Seen flag is present', function()
      assert.is_true(flags.is_seen({ flags = { 'Seen' } }))
    end)
  end)

  describe('count_unseen', function()
    it('counts envelopes without Seen flag', function()
      local envelopes = {
        { flags = { 'Seen' } },
        { flags = { 'Answered' } },
        {},
        { flags = { 'Seen', 'Flagged' } },
      }
      assert.equals(2, flags.count_unseen(envelopes))
    end)

    it('returns 0 for empty list', function()
      assert.equals(0, flags.count_unseen({}))
    end)
  end)

  describe('count_unseen_rows', function()
    it('counts rows whose .env lacks Seen flag', function()
      local rows = {
        { env = { flags = { 'Seen' } } },
        { env = { flags = { 'Answered' } } },
        { env = {} },
        { env = { flags = { 'Seen', 'Flagged' } } },
      }
      assert.equals(2, flags.count_unseen_rows(rows))
    end)

    it('returns 0 for empty list', function()
      assert.equals(0, flags.count_unseen_rows({}))
    end)
  end)
end)
