--- Pure page-computation functions extracted from email.lua.
--- All functions are free of Neovim buffer/window side effects
--- and can be unit-tested without a live editor.

local M = {}

--- Extract the display page's slice from fetched data.
--- Used by on_list_with to pick the visible page out of a
--- double-sized CLI fetch.
--- @param data table[]  fetched envelope array
--- @param page number   1-based display page
--- @param page_size number  envelopes per page
--- @param fetch_offset number  0-based global index of data[1]
--- @return table[]  envelopes for the display page
function M.fetch_page_slice(data, page, page_size, fetch_offset)
  local display_start = (page - 1) * page_size
  local idx_start = display_start - fetch_offset
  if idx_start <= 0 and #data <= page_size then
    return data
  end
  local result = {}
  for i = math.max(idx_start, 0) + 1, math.min(#data, idx_start + page_size) do
    result[#result + 1] = data[i]
  end
  return result
end

--- Extract a page slice from cached envelopes.
--- Used by display_slice and mark_envelope_seen to pick visible rows.
--- @param items table[]  cached envelopes
--- @param page number  1-based current page
--- @param page_size number  envelopes per page
--- @param cache_offset number  0-based global index of items[1]
--- @param max_rows? number  optional cap on returned rows (e.g. buffer line count)
--- @return table[]
function M.cache_slice(items, page, page_size, cache_offset, max_rows)
  local page_start = (page - 1) * page_size
  local idx = math.max(1, page_start - cache_offset + 1)
  local limit = max_rows or page_size
  local last = math.min(#items, idx + limit - 1)
  if idx == 1 and last == #items then return items end
  local sliced = {}
  for i = idx, last do sliced[#sliced + 1] = items[i] end
  return sliced
end

--- Compute new page, overlap range, and cursor position after a resize.
--- Pure function: takes cache geometry and cursor state, returns
--- everything needed for Phase 1 rendering.
--- @param cache_start number  0-based global index of first cached envelope
--- @param cache_count number  number of envelopes in cache
--- @param cursor_global number  0-based global index of the cursor's envelope
--- @param new_page_size number  new page size after resize
--- @return table { page, overlap_start, overlap_end, cursor_line }
function M.resize_page(cache_start, cache_count, cursor_global, new_page_size)
  local new_page = math.floor(cursor_global / new_page_size) + 1
  local new_page_start = (new_page - 1) * new_page_size
  local new_page_end = new_page_start + new_page_size

  local overlap_start = math.max(cache_start, new_page_start)
  local overlap_end = math.min(cache_start + cache_count, new_page_end)
  local cursor_line = cursor_global - overlap_start + 1

  return {
    page = new_page,
    overlap_start = overlap_start,
    overlap_end = overlap_end,
    cursor_line = cursor_line,
  }
end

--- Extract envelopes from cache for a given global range.
--- @param items table[]  cached envelopes
--- @param cache_start number  0-based global index of items[1]
--- @param range_start number  0-based global start (inclusive)
--- @param range_end number  0-based global end (exclusive)
--- @return table[]
function M.extract_range(items, cache_start, range_start, range_end)
  local result = {}
  for i = range_start - cache_start + 1, range_end - cache_start do
    result[#result + 1] = items[i]
  end
  return result
end

--- Find the 1-based index of an envelope by its ID string.
--- Returns nil if not found.
--- @param envelopes table[]
--- @param email_id string
--- @return number|nil
function M.find_envelope_index(envelopes, email_id)
  for i, env in ipairs(envelopes) do
    if tostring(env.id) == email_id then return i end
  end
  return nil
end

return M
