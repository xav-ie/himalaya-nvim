--- Window lookup helpers for himalaya buffers.
--- Centralises the repeated "iterate tabpage windows, match buffer" pattern.
local M = {}

--- Find a window in the current tabpage whose buffer name contains `pattern`.
--- @param pattern string  plain-text substring (not a Lua pattern)
--- @return number|nil winid
function M.find_by_name(pattern)
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) then
      local bname = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid))
      if bname:find(pattern, 1, true) then
        return winid
      end
    end
  end
end

--- Find a window in the current tabpage whose buffer has a matching
--- `himalaya_buffer_type` variable.
--- @param types string|string[]  single type or list of types to match
--- @return number|nil winid
--- @return number|nil bufnr
--- @return string|nil buffer_type
function M.find_by_buftype(types)
  if type(types) == 'string' then
    types = { types }
  end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local ok, bt = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_buffer_type')
      if ok then
        for _, t in ipairs(types) do
          if bt == t then
            return winid, bufnr, bt
          end
        end
      end
    end
  end
end

--- Find a window in the current tabpage that displays a specific buffer.
--- @param bufnr number
--- @return number|nil winid
function M.find_by_bufnr(bufnr)
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
end

--- Resolve a split size value: fraction (0<v<=1) → portion of total, >1 → absolute.
--- @param value number
--- @param total number
--- @return number
local function resolve_split_size(value, total)
  if value > 1 then
    return math.floor(value)
  else
    return math.floor(total * value)
  end
end

--- Open a split next to `ref_winid` using `reading_split` config, display `bufnr`.
--- @param bufnr number  buffer to show in the new split
--- @param ref_winid number  listing window to split relative to
function M.open_split(bufnr, ref_winid)
  local cfg = require('himalaya.config').get()
  local split = cfg.reading_split or {}
  local threshold = split.threshold or 115
  local default_size = split.size or 0.6
  local listing_width = vim.api.nvim_win_get_width(ref_winid)
  local branch = listing_width >= threshold
    and (split.over or 'right')
    or (split.under or 'below')

  local direction, size
  if type(branch) == 'table' then
    direction = branch.side or (listing_width >= threshold and 'right' or 'below')
    size = branch.size or default_size
  else
    direction = branch
    size = default_size
  end

  vim.api.nvim_open_win(bufnr, true, { split = direction, win = ref_winid })
  if direction == 'left' or direction == 'right' then
    vim.api.nvim_win_set_width(0, resolve_split_size(size, listing_width))
  else
    local listing_height = vim.api.nvim_win_get_height(ref_winid)
    local total_height = listing_height + vim.api.nvim_win_get_height(0)
    vim.api.nvim_win_set_height(0, resolve_split_size(size, total_height))
  end
end

return M
