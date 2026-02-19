describe('himalaya.domain.email.tree', function()
  local tree

  before_each(function()
    package.loaded['himalaya.domain.email.tree'] = nil
    tree = require('himalaya.domain.email.tree')
  end)

  describe('build', function()
    it('returns empty list for empty input', function()
      local rows = tree.build({})
      assert.are.equal(0, #rows)
    end)

    it('builds linear chain A→B→C with correct depths', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='Reply 1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='Bob'}, {id='3', from='Carol', subject='Reply 2', date='2024-01-03 10:00:00+00:00'}, 2 },
      }
      local rows = tree.build(edges)
      assert.are.equal(3, #rows)
      assert.are.equal(0, rows[1].depth)
      assert.are.equal(1, rows[2].depth)
      assert.are.equal(2, rows[3].depth)
      assert.is_true(rows[1].is_last_child)
      assert.is_true(rows[2].is_last_child)
      assert.is_true(rows[3].is_last_child)
    end)

    it('handles branch A→B and A→C', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='Reply B', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='Alice'}, {id='3', from='Carol', subject='Reply C', date='2024-01-03 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges)
      assert.are.equal(3, #rows)
      assert.are.equal(0, rows[1].depth)
      assert.are.equal(1, rows[2].depth)
      assert.are.equal(1, rows[3].depth)
      assert.is_false(rows[2].is_last_child)
      assert.is_true(rows[3].is_last_child)
    end)

    it('excludes ghost parent (id="0") from display rows', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
      }
      local rows = tree.build(edges)
      assert.are.equal(1, #rows)
      assert.are.equal('1', rows[1].env.id)
      assert.are.equal(0, rows[1].depth)
    end)

    it('sorts multiple threads by newest message date descending', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Old thread', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='2', from='Bob', subject='New thread', date='2024-02-01 10:00:00+00:00'}, 0 },
      }
      local rows = tree.build(edges)
      assert.are.equal(2, #rows)
      assert.are.equal('2', rows[1].env.id) -- New thread first
      assert.are.equal('1', rows[2].env.id)
    end)

    it('sorts thread by latest reply, not root date', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Old root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='3', from='Carol', subject='New reply', date='2024-03-01 10:00:00+00:00'}, 1 },
        { {id='0'}, {id='2', from='Bob', subject='Newer root', date='2024-02-01 10:00:00+00:00'}, 0 },
      }
      local rows = tree.build(edges)
      assert.are.equal(3, #rows)
      -- Thread with old root but newer reply should come first
      assert.are.equal('1', rows[1].env.id)
      assert.are.equal('3', rows[2].env.id)
      assert.are.equal('2', rows[3].env.id)
    end)

    it('handles single-message thread', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Solo', date='2024-01-01 10:00:00+00:00'}, 0 },
      }
      local rows = tree.build(edges)
      assert.are.equal(1, #rows)
      assert.are.equal(0, rows[1].depth)
      assert.is_true(rows[1].is_last_child)
    end)

    it('normalizes from string to table with name field', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice Smith', subject='Test', date='2024-01-01 10:00:00+00:00'}, 0 },
      }
      local rows = tree.build(edges)
      assert.are.same({ name = 'Alice Smith' }, rows[1].env.from)
    end)

    it('assigns thread_idx to each row', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Thread 1', date='2024-02-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='Reply', date='2024-02-02 10:00:00+00:00'}, 1 },
        { {id='0'}, {id='3', from='Carol', subject='Thread 2', date='2024-01-01 10:00:00+00:00'}, 0 },
      }
      local rows = tree.build(edges)
      -- Thread 1 is newer, so it comes first (thread_idx=1)
      assert.are.equal(1, rows[1].thread_idx)
      assert.are.equal(1, rows[2].thread_idx)
      assert.are.equal(2, rows[3].thread_idx)
    end)

    it('includes non-ghost parent at depth 0 and offsets children', function()
      local edges = {
        { {id='5', from='Root Author', subject='Root', date='2024-01-01 10:00:00+00:00'},
          {id='6', from='Reply Author', subject='Reply', date='2024-01-02 10:00:00+00:00'}, 0 },
        { {id='6', from='Reply Author'},
          {id='7', from='Deep Author', subject='Deep', date='2024-01-03 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges)
      assert.are.equal(3, #rows)
      assert.are.equal('5', rows[1].env.id)
      assert.are.equal(0, rows[1].depth)
      assert.are.equal('6', rows[2].env.id)
      assert.are.equal(1, rows[2].depth) -- offset from 0 to 1
      assert.are.equal('7', rows[3].env.id)
      assert.are.equal(2, rows[3].depth) -- offset from 1 to 2
    end)
  end)

  describe('build_prefix', function()
    it('adds empty prefix for depth-0 nodes', function()
      local rows = tree.build({
        { {id='0'}, {id='1', from='Alice', subject='Solo', date='2024-01-01 10:00:00+00:00'}, 0 },
      })
      tree.build_prefix(rows)
      assert.are.equal('', rows[1].prefix)
    end)

    it('adds fork prefix for non-last child and end prefix for last child', function()
      local rows = tree.build({
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='B', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='Alice'}, {id='3', from='Carol', subject='C', date='2024-01-03 10:00:00+00:00'}, 1 },
      })
      tree.build_prefix(rows)
      assert.are.equal('', rows[1].prefix)
      -- ├─ for non-last child
      assert.is_truthy(rows[2].prefix:find('\xe2\x94\x9c'))
      -- └─ for last child
      assert.is_truthy(rows[3].prefix:find('\xe2\x94\x94'))
    end)

    it('adds continuation line for deep nesting', function()
      -- Edges in DFS order: root → first child → grandchild → second child
      local rows = tree.build({
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='B', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='Bob'}, {id='3', from='Carol', subject='C', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='1', from='Alice'}, {id='4', from='Eve', subject='E', date='2024-01-04 10:00:00+00:00'}, 1 },
      })
      tree.build_prefix(rows)
      -- Row 3 (depth 2) should have │ continuation from depth 1 (non-last sibling)
      assert.is_truthy(rows[3].prefix:find('\xe2\x94\x82'))
    end)

    it('uses blank indent when ancestor is last child', function()
      local rows = tree.build({
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='B', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='Bob'}, {id='3', from='Carol', subject='C', date='2024-01-03 10:00:00+00:00'}, 2 },
      })
      tree.build_prefix(rows)
      -- Row 3 (depth 2): ancestor at depth 1 is last child, so blank indent (2 spaces)
      -- Prefix should be "  └─" (2 spaces + end connector)
      assert.are.equal(2, vim.fn.strdisplaywidth(rows[2].prefix)) -- └─ = 2 cols
      -- For depth 2, prefix should start with spaces (not │)
      assert.is_falsy(rows[3].prefix:sub(1, 3) == '\xe2\x94\x82')
    end)
  end)
end)
