local M = {}

--- Parse an ISO-ish date string to a UTC epoch number.
--- Handles both "YYYY-MM-DD HH:MM:SS±HH:MM" and "YYYY-MM-DDTHH:MM:SSZ".
--- @param raw string
--- @return number
local function date_to_epoch(raw)
  if not raw or raw == '' then return 0 end
  local y, mo, d, h, mi, s, tz = raw:match("^(%d+)-(%d+)-(%d+)[T%s](%d+):(%d+):?(%d*)(.*)")
  if not y then return 0 end
  s = (s ~= '') and tonumber(s) or 0
  local tz_offset = 0
  if tz ~= '' and tz ~= 'Z' then
    local tz_sign, tz_h, tz_m = tz:match("^([%+%-])(%d+):(%d+)")
    if tz_sign then
      tz_offset = (tonumber(tz_h) * 3600 + tonumber(tz_m) * 60)
      if tz_sign == '-' then tz_offset = -tz_offset end
    end
  end
  return os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = s,
  }) - tz_offset
end

--- Build flat display rows from CLI thread edges.
---
--- Input: CLI output from `envelope thread` — flat array of
--- {parent_env, child_env, depth_int} tuples.
--- Edges arrive in arbitrary order (not grouped by thread, not by depth).
---
--- Algorithm:
--- 1. Normalize `from` field: plain string → {name = string}.
--- 2. Identify thread roots from depth=0 edges; build node→thread map.
--- 3. Propagate thread membership to depth>0 edges via parent chain.
--- 4. Build parent→children adjacency map, sort children by date.
--- 5. DFS-walk each thread root to collect nodes in deterministic order.
--- 6. Sort thread groups by newest message date descending.
--- 7. Compute is_last_child for tree rendering.
---
--- @param edges table[] Array of {parent_env, child_env, depth_int}
--- @return table[] Array of {env, depth, is_last_child, thread_idx}
function M.build(edges)
  if #edges == 0 then
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

  -- Phase 1: Identify thread roots from depth=0 edges
  local node_to_thread = {} -- node_id → thread_root_id
  local thread_order = {}   -- ordered list of thread_ids (first-seen order)
  local thread_set = {}     -- thread_id → true (dedup)
  local thread_meta = {}    -- thread_id → {has_non_ghost_root, root_env}

  for _, edge in ipairs(edges) do
    local parent, child, depth = edge[1], edge[2], edge[3]
    if depth == 0 then
      local pid = tostring(parent.id)
      local cid = tostring(child.id)
      local thread_id
      if pid == '0' then
        thread_id = cid
        thread_meta[thread_id] = { has_non_ghost_root = false }
      else
        thread_id = pid
        node_to_thread[pid] = thread_id
        thread_meta[thread_id] = { has_non_ghost_root = true, root_env = parent }
      end
      node_to_thread[cid] = thread_id
      if not thread_set[thread_id] then
        thread_set[thread_id] = true
        thread_order[#thread_order + 1] = thread_id
      end
    end
  end

  -- Phase 2: Propagate thread IDs for depth>0 edges via parent chain
  local changed = true
  while changed do
    changed = false
    for _, edge in ipairs(edges) do
      local parent, child, depth = edge[1], edge[2], edge[3]
      if depth > 0 then
        local pid = tostring(parent.id)
        local cid = tostring(child.id)
        if node_to_thread[pid] and not node_to_thread[cid] then
          node_to_thread[cid] = node_to_thread[pid]
          changed = true
        end
      end
    end
  end

  -- Phase 3: Build parent→children adjacency map
  local children_of = {} -- parent_id → [{env, depth}]
  for _, edge in ipairs(edges) do
    local parent, child, depth = edge[1], edge[2], edge[3]
    local pid = tostring(parent.id)
    if not children_of[pid] then children_of[pid] = {} end
    children_of[pid][#children_of[pid] + 1] = { env = child, depth = depth }
  end

  -- Sort children of each parent by date (chronological), ID as tiebreaker
  for _, kids in pairs(children_of) do
    table.sort(kids, function(a, b)
      local ea = date_to_epoch(a.env.date or '')
      local eb = date_to_epoch(b.env.date or '')
      if ea ~= eb then return ea < eb end
      return tostring(a.env.id) < tostring(b.env.id)
    end)
  end

  -- Phase 4: DFS-walk each thread to collect nodes in tree order
  local function dfs(parent_id, depth_offset, group, thread_id)
    local kids = children_of[parent_id]
    if not kids then return end
    for _, kid in ipairs(kids) do
      local cid = tostring(kid.env.id)
      if node_to_thread[cid] == thread_id then
        group.nodes[#group.nodes + 1] = { env = kid.env, depth = kid.depth + depth_offset }
        local ep = date_to_epoch(kid.env.date or '')
        if ep > group.latest_epoch then group.latest_epoch = ep end
        dfs(cid, depth_offset, group, thread_id)
      end
    end
  end

  local groups = {} -- ordered list of {nodes, latest_epoch}
  for _, tid in ipairs(thread_order) do
    local meta = thread_meta[tid]
    local g = { nodes = {}, latest_epoch = 0, thread_id = tid }

    if meta.has_non_ghost_root then
      -- Non-ghost root: add parent at depth 0, DFS children with offset 1
      g.nodes[1] = { env = meta.root_env, depth = 0 }
      local ep = date_to_epoch(meta.root_env.date or '')
      if ep > g.latest_epoch then g.latest_epoch = ep end
      dfs(tid, 1, g, tid)
    else
      -- Ghost root: find root node from children_of['0'], DFS with offset 0
      local ghost_kids = children_of['0']
      if ghost_kids then
        for _, kid in ipairs(ghost_kids) do
          if tostring(kid.env.id) == tid then
            g.nodes[1] = { env = kid.env, depth = 0 }
            local ep = date_to_epoch(kid.env.date or '')
            if ep > g.latest_epoch then g.latest_epoch = ep end
            break
          end
        end
      end
      dfs(tid, 0, g, tid)
    end

    groups[#groups + 1] = g
  end

  -- Phase 5: Sort groups by latest date descending (newest thread first),
  -- with thread_id as tiebreaker for deterministic ordering.
  table.sort(groups, function(a, b)
    if a.latest_epoch ~= b.latest_epoch then
      return a.latest_epoch > b.latest_epoch
    end
    return a.thread_id < b.thread_id
  end)

  -- Phase 6: Flatten into display_rows with thread_idx
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

  -- Phase 7: Compute is_last_child
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
