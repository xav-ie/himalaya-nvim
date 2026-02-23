local perf = require('himalaya.perf')

local M = {}

--- Parse an ISO-ish date string to a UTC epoch number.
--- Handles both "YYYY-MM-DD HH:MM:SS±HH:MM" and "YYYY-MM-DDTHH:MM:SSZ".
--- @param raw string
--- @return number
function M.date_to_epoch(raw)
  if not raw or raw == '' then
    return 0
  end
  local y, mo, d, h, mi, s, tz = raw:match('^(%d+)-(%d+)-(%d+)[T%s](%d+):(%d+):?(%d*)(.*)')
  if not y then
    return 0
  end
  s = (s ~= '') and tonumber(s) or 0
  local tz_offset = 0
  if tz ~= '' and tz ~= 'Z' then
    local tz_sign, tz_h, tz_m = tz:match('^([%+%-])(%d+):(%d+)')
    if tz_sign then
      tz_offset = (tonumber(tz_h) * 3600 + tonumber(tz_m) * 60)
      if tz_sign == '-' then
        tz_offset = -tz_offset
      end
    end
  end
  return os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = s,
  }) - tz_offset
end

--- Build flat display rows from CLI thread edges.
---
--- Input: CLI output from `envelope thread` — flat array of
--- {parent_env, child_env, depth_int} tuples.
--- Edges arrive in arbitrary order. Depth=0 edges can form chains
--- (parent of one edge is the child of another) belonging to the
--- same thread.
---
--- Algorithm:
--- 1. Normalize `from` field: plain string → {name = string}.
--- 2. Build parent→children adjacency map, collect node envelopes.
--- 3. Find true roots: ghost children (parent='0') and non-ghost nodes
---    that never appear as children in any edge.
--- 4. DFS-walk each root, computing depth from graph position.
--- 5. Sort thread groups by newest message date descending.
--- 6. Compute is_last_child for tree rendering.
---
--- @param edges table[] Array of {parent_env, child_env, depth_int}
--- @param opts? table  Optional: { reverse = bool, sort = string ('date desc', 'from asc', etc.) }
--- @return table[] Array of {env, depth, is_last_child, thread_idx}
function M.build(edges, opts)
  perf.start('tree.build')
  opts = opts or {}
  local reverse = opts.reverse or false

  if #edges == 0 then
    perf.stop('tree.build')
    return {}
  end

  -- Normalize from fields upfront
  for _, edge in ipairs(edges) do
    local parent, child = edge[1], edge[2]
    if type(child.from) == 'string' then
      child.from = { name = child.from }
    end
    if type(parent.from) == 'string' then
      parent.from = { name = parent.from }
    end
  end

  -- Phase 1: Build parent→children adjacency map and collect node envelopes
  local children_of = {} -- parent_id → [child_env]
  local node_env = {} -- id → env (best available envelope data)
  local is_child = {} -- id → true (appears as child in some edge)

  for _, edge in ipairs(edges) do
    local parent, child = edge[1], edge[2]
    local pid = tostring(parent.id)
    local cid = tostring(child.id)

    if not children_of[pid] then
      children_of[pid] = {}
    end
    children_of[pid][#children_of[pid] + 1] = child

    -- Collect envelopes; child position typically has full data
    node_env[cid] = child
    if pid ~= '0' and not node_env[pid] then
      node_env[pid] = parent
    end

    is_child[cid] = true
  end

  -- Pre-compute epoch cache: one date_to_epoch call per unique envelope.
  local epoch_of = {}
  for id, env in pairs(node_env) do
    epoch_of[id] = M.date_to_epoch(env.date or '')
  end
  -- Ghost children (parent='0') may not be in node_env
  if children_of['0'] then
    for _, child in ipairs(children_of['0']) do
      local cid = tostring(child.id)
      if not epoch_of[cid] then
        epoch_of[cid] = M.date_to_epoch(child.date or '')
      end
    end
  end

  -- Sort children of each parent by date (chronological), ID as tiebreaker
  for _, kids in pairs(children_of) do
    table.sort(kids, function(a, b)
      local ea = epoch_of[tostring(a.id)] or 0
      local eb = epoch_of[tostring(b.id)] or 0
      if ea ~= eb then
        return ea < eb
      end
      return tostring(a.id) < tostring(b.id)
    end)
  end

  -- Phase 2: Find true roots
  local roots = {} -- [{env, id}]

  -- Ghost root children: children of '0' (these have no real parent)
  if children_of['0'] then
    for _, child in ipairs(children_of['0']) do
      roots[#roots + 1] = child
    end
  end

  -- Non-ghost roots: nodes that appear as parents but never as children
  -- Collect into a sorted list for deterministic ordering
  local orphan_ids = {}
  for pid, _ in pairs(children_of) do
    if pid ~= '0' and not is_child[pid] and node_env[pid] then
      orphan_ids[#orphan_ids + 1] = pid
    end
  end
  table.sort(orphan_ids)
  for _, pid in ipairs(orphan_ids) do
    roots[#roots + 1] = node_env[pid]
  end

  -- Phase 3: DFS-walk each root to build thread groups
  local groups = {}

  for _, root in ipairs(roots) do
    local rid = tostring(root.id)
    local g = { nodes = {}, latest_epoch = 0, thread_id = rid }

    -- Add root at depth 0, visual_depth 0
    g.nodes[1] = { env = root, depth = 0, visual_depth = 0, is_branch_child = false }
    local ep = epoch_of[rid] or 0
    if ep > g.latest_epoch then
      g.latest_epoch = ep
    end

    -- DFS: compute depth from graph position (parent depth + 1)
    -- visual_depth only increments at branch points (parent has 2+ children),
    -- minimum 1 for non-root nodes.
    -- visited set guards against cycles in malformed edge data.
    local visited = { [rid] = true }
    local function dfs(parent_id, depth, parent_vd)
      local kids = children_of[parent_id]
      if not kids then
        return
      end
      local is_branch = #kids > 1
      for _, kid in ipairs(kids) do
        local cid = tostring(kid.id)
        if not visited[cid] then
          visited[cid] = true
          local vd = is_branch and (parent_vd + 1) or parent_vd
          vd = math.max(1, vd)
          g.nodes[#g.nodes + 1] = { env = kid, depth = depth, visual_depth = vd, is_branch_child = is_branch }
          local kep = epoch_of[cid] or 0
          if kep > g.latest_epoch then
            g.latest_epoch = kep
          end
          dfs(cid, depth + 1, vd)
        end
      end
    end

    dfs(rid, 1, 0)
    groups[#groups + 1] = g
  end

  -- Phase 4: Sort thread groups by the user's chosen field/direction.
  local sort_str = opts.sort or 'date desc'
  local sort_field, sort_dir = sort_str:match('^(%S+)%s+(%S+)$')
  sort_field = sort_field or 'date'
  sort_dir = sort_dir or 'desc'
  local ascending = sort_dir == 'asc'

  -- Extract the comparison key for a group's root node.
  local function group_key(g)
    if sort_field == 'date' then
      return g.latest_epoch
    end
    local root = g.nodes[1] and g.nodes[1].env or {}
    if sort_field == 'from' then
      local f = root.from
      return type(f) == 'table' and (f.name or '') or (f or '')
    elseif sort_field == 'subject' then
      return root.subject or ''
    elseif sort_field == 'to' then
      local t = root.to
      return type(t) == 'table' and (t.name or '') or (t or '')
    end
    return g.latest_epoch
  end

  table.sort(groups, function(a, b)
    local ka, kb = group_key(a), group_key(b)
    if ka ~= kb then
      if ascending then
        return ka < kb
      else
        return ka > kb
      end
    end
    return a.thread_id < b.thread_id
  end)

  -- Phase 5: Flatten into display_rows with thread_idx.
  -- In reverse mode, rows are fully reversed (newest at top, root at bottom).
  local display_rows = {}
  for idx, group in ipairs(groups) do
    local nodes = group.nodes
    if reverse then
      local rev = {}
      for i = #nodes, 1, -1 do
        rev[#rev + 1] = nodes[i]
      end
      nodes = rev
    end
    for _, node in ipairs(nodes) do
      display_rows[#display_rows + 1] = {
        env = node.env,
        depth = node.depth,
        visual_depth = node.visual_depth,
        is_branch_child = node.is_branch_child,
        is_last_child = true,
        thread_idx = idx,
      }
    end
  end

  -- Phase 6: Compute is_last_child (backward pass, O(n))
  local last_at_depth = {}
  for i = #display_rows, 1, -1 do
    local row = display_rows[i]
    if row.depth > 0 then
      row.is_last_child = not last_at_depth[row.depth]
      last_at_depth[row.depth] = true
    end
    -- Crossing into a shallower depth resets deeper subtree tracking
    for d in pairs(last_at_depth) do
      if d > row.depth then
        last_at_depth[d] = nil
      end
    end
  end

  perf.stop('tree.build')
  return display_rows
end

-- Tree-drawing characters (hex-escaped for tokenizer safety)
local TREE_V = '\xe2\x94\x82' -- │
local TREE_H = '\xe2\x94\x80' -- ─
local TREE_FORK = '\xe2\x94\x9c' -- ├
local TREE_END = '\xe2\x94\x94' -- └
local TREE_TOP = '\xe2\x94\x8c' -- ┌

--- Compute compact tree connector prefix strings for each row.
--- Uses visual_depth (which only increments at branch points) so linear
--- chains stay flat.  Branch children get traditional ├─/└─ connectors;
--- linear continuation nodes inherit the ancestor branch continuation (│)
--- or plain indent (  ) depending on whether an active branch exists.
---
--- In reverse mode, connectors are mirrored: ┌─ for the first/top branch
--- child, ├─ for all subsequent children.
--- @param rows table[] Display rows from M.build()
--- @param opts? table  Optional: { reverse = bool }
--- @return table[] Same rows with .prefix added
function M.build_prefix(rows, opts)
  perf.start('tree.build_prefix')
  opts = opts or {}
  local reverse = opts.reverse or false
  local stack = {}
  for _, row in ipairs(rows) do
    local vd = row.visual_depth or row.depth
    for d = vd + 1, #stack do
      stack[d] = nil
    end
    local prefix = ''
    for d = 1, vd - 1 do
      prefix = prefix .. (stack[d] and (TREE_V .. ' ') or '  ')
    end
    if vd > 0 then
      if row.is_branch_child then
        if reverse then
          -- ┌─ first (top), ├─ rest
          if stack[vd] == nil then
            prefix = prefix .. (TREE_TOP .. TREE_H)
          else
            prefix = prefix .. (TREE_FORK .. TREE_H)
          end
        else
          prefix = prefix .. (row.is_last_child and (TREE_END .. TREE_H) or (TREE_FORK .. TREE_H))
        end
        stack[vd] = not row.is_last_child
      else
        -- Linear continuation: piggyback on active branch or plain indent
        prefix = prefix .. (stack[vd] and (TREE_V .. ' ') or '  ')
      end
    end
    row.prefix = prefix
  end
  perf.stop('tree.build_prefix')
  return rows
end

return M
