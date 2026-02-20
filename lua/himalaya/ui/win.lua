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
  if type(types) == 'string' then types = { types } end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local ok, bt = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_buffer_type')
      if ok then
        for _, t in ipairs(types) do
          if bt == t then return winid, bufnr, bt end
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

return M
