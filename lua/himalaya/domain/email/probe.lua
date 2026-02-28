local request = require('himalaya.request')
local log = require('himalaya.log')

local M = {}

local totals = {}
local job = nil
local saved_args = nil
local generation = 0
local on_cancel_cb = nil

--- Compute total pages string from totals cache.
--- @param cache_key string
--- @param page_size number
--- @return string
function M.total_pages_str(cache_key, page_size)
  local total = totals[cache_key]
  if not total then
    return '?'
  end
  if total < 0 then
    return tostring(math.ceil(-total / page_size)) .. '+'
  end
  return tostring(math.ceil(total / page_size))
end

--- Return the known total envelope count for a cache key, or nil if unknown.
--- @param cache_key string
--- @return number|nil
function M.total_count(cache_key)
  local total = totals[cache_key]
  if not total or total < 0 then
    return nil
  end
  return total
end

--- Track context changes (no longer wipes totals — entries are keyed by
--- (acct, folder, query) and persist across folder/account switches).
--- @param acct_flag string
--- @param folder string
--- @param qry string
function M.reset_if_changed(_acct_flag, _folder, _qry) end

--- Record or validate total from initial listing data.
--- When the data is a partial page, the exact total is deterministic — always
--- set it (overwriting any stale cached value from a previous visit).
--- When the data is a full page, invalidate any cached total that is too low
--- so the probe re-runs and discovers the real count.
--- @param cache_key string
--- @param page number
--- @param page_size number
--- @param data_count number
function M.set_total_from_data(cache_key, page, page_size, data_count)
  if data_count < page_size then
    totals[cache_key] = (page - 1) * page_size + data_count
  else
    local min_items = (page - 1) * page_size + data_count
    local cached = totals[cache_key]
    if cached and cached > 0 and cached < min_items then
      totals[cache_key] = nil
    end
  end
end

--- Run probe for a specific page.
--- @param acct_flag string pre-computed '--account <name>' flag
--- @param folder string
--- @param page_size number
--- @param probe_page number
--- @param qry string
--- @param bufnr number
--- @param upper_bound? number  highest page known to be out of bounds
local function run_probe(acct_flag, folder, page_size, probe_page, qry, bufnr, upper_bound)
  generation = generation + 1
  local my_gen = generation
  saved_args = { acct_flag, folder, page_size, probe_page, qry, bufnr, upper_bound }
  job = request.json({
    cmd = 'envelope list --folder %q %s --page-size %d --page %d %s',
    args = {
      folder,
      acct_flag,
      page_size,
      probe_page,
      qry,
    },
    msg = string.format('Probing page %d', probe_page),
    silent = true,
    on_error = function()
      log.debug('[probe] on_error: probe page %d failed, gen=%d', probe_page, my_gen)
      job = nil
      if my_gen ~= generation then
        -- Cancelled: fire callback without retrying.
        if on_cancel_cb then
          local cb = on_cancel_cb
          on_cancel_cb = nil
          cb()
        end
        return
      end
      -- CLI error (e.g. page out of bounds): fall back to previous page,
      -- recording this page as the upper bound so we don't double past it.
      if probe_page > 1 then
        log.debug('[probe] falling back to page %d (upper_bound=%d)', probe_page - 1, probe_page)
        run_probe(acct_flag, folder, page_size, probe_page - 1, qry, bufnr, probe_page)
      else
        if on_cancel_cb then
          local cb = on_cancel_cb
          on_cancel_cb = nil
          cb()
        end
      end
    end,
    on_data = function(data)
      if my_gen ~= generation then
        -- Stale: process completed before kill signal arrived.
        log.debug('[probe] on_data: STALE my_gen=%d gen=%d', my_gen, generation)
        job = nil
        if on_cancel_cb then
          local cb = on_cancel_cb
          on_cancel_cb = nil
          cb()
        end
        return
      end
      local cache_key = acct_flag .. '\0' .. folder .. '\0' .. qry
      log.debug('[probe] on_data: page=%d #data=%d ps=%d ub=%s', probe_page, #data, page_size, tostring(upper_bound))
      if #data < page_size then
        totals[cache_key] = (probe_page - 1) * page_size + #data
        log.debug('[probe] total resolved: %d', totals[cache_key])
        job = nil
        saved_args = nil
      elseif upper_bound and probe_page + 1 >= upper_bound then
        -- Full page but next page is out of bounds: total is exactly
        -- probe_page * page_size.
        totals[cache_key] = probe_page * page_size
        log.debug('[probe] total resolved (at upper bound): %d', totals[cache_key])
        job = nil
        saved_args = nil
      elseif probe_page >= 10 then
        totals[cache_key] = -(probe_page * page_size)
        log.debug('[probe] total capped: %d+', -totals[cache_key])
        job = nil
        saved_args = nil
      else
        local next_page
        if upper_bound then
          -- Linear scan upward within known bounds
          next_page = probe_page + 1
        else
          next_page = math.min(probe_page * 2, 10)
        end
        log.debug('[probe] continuing to page %d', next_page)
        run_probe(acct_flag, folder, page_size, next_page, qry, bufnr, upper_bound)
        return
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        local ok, page = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_page')
        local ok2, cur_page_size = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_page_size')
        log.debug('[probe] buf valid, page ok=%s (%s), ps ok=%s (%s)', tostring(ok), tostring(page), tostring(ok2), tostring(cur_page_size))
        if ok and ok2 then
          local display_qry = qry == '' and 'all' or qry
          local new_name = string.format(
            'Himalaya/envelopes [%s] [%s] [page %d⁄%s]',
            folder,
            display_qry,
            page,
            M.total_pages_str(cache_key, cur_page_size)
          )
          -- Wipe stale envelope buffers that would conflict with the rename.
          -- Rapid account switching can leave orphan listing buffers when
          -- on_list_with's async callback fires while a picker has focus.
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if b ~= bufnr and vim.api.nvim_buf_is_valid(b) then
              local bname = vim.api.nvim_buf_get_name(b)
              if bname:find('Himalaya/envelopes', 1, true) then
                vim.cmd('silent! bwipeout ' .. b)
              end
            end
          end
          vim.api.nvim_buf_set_name(bufnr, new_name)
          log.debug('[probe] buf renamed: %s', new_name)
          vim.cmd('redraw')
        end
      else
        log.debug('[probe] buf %d invalid, skipping rename', bufnr)
      end
    end,
  })
end

--- Start probing from page+1 if total is unknown.
--- @param acct_flag string pre-computed '--account <name>' flag
--- @param folder string
--- @param page_size number
--- @param page number current page
--- @param qry string
--- @param bufnr number
function M.start(acct_flag, folder, page_size, page, qry, bufnr)
  local cache_key = acct_flag .. '\0' .. folder .. '\0' .. qry
  if not totals[cache_key] then
    log.debug('[probe] start: probing page %d, ps=%d, bufnr=%d', page + 1, page_size, bufnr)
    run_probe(acct_flag, folder, page_size, page + 1, qry, bufnr)
  else
    log.debug('[probe] start: total already known (%s), skipping', tostring(totals[cache_key]))
  end
end

--- Cancel a running probe, preserving its args for later restart.
--- Non-blocking: sends SIGTERM and invokes callback when the process exits
--- (via on_error or stale on_data), ensuring the database lock is released
--- before the callback runs.
--- @param callback? function  called once the probe process has exited
function M.cancel(callback)
  if not job then
    if callback then
      callback()
    end
    return
  end
  generation = generation + 1
  -- Fire any previously-queued callback before overwriting, so
  -- callers are never silently discarded.
  if on_cancel_cb then
    local old = on_cancel_cb
    on_cancel_cb = nil
    old()
  end
  on_cancel_cb = callback
  job:kill()
end

--- Cancel a running probe synchronously, waiting for the process to exit.
--- Use before starting a new CLI command to avoid database lock contention.
function M.cancel_sync()
  if not job then
    return
  end
  generation = generation + 1
  on_cancel_cb = nil
  local j = job
  job = nil
  require('himalaya.job').kill_and_wait(j)
end

--- Restart a previously cancelled probe.
function M.restart()
  if saved_args then
    local args = saved_args
    saved_args = nil
    run_probe(unpack(args))
  end
end

--- Clean up all module-local state for buffer teardown.
function M.cleanup()
  log.debug('[probe] cleanup called')
  M.cancel_sync()
  totals = {}
  saved_args = nil
end

return M
