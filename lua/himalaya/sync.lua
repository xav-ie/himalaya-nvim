local config = require('himalaya.config')
local request = require('himalaya.request')
local job = require('himalaya.job')
local win = require('himalaya.ui.win')
local events = require('himalaya.events')

local M = {}

-- Module-local state
local timer = nil
local sync_job = nil
local generation = 0

--- Cancel the in-flight sync job, if any.
function M.cancel()
  generation = generation + 1
  if sync_job then
    job.kill_and_wait(sync_job)
    sync_job = nil
  end
end

--- Stop the sync timer and cancel any in-flight job.
function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  M.cancel()
end

--- Collect the set of email IDs from buffer lines.
--- @param bufnr number
--- @return table<string, boolean>
local function ids_from_buffer(bufnr)
  local listing = require('himalaya.ui.listing')
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local set = {}
  for _, line in ipairs(lines) do
    local id = listing.get_email_id_from_line(line)
    if id ~= '' then
      set[id] = true
    end
  end
  return set
end

--- Collect the set of email IDs from an envelope list.
--- @param envelopes table[]
--- @return table<string, boolean>
local function ids_from_envelopes(envelopes)
  local set = {}
  for _, env in ipairs(envelopes) do
    set[tostring(env.id)] = true
  end
  return set
end

--- Check whether two ID sets are identical.
--- @param a table<string, boolean>
--- @param b table<string, boolean>
--- @return boolean
local function sets_equal(a, b)
  for k in pairs(a) do
    if not b[k] then
      return false
    end
  end
  for k in pairs(b) do
    if not a[k] then
      return false
    end
  end
  return true
end

--- Count IDs present in `new_set` but not in `old_set`.
--- @param old_set table<string, boolean>
--- @param new_set table<string, boolean>
--- @return number count
--- @return string[] new_ids
local function diff_new(old_set, new_set)
  local count = 0
  local ids = {}
  for k in pairs(new_set) do
    if not old_set[k] then
      count = count + 1
      ids[#ids + 1] = k
    end
  end
  return count, ids
end

--- Run one sync cycle. Called by the timer callback via vim.schedule().
function M.poll()
  local email = require('himalaya.domain.email')
  local thread_listing = require('himalaya.domain.email.thread_listing')

  -- Find a visible listing buffer
  local listing_win, bufnr, buf_type = win.find_by_buftype({ 'listing', 'thread-listing' })
  if not listing_win then
    return
  end

  -- Skip if user jobs are in-flight (DB lock safety)
  if email.is_busy() or thread_listing.is_busy() then
    return
  end

  -- Skip if a sync job is already running
  if sync_job then
    return
  end

  local account = vim.b[bufnr].himalaya_account
  local folder = vim.b[bufnr].himalaya_folder or 'INBOX'

  if not account or account == '' then
    return
  end

  generation = generation + 1
  local my_gen = generation

  local account_flag = require('himalaya.state.account').flag

  if buf_type == 'thread-listing' then
    -- Thread mode: re-fetch thread edges
    local query = vim.b[bufnr].himalaya_query or ''
    sync_job = request.json({
      cmd = 'envelope thread --folder %q %s %s',
      args = { folder, account_flag(account), query },
      msg = 'Background sync (threads)',
      silent = true,
      is_stale = function()
        return my_gen ~= generation
      end,
      on_error = function()
        sync_job = nil
      end,
      on_data = function(data)
        sync_job = nil
        if not vim.api.nvim_win_is_valid(listing_win) then
          return
        end

        -- Build new ID set from edges
        local new_ids_set = {}
        for _, edge in ipairs(data) do
          if edge.id then
            new_ids_set[tostring(edge.id)] = true
          end
        end
        local old_ids = ids_from_buffer(bufnr)

        if sets_equal(old_ids, new_ids_set) then
          return
        end

        local new_count, new_id_list = diff_new(old_ids, new_ids_set)

        -- Refresh thread listing in-place
        vim.api.nvim_win_call(listing_win, function()
          local view = vim.fn.winsaveview()
          local tree = require('himalaya.domain.email.tree')
          local cfg = config.get()
          local rows = tree.build(data, { reverse = cfg.thread_reverse })
          tree.build_prefix(rows, { reverse = cfg.thread_reverse })

          -- Pre-populate flags from existing cache
          local ok, cached_envs = pcall(vim.api.nvim_buf_get_var, bufnr, 'himalaya_envelopes')
          if ok and cached_envs then
            local id_map = {}
            for _, env in ipairs(cached_envs) do
              id_map[tostring(env.id)] = env
            end
            for _, row in ipairs(rows) do
              local flat = id_map[tostring(row.env.id)]
              if flat then
                row.env.flags = flat.flags
                row.env.has_attachment = flat.has_attachment
              end
            end
          end

          thread_listing._set_state(rows, 1)
          thread_listing.render_page(1, { restore_cursor = { view.lnum, view.col } })
          vim.fn.winrestview(view)
        end)

        if new_count > 0 then
          vim.notify(string.format('%d new in %s', new_count, folder), vim.log.levels.INFO)
          events.emit('NewMail', {
            account = account,
            folder = folder,
            count = new_count,
            new_ids = new_id_list,
          })
        end
      end,
    })
  else
    -- Flat mode: re-fetch envelope list
    local page = vim.b[bufnr].himalaya_page or 1
    local page_size = vim.b[bufnr].himalaya_page_size or 50
    local query = vim.b[bufnr].himalaya_query or ''

    sync_job = request.json({
      cmd = 'envelope list --folder %q %s --page-size %d --page %d %s',
      args = { folder, account_flag(account), page_size, page, query },
      msg = 'Background sync',
      silent = true,
      is_stale = function()
        return my_gen ~= generation
      end,
      on_error = function()
        sync_job = nil
      end,
      on_data = function(data)
        sync_job = nil
        if not vim.api.nvim_win_is_valid(listing_win) then
          return
        end

        local new_ids = ids_from_envelopes(data)
        local old_ids = ids_from_buffer(bufnr)

        if sets_equal(old_ids, new_ids) then
          return
        end

        local new_count, new_id_list = diff_new(old_ids, new_ids)

        -- Refresh listing buffer in-place
        vim.api.nvim_win_call(listing_win, function()
          local view = vim.fn.winsaveview()
          local renderer = require('himalaya.ui.renderer')
          local listing = require('himalaya.ui.listing')
          local email_mod = require('himalaya.domain.email')

          local result = renderer.render(data, email_mod._bufwidth())
          vim.bo[bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
          listing.apply_header(bufnr, result.header)
          listing.apply_highlights(bufnr, data)
          vim.bo[bufnr].modifiable = false
          vim.b[bufnr].himalaya_envelopes = data
          vim.fn.winrestview(view)
        end)

        if new_count > 0 then
          vim.notify(string.format('%d new in %s', new_count, folder), vim.log.levels.INFO)
          events.emit('NewMail', {
            account = account,
            folder = folder,
            count = new_count,
            new_ids = new_id_list,
          })
        end
      end,
    })
  end
end

--- Start the background sync timer. Idempotent — if already running, no-op.
function M.start()
  local cfg = config.get()
  if not cfg.background_sync then
    return
  end
  if timer then
    return
  end
  local interval_ms = (cfg.sync_interval or 60) * 1000
  timer = vim.uv.new_timer()
  timer:start(
    interval_ms,
    interval_ms,
    vim.schedule_wrap(function()
      M.poll()
    end)
  )
end

--- Test-only accessors
function M._get_timer()
  return timer
end

function M._get_sync_job()
  return sync_job
end

function M._get_generation()
  return generation
end

function M._reset()
  M.stop()
  generation = 0
end

return M
