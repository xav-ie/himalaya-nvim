describe('himalaya.ui.search', function()
  local search

  before_each(function()
    package.loaded['himalaya.ui.search'] = nil
    search = require('himalaya.ui.search')
  end)

  local function empty_values()
    local v = {}
    for i = 1, #search._FIELDS do
      v[i] = ''
    end
    return v
  end

  local function field_index(keyword_or_complete)
    for i, f in ipairs(search._FIELDS) do
      if f.keyword == keyword_or_complete or f.complete == keyword_or_complete then
        return i
      end
    end
  end

  local function segments_to_string(segs)
    local parts = {}
    for _, s in ipairs(segs) do
      parts[#parts + 1] = s.text
    end
    return table.concat(parts)
  end

  describe('negate_label', function()
    it('replaces last leading space with !', function()
      assert.are.equal('  !from: ', search._negate_label('   from: '))
    end)

    it('handles label with single leading space', function()
      assert.are.equal('!folder: ', search._negate_label(' folder: '))
    end)

    it('handles label with no leading space', function()
      assert.are.equal('!subject:', search._negate_label('subject: '))
    end)
  end)

  describe('format_condition', function()
    it('escapes spaces for quoted fields', function()
      local field = { keyword = 'subject', quote = true }
      assert.are.equal('subject hello\\ world', search._format_condition(field, 'hello world'))
    end)

    it('does not escape for non-quoted fields', function()
      local field = { keyword = 'flag' }
      assert.are.equal('flag Seen', search._format_condition(field, 'Seen'))
    end)
  end)

  describe('build_query_segments', function()
    it('returns empty for all-empty values', function()
      local segs = search._build_query_segments(empty_values(), {})
      assert.are.same({}, segs)
    end)

    it('builds single subject condition', function()
      local vals = empty_values()
      vals[field_index('subject')] = 'hello'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('subject hello', q)
    end)

    it('builds subject or body', function()
      local vals = empty_values()
      vals[field_index('subject')] = 'hello'
      vals[field_index('body')] = 'world'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('subject hello or body world', q)
    end)

    it('wraps or-group in parens when and-conditions exist', function()
      local vals = empty_values()
      vals[field_index('subject')] = 'hello'
      vals[field_index('body')] = 'world'
      vals[field_index('from')] = 'alice'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('(subject hello or body world) and from alice', q)
    end)

    it('does not wrap single or-seg in parens', function()
      local vals = empty_values()
      vals[field_index('subject')] = 'hello'
      vals[field_index('from')] = 'alice'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('subject hello and from alice', q)
    end)

    it('negates fields with not prefix', function()
      local vals = empty_values()
      vals[field_index('from')] = 'bob'
      local neg = { [field_index('from') - 1] = true }
      local q = segments_to_string(search._build_query_segments(vals, neg))
      assert.are.equal('not from bob', q)
    end)

    it('places when-preset in and-group', function()
      local vals = empty_values()
      vals[field_index('when')] = 'after 2024-01-01'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('after 2024-01-01', q)
    end)

    it('combines subject + from + when', function()
      local vals = empty_values()
      vals[field_index('subject')] = 'test'
      vals[field_index('from')] = 'alice'
      vals[field_index('when')] = 'after 2024-01-01'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('subject test and from alice and after 2024-01-01', q)
    end)

    it('handles flag field', function()
      local vals = empty_values()
      vals[field_index('flag')] = 'Seen'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('flag Seen', q)
    end)

    it('escapes spaces in subject', function()
      local vals = empty_values()
      vals[field_index('subject')] = 'hello world'
      local q = segments_to_string(search._build_query_segments(vals, {}))
      assert.are.equal('subject hello\\ world', q)
    end)
  end)

  ---------------------------------------------------------------------------
  -- Integration tests for M.open() — popup lifecycle, reactive editing,
  -- completefunc, submit, close, negation, and state restoration.
  ---------------------------------------------------------------------------
  describe('open', function()
    -- Line indices (0-based) aligned with FIELDS
    local FOLDER, SUBJECT, BODY, FROM, WHEN, FLAG, QUERY = 0, 1, 2, 3, 5, 6, 7

    before_each(function()
      package.loaded['himalaya.domain.email.flags'] = {
        complete_list = function()
          return { 'Seen', 'Flagged', 'Answered', 'Draft' }
        end,
      }
      package.loaded['himalaya.state.account'] = {
        flag = function(acct)
          return '--account ' .. (acct or '')
        end,
      }
      package.loaded['himalaya.request'] = {
        json = function(opts)
          if opts.on_data then
            opts.on_data({ { name = 'INBOX' }, { name = 'Sent' }, { name = 'Drafts' } })
          end
          return { kill = function() end }
        end,
      }
      package.loaded['himalaya.ui.search'] = nil
      search = require('himalaya.ui.search')
    end)

    after_each(function()
      vim.cmd('stopinsert')
      for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local ok, cfg = pcall(vim.api.nvim_win_get_config, winid)
        if ok and cfg.relative and cfg.relative ~= '' then
          pcall(vim.api.nvim_win_close, winid, true)
        end
      end
    end)

    local callback_result

    local function open_popup(prev_query, folder)
      callback_result = nil
      search.open(function(q, f)
        callback_result = { query = q, folder = f }
      end, prev_query, folder or 'INBOX', 'test')
    end

    --- Flush vim.schedule callbacks.
    local function flush()
      vim.wait(50, function()
        return false
      end)
    end

    local function get_line(idx)
      return vim.api.nvim_buf_get_lines(0, idx, idx + 1, false)[1] or ''
    end

    local function set_field(idx, text)
      local old = get_line(idx)
      vim.api.nvim_buf_set_text(0, idx, 0, idx, #old, { text })
    end

    local function feedkeys(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end

    -- Setup -----------------------------------------------------------

    describe('setup', function()
      it('creates a buffer with the right line count', function()
        open_popup()
        assert.are.equal(#search._FIELDS, vim.api.nvim_buf_line_count(0))
      end)

      it('pre-populates folder field', function()
        open_popup(nil, 'Sent')
        assert.are.equal('Sent', get_line(FOLDER))
      end)

      it('places cursor on subject line for fresh search', function()
        open_popup()
        assert.are.equal(SUBJECT + 1, vim.api.nvim_win_get_cursor(0)[1])
      end)

      it('registers expected keymaps', function()
        open_popup()
        local buf = vim.api.nvim_get_current_buf()
        local n_keys, i_keys = {}, {}
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
          n_keys[m.lhs] = true
        end
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'i')) do
          i_keys[m.lhs] = true
        end
        for _, k in ipairs({ '<Esc>', 'dd', '<Tab>', '<S-Tab>', '<CR>', '<C-X>' }) do
          assert.is_truthy(n_keys[k], 'n ' .. k)
        end
        for _, k in ipairs({ '<Tab>', '<S-Tab>', '<CR>', '<C-X>', '<BS>' }) do
          assert.is_truthy(i_keys[k], 'i ' .. k)
        end
      end)

      it('registers visual d and x keymaps', function()
        open_popup()
        local buf = vim.api.nvim_get_current_buf()
        local x_keys = {}
        for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'x')) do
          x_keys[m.lhs] = true
        end
        assert.is_truthy(x_keys['d'])
        assert.is_truthy(x_keys['x'])
      end)
    end)

    -- Completefunc ----------------------------------------------------

    describe('completefunc', function()
      it('completes flags on flag line', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FLAG + 1, 0 })
        assert.are.equal(0, _G._himalaya_search_completefunc(1, ''))
        local matches = _G._himalaya_search_completefunc(0, '')
        assert.are.equal(4, #matches)
      end)

      it('filters flags by prefix', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FLAG + 1, 0 })
        local matches = _G._himalaya_search_completefunc(0, 'Se')
        assert.are.equal(1, #matches)
        assert.are.equal('Seen', matches[1])
      end)

      it('completes when-presets on when line', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { WHEN + 1, 0 })
        assert.are.equal(0, _G._himalaya_search_completefunc(1, ''))
        local matches = _G._himalaya_search_completefunc(0, '')
        assert.is_true(#matches > 0)
        assert.is_not_nil(matches[1].word)
        assert.is_not_nil(matches[1].menu)
      end)

      it('completes folder names on folder line', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FOLDER + 1, 0 })
        assert.are.equal(0, _G._himalaya_search_completefunc(1, ''))
        local matches = _G._himalaya_search_completefunc(0, '')
        assert.are.equal(3, #matches)
      end)

      it('filters folders by prefix', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FOLDER + 1, 0 })
        local matches = _G._himalaya_search_completefunc(0, 'S')
        assert.are.equal(1, #matches)
        assert.are.equal('Sent', matches[1])
      end)

      it('returns -3 on non-completable line (findstart)', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FROM + 1, 0 })
        assert.are.equal(-3, _G._himalaya_search_completefunc(1, ''))
      end)

      it('returns empty on non-completable line (base)', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FROM + 1, 0 })
        local matches = _G._himalaya_search_completefunc(0, '')
        assert.are.same({}, matches)
      end)

      it('returns -3 when folder candidates not loaded', function()
        open_popup()
        pcall(vim.api.nvim_buf_del_var, 0, '_himalaya_folder_candidates')
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FOLDER + 1, 0 })
        assert.are.equal(-3, _G._himalaya_search_completefunc(1, ''))
      end)
    end)

    -- Reactive editing ------------------------------------------------

    describe('reactive editing', function()
      it('mirrors subject to body', function()
        open_popup()
        set_field(SUBJECT, 'hello')
        flush()
        assert.are.equal('hello', get_line(BODY))
      end)

      it('recomposes query from subject (body mirrored)', function()
        open_popup()
        set_field(SUBJECT, 'hello')
        flush()
        assert.are.equal('subject hello or body hello', get_line(QUERY))
      end)

      it('builds query from from-field', function()
        open_popup()
        set_field(FROM, 'alice')
        flush()
        assert.are.equal('from alice', get_line(QUERY))
      end)

      it('combines subject + from in query', function()
        open_popup()
        set_field(SUBJECT, 'test')
        flush()
        set_field(FROM, 'alice')
        flush()
        assert.are.equal('(subject test or body test) and from alice', get_line(QUERY))
      end)

      it('unlinks body after independent body edit', function()
        open_popup()
        set_field(SUBJECT, 'hello')
        flush()
        -- Edit body independently
        set_field(BODY, 'different')
        flush()
        -- Now subject edit should not mirror to body
        set_field(SUBJECT, 'changed')
        flush()
        assert.are.equal('different', get_line(BODY))
      end)

      it('re-links body when body is cleared', function()
        open_popup()
        set_field(SUBJECT, 'hello')
        flush()
        -- Unlink
        set_field(BODY, 'different')
        flush()
        -- Clear body → re-links
        set_field(BODY, '')
        flush()
        -- Body should re-mirror subject
        assert.are.equal('hello', get_line(BODY))
      end)

      it('unsubscribes query on manual query edit', function()
        open_popup()
        set_field(SUBJECT, 'test')
        flush()
        assert.are.equal('subject test or body test', get_line(QUERY))
        -- Manually edit query
        set_field(QUERY, 'custom')
        flush()
        -- Query should retain manual value (recompose skipped)
        assert.are.equal('custom', get_line(QUERY))
      end)

      it('re-subscribes query when query is cleared after manual edit', function()
        open_popup()
        set_field(SUBJECT, 'test')
        flush()
        -- Manual edit
        set_field(QUERY, 'custom')
        flush()
        -- Clear query → re-subscribes and recomposes
        set_field(QUERY, '')
        flush()
        assert.are.equal('subject test or body test', get_line(QUERY))
      end)

      it('undoes line additions to preserve structure', function()
        open_popup()
        local expected_count = vim.api.nvim_buf_line_count(0)
        -- Force a new undo block so the insertion is independently undoable
        local ul = vim.bo.undolevels
        vim.bo.undolevels = ul
        -- Insert an extra line
        vim.api.nvim_buf_set_lines(0, 1, 1, false, { 'extra' })
        flush()
        -- Should have been undone
        assert.are.equal(expected_count, vim.api.nvim_buf_line_count(0))
      end)
    end)

    -- Submit / close --------------------------------------------------

    describe('submit', function()
      it('calls callback with query and folder', function()
        open_popup(nil, 'Sent')
        set_field(SUBJECT, 'hello')
        flush()
        vim.cmd('stopinsert')
        feedkeys('<CR>')
        assert.is_not_nil(callback_result)
        assert.are.equal('subject hello or body hello', callback_result.query)
        assert.are.equal('Sent', callback_result.folder)
      end)

      it('closes the popup window', function()
        open_popup()
        vim.cmd('stopinsert')
        local win_count = #vim.api.nvim_tabpage_list_wins(0)
        feedkeys('<CR>')
        assert.are.equal(win_count - 1, #vim.api.nvim_tabpage_list_wins(0))
      end)
    end)

    describe('close', function()
      it('closes popup without calling callback', function()
        open_popup()
        vim.cmd('stopinsert')
        feedkeys('<Esc>')
        assert.is_nil(callback_result)
      end)
    end)

    -- Navigation ------------------------------------------------------

    describe('field navigation', function()
      it('Tab on non-completable line moves to next field', function()
        open_popup()
        vim.cmd('stopinsert')
        -- Start on subject (row 2, 1-based)
        vim.api.nvim_win_set_cursor(0, { SUBJECT + 1, 0 })
        feedkeys('<Tab>')
        assert.are.equal(BODY + 1, vim.api.nvim_win_get_cursor(0)[1])
      end)

      it('S-Tab moves to previous field', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { BODY + 1, 0 })
        feedkeys('<S-Tab>')
        assert.are.equal(SUBJECT + 1, vim.api.nvim_win_get_cursor(0)[1])
      end)

      it('Tab wraps from last to first field', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { QUERY + 1, 0 })
        feedkeys('<Tab>')
        assert.are.equal(FOLDER + 1, vim.api.nvim_win_get_cursor(0)[1])
      end)

      it('S-Tab wraps from first to last field', function()
        open_popup()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FOLDER + 1, 0 })
        feedkeys('<S-Tab>')
        assert.are.equal(QUERY + 1, vim.api.nvim_win_get_cursor(0)[1])
      end)
    end)

    -- Negation --------------------------------------------------------

    describe('negation', function()
      it('toggles not prefix in query via C-x', function()
        open_popup()
        set_field(FROM, 'bob')
        flush()
        assert.are.equal('from bob', get_line(QUERY))
        -- Toggle negation on the from line
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FROM + 1, 0 })
        feedkeys('<C-x>')
        assert.are.equal('not from bob', get_line(QUERY))
      end)

      it('C-x is no-op on query line', function()
        open_popup()
        set_field(SUBJECT, 'test')
        flush()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { QUERY + 1, 0 })
        local q_before = get_line(QUERY)
        feedkeys('<C-x>')
        -- Query should be unchanged
        assert.are.equal(q_before, get_line(QUERY))
      end)

      it('second C-x removes negation', function()
        open_popup()
        set_field(FROM, 'bob')
        flush()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FROM + 1, 0 })
        feedkeys('<C-x>')
        assert.are.equal('not from bob', get_line(QUERY))
        feedkeys('<C-x>')
        assert.are.equal('from bob', get_line(QUERY))
      end)
    end)

    -- State restoration -----------------------------------------------

    describe('state restoration', function()
      it('restores field values on re-open with prev_query', function()
        open_popup(nil, 'INBOX')
        set_field(SUBJECT, 'hello')
        set_field(FROM, 'alice')
        flush()
        local expected_query = get_line(QUERY)
        vim.cmd('stopinsert')
        feedkeys('<CR>')
        assert.is_not_nil(callback_result)

        -- Re-open with the previous query
        open_popup(expected_query, 'INBOX')
        assert.are.equal('hello', get_line(SUBJECT))
        assert.are.equal('alice', get_line(FROM))
        assert.are.equal(expected_query, get_line(QUERY))
      end)

      it('overrides restored folder with current folder', function()
        open_popup(nil, 'OldFolder')
        set_field(SUBJECT, 'x')
        flush()
        vim.cmd('stopinsert')
        feedkeys('<CR>')

        -- Re-open with different folder
        open_popup(callback_result.query, 'NewFolder')
        assert.are.equal('NewFolder', get_line(FOLDER))
      end)

      it('restores negation state', function()
        open_popup(nil, 'INBOX')
        set_field(FROM, 'bob')
        flush()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FROM + 1, 0 })
        feedkeys('<C-x>')
        local expected_query = get_line(QUERY)
        assert.truthy(expected_query:find('not'))
        feedkeys('<CR>')

        open_popup(expected_query, 'INBOX')
        assert.are.equal(expected_query, get_line(QUERY))
      end)

      it('places cursor from saved state', function()
        open_popup(nil, 'INBOX')
        set_field(SUBJECT, 'x')
        flush()
        vim.cmd('stopinsert')
        vim.api.nvim_win_set_cursor(0, { FROM + 1, 0 })
        feedkeys('<CR>')

        open_popup(callback_result.query, 'INBOX')
        assert.are.equal(FROM + 1, vim.api.nvim_win_get_cursor(0)[1])
      end)
    end)
  end)
end)
