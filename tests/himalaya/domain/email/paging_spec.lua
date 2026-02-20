describe('himalaya.domain.email.paging', function()
  local paging

  before_each(function()
    package.loaded['himalaya.domain.email.paging'] = nil
    paging = require('himalaya.domain.email.paging')
  end)

  describe('fetch_page_slice', function()
    local data = {}
    for i = 1, 20 do data[i] = { id = tostring(i) } end

    it('returns full data when it fits in one page', function()
      local small = { { id = '1' }, { id = '2' } }
      local result = paging.fetch_page_slice(small, 1, 10, 0)
      assert.are.same(small, result)
    end)

    it('extracts first half for odd page from double fetch', function()
      local result = paging.fetch_page_slice(data, 1, 10, 0)
      assert.are.equal(10, #result)
      assert.are.equal('1', result[1].id)
      assert.are.equal('10', result[10].id)
    end)

    it('extracts second half for even page from double fetch', function()
      local result = paging.fetch_page_slice(data, 2, 10, 0)
      assert.are.equal(10, #result)
      assert.are.equal('11', result[1].id)
      assert.are.equal('20', result[10].id)
    end)

    it('handles offset fetch correctly', function()
      local result = paging.fetch_page_slice(data, 3, 10, 20)
      assert.are.equal(10, #result)
      assert.are.equal('1', result[1].id)
    end)

    it('handles partial last page', function()
      local partial = {}
      for i = 1, 5 do partial[i] = { id = tostring(i) } end
      local result = paging.fetch_page_slice(partial, 1, 10, 0)
      assert.are.same(partial, result)
    end)
  end)

  describe('cache_slice', function()
    local items = {}
    for i = 1, 30 do items[i] = { id = tostring(i) } end

    it('returns full array when it is the exact page', function()
      local small = { { id = '1' }, { id = '2' } }
      local result = paging.cache_slice(small, 1, 2, 0)
      assert.are.same(small, result)
    end)

    it('extracts page 1 from larger cache', function()
      local result = paging.cache_slice(items, 1, 10, 0)
      assert.are.equal(10, #result)
      assert.are.equal('1', result[1].id)
      assert.are.equal('10', result[10].id)
    end)

    it('extracts page 2 from cache starting at 0', function()
      local result = paging.cache_slice(items, 2, 10, 0)
      assert.are.equal(10, #result)
      assert.are.equal('11', result[1].id)
      assert.are.equal('20', result[10].id)
    end)

    it('handles cache_offset > 0', function()
      local result = paging.cache_slice(items, 2, 10, 5)
      assert.are.equal(10, #result)
      assert.are.equal('6', result[1].id)
    end)

    it('respects max_rows cap', function()
      local result = paging.cache_slice(items, 1, 10, 0, 5)
      assert.are.equal(5, #result)
      assert.are.equal('1', result[1].id)
    end)

    it('handles partial last page', function()
      local result = paging.cache_slice(items, 4, 10, 0)
      assert.are.equal(0, #result)
    end)
  end)

  describe('resize_page', function()
    it('keeps page 1 when cursor is near start', function()
      local info = paging.resize_page(0, 50, 3, 20)
      assert.are.equal(1, info.page)
      assert.are.equal(0, info.overlap_start)
      assert.are.equal(20, info.overlap_end)
      assert.are.equal(4, info.cursor_line)
    end)

    it('moves to page 2 when cursor is past first page boundary', function()
      local info = paging.resize_page(0, 50, 25, 20)
      assert.are.equal(2, info.page)
      assert.are.equal(20, info.overlap_start)
      assert.are.equal(40, info.overlap_end)
      assert.are.equal(6, info.cursor_line)
    end)

    it('clamps overlap_end to cache boundary', function()
      local info = paging.resize_page(0, 15, 5, 20)
      assert.are.equal(1, info.page)
      assert.are.equal(0, info.overlap_start)
      assert.are.equal(15, info.overlap_end)
    end)

    it('handles cache_start > 0', function()
      local info = paging.resize_page(10, 30, 15, 20)
      assert.are.equal(1, info.page)
      assert.are.equal(10, info.overlap_start)
      assert.are.equal(20, info.overlap_end)
      assert.are.equal(6, info.cursor_line)
    end)

    it('handles cache_start beyond new page start', function()
      local info = paging.resize_page(25, 20, 30, 20)
      assert.are.equal(2, info.page)
      assert.are.equal(25, info.overlap_start)
      assert.are.equal(40, info.overlap_end)
      assert.are.equal(6, info.cursor_line)
    end)
  end)

  describe('extract_range', function()
    local items = {}
    for i = 1, 20 do items[i] = { id = tostring(i) } end

    it('extracts full range', function()
      local result = paging.extract_range(items, 0, 0, 20)
      assert.are.equal(20, #result)
    end)

    it('extracts sub-range', function()
      local result = paging.extract_range(items, 0, 5, 10)
      assert.are.equal(5, #result)
      assert.are.equal('6', result[1].id)
      assert.are.equal('10', result[5].id)
    end)

    it('handles non-zero cache_start', function()
      local result = paging.extract_range(items, 10, 15, 20)
      assert.are.equal(5, #result)
      assert.are.equal('6', result[1].id)
    end)

    it('returns empty for zero-width range', function()
      local result = paging.extract_range(items, 0, 5, 5)
      assert.are.equal(0, #result)
    end)
  end)
end)
