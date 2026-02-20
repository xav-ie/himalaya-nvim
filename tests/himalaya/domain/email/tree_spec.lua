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

    it('groups interleaved edges from different threads correctly', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Thread A root', date='2024-02-01 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='10', from='Bob', subject='Thread B root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Carol', subject='Reply A1', date='2024-02-02 10:00:00+00:00'}, 1 },
        { {id='10', from='Bob'}, {id='11', from='Dave', subject='Reply B1', date='2024-01-02 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges)
      assert.are.equal(4, #rows)
      -- Thread A (newer) comes first
      assert.are.equal('1', rows[1].env.id)
      assert.are.equal('2', rows[2].env.id)
      assert.are.equal(0, rows[1].depth)
      assert.are.equal(1, rows[2].depth)
      -- Thread B second
      assert.are.equal('10', rows[3].env.id)
      assert.are.equal('11', rows[4].env.id)
      assert.are.equal(0, rows[3].depth)
      assert.are.equal(1, rows[4].depth)
      -- Correct thread_idx
      assert.are.equal(1, rows[1].thread_idx)
      assert.are.equal(1, rows[2].thread_idx)
      assert.are.equal(2, rows[3].thread_idx)
      assert.are.equal(2, rows[4].thread_idx)
    end)

    it('groups deeply interleaved edges across 3 threads', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='T1', date='2024-03-01 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='10', from='Bob', subject='T2', date='2024-02-01 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='20', from='Carol', subject='T3', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='Alice'}, {id='2', from='Dave', subject='T1-R1', date='2024-03-02 10:00:00+00:00'}, 1 },
        { {id='10', from='Bob'}, {id='11', from='Eve', subject='T2-R1', date='2024-02-02 10:00:00+00:00'}, 1 },
        { {id='20', from='Carol'}, {id='21', from='Frank', subject='T3-R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='Dave'}, {id='3', from='Grace', subject='T1-R2', date='2024-03-03 10:00:00+00:00'}, 2 },
      }
      local rows = tree.build(edges)
      assert.are.equal(7, #rows)
      -- Thread 1 first (newest)
      assert.are.equal('1', rows[1].env.id)
      assert.are.equal('2', rows[2].env.id)
      assert.are.equal('3', rows[3].env.id)
      assert.are.equal(0, rows[1].depth)
      assert.are.equal(1, rows[2].depth)
      assert.are.equal(2, rows[3].depth)
      -- Thread 2 second
      assert.are.equal('10', rows[4].env.id)
      assert.are.equal('11', rows[5].env.id)
      -- Thread 3 last
      assert.are.equal('20', rows[6].env.id)
      assert.are.equal('21', rows[7].env.id)
    end)

    it('produces deterministic order regardless of edge input order', function()
      -- Same thread data but edges in reverse order (deep before root)
      local edges = {
        { {id='2', from='Bob'}, {id='3', from='Carol', subject='Deep', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='Reply', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
      }
      local rows = tree.build(edges)
      assert.are.equal(3, #rows)
      -- Must be in DFS order: root, reply, deep — not reverse edge order
      assert.are.equal('1', rows[1].env.id)
      assert.are.equal(0, rows[1].depth)
      assert.are.equal('2', rows[2].env.id)
      assert.are.equal(1, rows[2].depth)
      assert.are.equal('3', rows[3].env.id)
      assert.are.equal(2, rows[3].depth)
    end)

    it('sorts sibling replies by date within a thread', function()
      local edges = {
        { {id='0'}, {id='1', from='Alice', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        -- Later reply listed before earlier one in edges
        { {id='1', from='Alice'}, {id='3', from='Carol', subject='Later', date='2024-01-03 10:00:00+00:00'}, 1 },
        { {id='1', from='Alice'}, {id='2', from='Bob', subject='Earlier', date='2024-01-02 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges)
      assert.are.equal(3, #rows)
      assert.are.equal('1', rows[1].env.id)
      -- Siblings sorted by date: earlier first
      assert.are.equal('2', rows[2].env.id)
      assert.are.equal('3', rows[3].env.id)
    end)

    it('is deterministic when threads have identical latest dates', function()
      local edges_order1 = {
        { {id='0'}, {id='1', from='Alice', subject='T1', date='2024-01-10 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='2', from='Bob', subject='T2', date='2024-01-10 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='3', from='Carol', subject='T3', date='2024-01-10 10:00:00+00:00'}, 0 },
      }
      local edges_order2 = {
        { {id='0'}, {id='3', from='Carol', subject='T3', date='2024-01-10 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='1', from='Alice', subject='T1', date='2024-01-10 10:00:00+00:00'}, 0 },
        { {id='0'}, {id='2', from='Bob', subject='T2', date='2024-01-10 10:00:00+00:00'}, 0 },
      }
      local rows1 = tree.build(edges_order1)
      local rows2 = tree.build(edges_order2)
      assert.are.equal(3, #rows1)
      assert.are.equal(3, #rows2)
      assert.are.equal(rows1[1].env.id, rows2[1].env.id)
      assert.are.equal(rows1[2].env.id, rows2[2].env.id)
      assert.are.equal(rows1[3].env.id, rows2[3].env.id)
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

  describe('visual_depth', function()
    it('sets VD=0 for root and VD=1 for all nodes in a linear chain', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='R2', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='3', from='C'}, {id='4', from='D', subject='R3', date='2024-01-04 10:00:00+00:00'}, 3 },
      }
      local rows = tree.build(edges)
      assert.are.equal(0, rows[1].visual_depth)
      assert.are.equal(1, rows[2].visual_depth)
      assert.are.equal(1, rows[3].visual_depth)
      assert.are.equal(1, rows[4].visual_depth)
    end)

    it('increments VD only at branch points', function()
      -- Root → A → {B, C}  (A has 2 children = branch)
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='B1', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='2', from='B'}, {id='4', from='D', subject='B2', date='2024-01-04 10:00:00+00:00'}, 2 },
      }
      local rows = tree.build(edges)
      assert.are.equal(0, rows[1].visual_depth) -- Root
      assert.are.equal(1, rows[2].visual_depth) -- A (linear)
      assert.are.equal(2, rows[3].visual_depth) -- B1 (branch child)
      assert.are.equal(2, rows[4].visual_depth) -- B2 (branch child)
    end)

    it('keeps linear descendants of branch children at same VD', function()
      -- Root → {A, Z}  A → B → C (linear under A)
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='A', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='5', from='F', subject='Z', date='2024-01-06 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='B', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='3', from='C'}, {id='4', from='D', subject='C', date='2024-01-04 10:00:00+00:00'}, 3 },
      }
      local rows = tree.build(edges)
      assert.are.equal(0, rows[1].visual_depth) -- Root
      assert.are.equal(1, rows[2].visual_depth) -- A (branch child)
      assert.are.equal(1, rows[3].visual_depth) -- B (linear under A)
      assert.are.equal(1, rows[4].visual_depth) -- C (linear under B)
      assert.are.equal(1, rows[5].visual_depth) -- Z (branch child)
    end)

    it('marks is_branch_child correctly', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='B1', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='2', from='B'}, {id='4', from='D', subject='B2', date='2024-01-04 10:00:00+00:00'}, 2 },
      }
      local rows = tree.build(edges)
      assert.is_false(rows[1].is_branch_child) -- Root
      assert.is_false(rows[2].is_branch_child) -- R1 (only child)
      assert.is_true(rows[3].is_branch_child)  -- B1 (one of 2 children)
      assert.is_true(rows[4].is_branch_child)  -- B2 (one of 2 children)
    end)

    it('deep linear chain of 15 nodes stays at VD=1', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
      }
      for i = 1, 14 do
        edges[#edges + 1] = {
          {id=tostring(i), from='X'},
          {id=tostring(i+1), from='Y', subject='R'..i, date=string.format('2024-01-%02d 10:00:00+00:00', i+1)},
          i,
        }
      end
      local rows = tree.build(edges)
      assert.are.equal(15, #rows)
      assert.are.equal(0, rows[1].visual_depth)
      for i = 2, 15 do
        assert.are.equal(1, rows[i].visual_depth)
      end
    end)
  end)

  describe('build_prefix (compact)', function()
    it('adds empty prefix for root nodes', function()
      local rows = tree.build({
        { {id='0'}, {id='1', from='Alice', subject='Solo', date='2024-01-01 10:00:00+00:00'}, 0 },
      })
      tree.build_prefix(rows)
      assert.are.equal('', rows[1].prefix)
    end)

    it('uses space indent for linear chain (no branch connectors)', function()
      local rows = tree.build({
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='R2', date='2024-01-03 10:00:00+00:00'}, 2 },
      })
      tree.build_prefix(rows)
      assert.are.equal('  ', rows[2].prefix) -- 2-space indent, no tree chars
      assert.are.equal('  ', rows[3].prefix) -- same level, same indent
    end)

    it('uses branch connectors for multi-child parent', function()
      local rows = tree.build({
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='B', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='3', from='C', subject='C', date='2024-01-03 10:00:00+00:00'}, 1 },
      })
      tree.build_prefix(rows)
      assert.are.equal('', rows[1].prefix)
      -- ├─ for non-last branch child
      assert.is_truthy(rows[2].prefix:find('\xe2\x94\x9c'))
      -- └─ for last branch child
      assert.is_truthy(rows[3].prefix:find('\xe2\x94\x94'))
    end)

    it('shows branch continuation │ for linear descendants of non-last branch', function()
      -- Root → {A, Z}  A → B (linear under A)
      local rows = tree.build({
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='A', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='B', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='1', from='A'}, {id='4', from='D', subject='Z', date='2024-01-04 10:00:00+00:00'}, 1 },
      })
      tree.build_prefix(rows)
      -- A = ├─ (branch, not last)
      assert.is_truthy(rows[2].prefix:find('\xe2\x94\x9c'))
      -- B = │  (linear, piggybacks on A's branch continuation)
      assert.are.equal('\xe2\x94\x82 ', rows[3].prefix)
      -- Z = └─ (branch, last)
      assert.is_truthy(rows[4].prefix:find('\xe2\x94\x94'))
    end)

    it('uses space indent after last branch child (no continuation)', function()
      -- Root → {A, B}  B → C (linear under last branch child)
      local rows = tree.build({
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='A', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='3', from='C', subject='B', date='2024-01-03 10:00:00+00:00'}, 1 },
        { {id='3', from='C'}, {id='4', from='D', subject='C', date='2024-01-04 10:00:00+00:00'}, 2 },
      })
      tree.build_prefix(rows)
      -- C is linear child of B (last branch child) → space indent, no │
      assert.are.equal('  ', rows[4].prefix)
    end)

    it('handles nested branches correctly', function()
      -- Root → {A, Z}   A → B → {C, D}
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='A', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='B', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='3', from='C'}, {id='4', from='D', subject='C', date='2024-01-04 10:00:00+00:00'}, 3 },
        { {id='3', from='C'}, {id='5', from='E', subject='D', date='2024-01-05 10:00:00+00:00'}, 3 },
        { {id='1', from='A'}, {id='6', from='F', subject='Z', date='2024-01-06 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges)
      tree.build_prefix(rows)
      -- Root: ""
      assert.are.equal('', rows[1].prefix)
      -- A: ├─ (branch child, not last: Z follows)
      assert.are.equal('\xe2\x94\x9c\xe2\x94\x80', rows[2].prefix)
      -- B: │  (linear under A, branch continuation active)
      assert.are.equal('\xe2\x94\x82 ', rows[3].prefix)
      -- C: │ ├─ (branch child of B at VD=2, B has 2 children)
      assert.are.equal('\xe2\x94\x82 \xe2\x94\x9c\xe2\x94\x80', rows[4].prefix)
      -- D: │ └─ (last branch child at VD=2)
      assert.are.equal('\xe2\x94\x82 \xe2\x94\x94\xe2\x94\x80', rows[5].prefix)
      -- Z: └─ (last branch child at VD=1)
      assert.are.equal('\xe2\x94\x94\xe2\x94\x80', rows[6].prefix)
    end)

    it('deep linear chain uses only 2-char prefix regardless of depth', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
      }
      for i = 1, 14 do
        edges[#edges + 1] = {
          {id=tostring(i), from='X'},
          {id=tostring(i+1), from='Y', subject='R'..i, date=string.format('2024-01-%02d 10:00:00+00:00', i+1)},
          i,
        }
      end
      local rows = tree.build(edges)
      tree.build_prefix(rows)
      -- All non-root nodes should have exactly 2 display columns of prefix
      for i = 2, 15 do
        assert.are.equal(2, vim.fn.strdisplaywidth(rows[i].prefix),
          'row ' .. i .. ' prefix width should be 2, got: ' .. vim.fn.strdisplaywidth(rows[i].prefix))
      end
    end)
  end)

  describe('build (reverse)', function()
    it('fully reverses rows: newest at top, root at bottom', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='R2', date='2024-01-03 10:00:00+00:00'}, 2 },
      }
      local rows = tree.build(edges, { reverse = true })
      assert.are.equal(3, #rows)
      assert.are.equal('3', rows[1].env.id)  -- Newest at top
      assert.are.equal('2', rows[2].env.id)
      assert.are.equal('1', rows[3].env.id)  -- Root at bottom
    end)

    it('preserves original depth/VD from build', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='R2', date='2024-01-03 10:00:00+00:00'}, 2 },
      }
      local rows = tree.build(edges, { reverse = true })
      -- Reversed: C(d2), B(d1), Root(d0)
      assert.are.equal(2, rows[1].depth)
      assert.are.equal(1, rows[2].depth)
      assert.are.equal(0, rows[3].depth)
    end)

    it('fully reverses a branching tree', function()
      -- Normal DFS: Root, A, B, C, D, Z
      -- Reversed:   Z, D, C, B, A, Root
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='A', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='6', from='F', subject='Z', date='2024-01-06 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='B', date='2024-01-03 10:00:00+00:00'}, 2 },
        { {id='3', from='C'}, {id='4', from='D', subject='C', date='2024-01-04 10:00:00+00:00'}, 3 },
        { {id='3', from='C'}, {id='5', from='E', subject='D', date='2024-01-05 10:00:00+00:00'}, 3 },
      }
      local rows = tree.build(edges, { reverse = true })
      assert.are.equal(6, #rows)
      assert.are.equal('6', rows[1].env.id)  -- Z
      assert.are.equal('5', rows[2].env.id)  -- D
      assert.are.equal('4', rows[3].env.id)  -- C
      assert.are.equal('3', rows[4].env.id)  -- B
      assert.are.equal('2', rows[5].env.id)  -- A
      assert.are.equal('1', rows[6].env.id)  -- Root at bottom
    end)

    it('linear chain prefix: plain indent, root has none', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='R1', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='3', from='C', subject='R2', date='2024-01-03 10:00:00+00:00'}, 2 },
      }
      local rows = tree.build(edges, { reverse = true })
      tree.build_prefix(rows, { reverse = true })
      -- Reversed: C, B, Root — all linear, no branch connectors
      assert.are.equal('  ', rows[1].prefix)  -- C (VD=1)
      assert.are.equal('  ', rows[2].prefix)  -- B (VD=1)
      assert.are.equal('', rows[3].prefix)    -- Root (VD=0)
    end)

    it('reversed branch connectors: ┌─ for first/top, ├─ for last/bottom', function()
      -- Normal:   Root, ├─A, └─B
      -- Reversed: ┌─B, ├─A, Root
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='Older', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='3', from='C', subject='Newer', date='2024-01-03 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges, { reverse = true })
      tree.build_prefix(rows, { reverse = true })
      -- C is first branch child (top) → ┌─
      assert.are.equal('\xe2\x94\x8c\xe2\x94\x80', rows[1].prefix)
      -- B is last branch child (bottom) → ├─
      assert.are.equal('\xe2\x94\x9c\xe2\x94\x80', rows[2].prefix)
      assert.are.equal('', rows[3].prefix)
    end)

    it('reversed 3-way branch: ┌─ first/top, ├─ middle, ├─ last/bottom', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='X', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='3', from='C', subject='Y', date='2024-01-03 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='4', from='D', subject='Z', date='2024-01-04 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges, { reverse = true })
      tree.build_prefix(rows, { reverse = true })
      -- Reversed: D, C, B, Root
      assert.are.equal('\xe2\x94\x8c\xe2\x94\x80', rows[1].prefix)  -- ┌─ first/top
      assert.are.equal('\xe2\x94\x9c\xe2\x94\x80', rows[2].prefix)  -- ├─ middle
      assert.are.equal('\xe2\x94\x9c\xe2\x94\x80', rows[3].prefix)  -- ├─ last/bottom
      assert.are.equal('', rows[4].prefix)
    end)

    it('cycle in edges does not stack overflow', function()
      -- A→B and B→A form a cycle; build must not recurse infinitely
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='Reply', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='2', from='B'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges)
      -- Should produce rows without crashing; exact structure is
      -- implementation-defined but both nodes must appear at most once.
      assert.is_true(#rows >= 1)
      assert.is_true(#rows <= 2)
    end)

    it('self-referencing edge does not stack overflow', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Self', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='1', from='A', subject='Self', date='2024-01-01 10:00:00+00:00'}, 1 },
      }
      local rows = tree.build(edges)
      assert.are.equal(1, #rows)
      assert.are.equal('1', tostring(rows[1].env.id))
    end)

    it('normal mode is unchanged when reverse is false', function()
      local edges = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='Older', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='3', from='C', subject='Newer', date='2024-01-03 10:00:00+00:00'}, 1 },
      }
      local rows_default = tree.build(edges)
      local edges2 = {
        { {id='0'}, {id='1', from='A', subject='Root', date='2024-01-01 10:00:00+00:00'}, 0 },
        { {id='1', from='A'}, {id='2', from='B', subject='Older', date='2024-01-02 10:00:00+00:00'}, 1 },
        { {id='1', from='A'}, {id='3', from='C', subject='Newer', date='2024-01-03 10:00:00+00:00'}, 1 },
      }
      local rows_explicit = tree.build(edges2, { reverse = false })
      assert.are.equal(rows_default[1].env.id, rows_explicit[1].env.id)
      assert.are.equal(rows_default[2].env.id, rows_explicit[2].env.id)
      assert.are.equal(rows_default[3].env.id, rows_explicit[3].env.id)
    end)
  end)
end)
