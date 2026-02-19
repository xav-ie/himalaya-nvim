local M = {}

--- Merge two contiguous or overlapping envelope caches into one.
--- If they are disjoint (gap between them), returns new_envs only.
--- @param old_envs table[]|nil previous cached envelopes
--- @param old_offset number    global index where old_envs starts
--- @param new_envs table[]     freshly fetched envelopes
--- @param new_offset number    global index where new_envs starts
--- @return table[] merged envelopes
--- @return number  merged offset
function M.merge(old_envs, old_offset, new_envs, new_offset)
  if not old_envs or #old_envs == 0 then
    return new_envs, new_offset
  end
  local old_end = old_offset + #old_envs
  local new_end = new_offset + #new_envs
  -- Disjoint (gap) -> replace, can't have holes
  if new_offset > old_end or old_offset > new_end then
    return new_envs, new_offset
  end
  -- Contiguous or overlapping -> merge, new wins in overlap
  local merged_offset = math.min(old_offset, new_offset)
  local merged_end = math.max(old_end, new_end)
  local merged = {}
  for i = 1, merged_end - merged_offset do
    local g = merged_offset + i - 1
    if g >= old_offset and g < old_end then
      merged[i] = old_envs[g - old_offset + 1]
    end
  end
  for i = 1, #new_envs do
    merged[new_offset - merged_offset + i] = new_envs[i]
  end
  return merged, merged_offset
end

return M
