local request = require('himalaya.request')

local M = {}

local totals = {}
local last_account = nil
local last_folder = nil
local last_query = nil
local job = nil
local saved_args = nil
local generation = 0

--- Compute total pages string from totals cache.
--- @param cache_key string
--- @param page_size number
--- @return string
function M.total_pages_str(cache_key, page_size)
  local total = totals[cache_key]
  if not total then return '?' end
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
  if not total or total < 0 then return nil end
  return total
end

--- Reset totals when account, folder, or query changes.
--- @param acct_flag string
--- @param folder string
--- @param qry string
function M.reset_if_changed(acct_flag, folder, qry)
  if acct_flag ~= last_account or folder ~= last_folder or qry ~= last_query then
    totals = {}
    last_account = acct_flag
    last_folder = folder
    last_query = qry
  end
end

--- Record total from initial listing data if deterministic.
--- @param cache_key string
--- @param page number
--- @param page_size number
--- @param data_count number
function M.set_total_from_data(cache_key, page, page_size, data_count)
  if not totals[cache_key] and data_count < page_size then
    totals[cache_key] = (page - 1) * page_size + data_count
  end
end

--- Run probe for a specific page.
--- @param acct_flag string pre-computed '--account <name>' flag
--- @param folder string
--- @param page_size number
--- @param probe_page number
--- @param qry string
--- @param bufnr number
local function run_probe(acct_flag, folder, page_size, probe_page, qry, bufnr)
  generation = generation + 1
  local my_gen = generation
  saved_args = { acct_flag, folder, page_size, probe_page, qry, bufnr }
  job = request.json({
    cmd = 'envelope list --folder %s %s --page-size %d --page %d %s',
    args = {
      folder,
      acct_flag,
      page_size,
      probe_page,
      qry,
    },
    msg = string.format('Probing page %d', probe_page),
    silent = true,
    on_data = function(data)
      if my_gen ~= generation then return end
      local cache_key = acct_flag .. '\0' .. folder .. '\0' .. qry
      if #data < page_size then
        totals[cache_key] = (probe_page - 1) * page_size + #data
        job = nil
        saved_args = nil
      elseif probe_page >= 10 then
        totals[cache_key] = -(probe_page * page_size)
        job = nil
        saved_args = nil
      else
        run_probe(acct_flag, folder, page_size, probe_page + 1, qry, bufnr)
        return
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        local ok, page = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_page')
        local ok2, cur_page_size = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_page_size')
        if ok and ok2 then
          local display_qry = qry == '' and 'all' or qry
          local new_name = string.format('Himalaya/envelopes [%s] [%s] [page %d⁄%s]', folder, display_qry, page, M.total_pages_str(cache_key, cur_page_size))
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
          vim.cmd('redraw')
        end
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
    run_probe(acct_flag, folder, page_size, page + 1, qry, bufnr)
  end
end

--- Cancel a running probe, preserving its args for later restart.
--- Blocks until the process exits to ensure the database lock is released.
function M.cancel()
  if job then
    generation = generation + 1
    job:kill()
    if not job:wait(3000) then
      job:kill(9)
      job:wait(1000)
    end
    job = nil
  end
end

--- Restart a previously cancelled probe.
function M.restart()
  if saved_args then
    local args = saved_args
    saved_args = nil
    run_probe(unpack(args))
  end
end

return M
