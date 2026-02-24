describe('himalaya.domain.email.cache', function()
  local cache

  before_each(function()
    for k in pairs(package.loaded) do
      if k:match('^himalaya') then
        package.loaded[k] = nil
      end
    end
    cache = require('himalaya.domain.email.cache')
  end)

  --- Generate a list of envelope stubs.
  local function make_envelopes(start_id, count)
    local envs = {}
    for i = 0, count - 1 do
      table.insert(envs, {
        id = tostring(start_id + i),
        flags = { 'Seen' },
        subject = 'Subject ' .. (start_id + i),
      })
    end
    return envs
  end

  describe('merge', function()
    it('returns new as-is when old is nil', function()
      local new = make_envelopes(1, 5)
      local merged, offset = cache.merge(nil, 0, new, 0)
      assert.are.same(new, merged)
      assert.are.equal(0, offset)
    end)

    it('returns new as-is when old is empty', function()
      local new = make_envelopes(1, 5)
      local merged, offset = cache.merge({}, 0, new, 0)
      assert.are.same(new, merged)
      assert.are.equal(0, offset)
    end)

    it('merges contiguous forward (page 1 + page 2)', function()
      local old = make_envelopes(1, 5) -- offset 0, covers 0..4
      local new = make_envelopes(6, 5) -- offset 5, covers 5..9
      local merged, offset = cache.merge(old, 0, new, 5)
      assert.are.equal(0, offset)
      assert.are.equal(10, #merged)
      assert.are.equal('1', merged[1].id)
      assert.are.equal('5', merged[5].id)
      assert.are.equal('6', merged[6].id)
      assert.are.equal('10', merged[10].id)
    end)

    it('merges contiguous backward (page 2 + page 1)', function()
      local old = make_envelopes(6, 5) -- offset 5, covers 5..9
      local new = make_envelopes(1, 5) -- offset 0, covers 0..4
      local merged, offset = cache.merge(old, 5, new, 0)
      assert.are.equal(0, offset)
      assert.are.equal(10, #merged)
      assert.are.equal('1', merged[1].id)
      assert.are.equal('6', merged[6].id)
      assert.are.equal('10', merged[10].id)
    end)

    it('merges overlapping ranges with new data winning', function()
      local old = make_envelopes(1, 5) -- offset 0, covers 0..4
      -- New envelopes overlap at positions 3-4 and extend to 7
      local new = make_envelopes(101, 5) -- offset 3, covers 3..7
      local merged, offset = cache.merge(old, 0, new, 3)
      assert.are.equal(0, offset)
      assert.are.equal(8, #merged)
      -- Old data preserved for non-overlapping region
      assert.are.equal('1', merged[1].id)
      assert.are.equal('3', merged[3].id)
      -- New data wins in overlap zone (positions 3-4)
      assert.are.equal('101', merged[4].id)
      assert.are.equal('102', merged[5].id)
      -- New data fills extension
      assert.are.equal('105', merged[8].id)
    end)

    it('replaces with new data on exact same range (re-fetch)', function()
      local old = make_envelopes(1, 5) -- offset 0, covers 0..4
      local new = make_envelopes(101, 5) -- offset 0, covers 0..4
      local merged, offset = cache.merge(old, 0, new, 0)
      assert.are.equal(0, offset)
      assert.are.equal(5, #merged)
      -- New data replaces entirely
      assert.are.equal('101', merged[1].id)
      assert.are.equal('105', merged[5].id)
    end)

    it('returns new only when disjoint (gap)', function()
      local old = make_envelopes(1, 5) -- offset 0, covers 0..4
      local new = make_envelopes(11, 5) -- offset 10, covers 10..14 (gap at 5-9)
      local merged, offset = cache.merge(old, 0, new, 10)
      assert.are.same(new, merged)
      assert.are.equal(10, offset)
    end)

    it('new data overwrites flags in overlap', function()
      local old = make_envelopes(1, 3) -- offset 0
      old[3].flags = { 'Seen' }
      -- New data for same region but with updated flags
      local new = make_envelopes(3, 2) -- offset 2, overlaps at position 2
      new[1].flags = { 'Seen', 'Flagged' }
      local merged, _ = cache.merge(old, 0, new, 2)
      assert.are.equal(4, #merged)
      -- Position 3 (index 3) should have new flags
      assert.are.same({ 'Seen', 'Flagged' }, merged[3].flags)
    end)
  end)
end)
