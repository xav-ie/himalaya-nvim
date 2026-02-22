describe('himalaya.ui.search', function()
  local search

  before_each(function()
    package.loaded['himalaya.ui.search'] = nil
    search = require('himalaya.ui.search')
  end)

  -- Helper: build an empty values array aligned with FIELDS
  local function empty_values()
    local v = {}
    for i = 1, #search._FIELDS do
      v[i] = ''
    end
    return v
  end

  -- Helper: find the 1-based FIELDS index for a given keyword or complete type
  local function field_index(keyword_or_complete)
    for i, f in ipairs(search._FIELDS) do
      if f.keyword == keyword_or_complete or f.complete == keyword_or_complete then
        return i
      end
    end
  end

  -- Helper: join segments into a plain string
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
end)
