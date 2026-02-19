local M = {}

--- Build flat display rows from CLI thread edges.
---
--- Input: CLI output from `envelope thread` — flat array of
--- {parent_env, child_env, depth_int} tuples.
---
--- Algorithm:
--- 1. Walk edges; depth=0 starts a new thread group.
--- 2. For each group, take the child from each edge. For depth=0 edges
---    with a non-ghost parent (id ~= "0"), also include the parent.
--- 3. Sort thread groups by newest message date descending.
--- 4. Compute is_last_child for tree rendering.
--- 5. Normalize `from` field: plain string → {name = string}.
---
--- @param edges table[] Array of {parent_env, child_env, depth_int}
--- @return table[] Array of {env, depth, is_last_child, thread_idx}
function M.build(edges)
  if #edges == 0 then
    return {}
  end

  -- Group edges into threads (depth=0 starts a new group)
  local groups = {}
  local current_group = nil

  for _, edge in ipairs(edges) do
    local parent, child, depth = edge[1], edge[2], edge[3]
    if depth == 0 then
      current_group = { nodes = {}, latest_date = '', depth_offset = 0 }
      groups[#groups + 1] = current_group
    end
    if current_group then
      -- Normalize from: thread envelopes have from as a plain string
      if type(child.from) == 'string' then
        child.from = { name = child.from }
      end

      if depth == 0 and tostring(parent.id) ~= '0' then
        -- Include non-ghost parent at depth 0
        if type(parent.from) == 'string' then
          parent.from = { name = parent.from }
        end
        current_group.nodes[#current_group.nodes + 1] = { env = parent, depth = 0 }
        if (parent.date or '') > current_group.latest_date then
          current_group.latest_date = parent.date or ''
        end
        current_group.depth_offset = 1
      end

      current_group.nodes[#current_group.nodes + 1] = {
        env = child,
        depth = depth + current_group.depth_offset,
      }
      if (child.date or '') > current_group.latest_date then
        current_group.latest_date = child.date or ''
      end
    end
  end

  -- Sort groups by latest date descending (newest thread first)
  table.sort(groups, function(a, b)
    return a.latest_date > b.latest_date
  end)

  -- Flatten into display_rows with thread_idx
  local display_rows = {}
  for idx, group in ipairs(groups) do
    for _, node in ipairs(group.nodes) do
      display_rows[#display_rows + 1] = {
        env = node.env,
        depth = node.depth,
        is_last_child = true,
        thread_idx = idx,
      }
    end
  end

  -- Compute is_last_child: a node at depth d is last if no later node
  -- at the same depth appears before a node at depth < d.
  for i, row in ipairs(display_rows) do
    if row.depth > 0 then
      row.is_last_child = true
      for j = i + 1, #display_rows do
        local other = display_rows[j]
        if other.depth < row.depth then
          break
        end
        if other.depth == row.depth then
          row.is_last_child = false
          break
        end
      end
    end
  end

  return display_rows
end

-- Tree-drawing characters (hex-escaped for tokenizer safety)
local TREE_V    = "\xe2\x94\x82" -- │
local TREE_H    = "\xe2\x94\x80" -- ─
local TREE_FORK = "\xe2\x94\x9c" -- ├
local TREE_END  = "\xe2\x94\x94" -- └

--- Compute tree connector prefix strings for each row.
--- Uses a boolean ancestor stack to track which levels need continuation lines.
--- @param rows table[] Display rows from M.build()
--- @return table[] Same rows with .prefix added
function M.build_prefix(rows)
  local stack = {}
  for _, row in ipairs(rows) do
    for d = row.depth + 1, #stack do stack[d] = nil end
    local prefix = ''
    for d = 1, row.depth - 1 do
      prefix = prefix .. (stack[d] and (TREE_V .. ' ') or '  ')
    end
    if row.depth > 0 then
      prefix = prefix .. (row.is_last_child and (TREE_END .. TREE_H) or (TREE_FORK .. TREE_H))
    end
    row.prefix = prefix
    stack[row.depth] = not row.is_last_child
  end
  return rows
end

return M
