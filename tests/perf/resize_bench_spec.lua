--- Performance benchmark for email listing resize rendering.
--- Exercises the real renderer, real apply_highlights,
--- forces redraw to simulate actual screen rendering in headless mode.
---
--- Run via: make perf
--- Results written to: perf-results.json

local ITERATIONS = 20
local WIDTH = 120

-- ── helpers ──────────────────────────────────────────────────────

--- Load real envelope fixture captured from `himalaya envelope list`.
local function load_fixture()
  local path = vim.fn.getcwd() .. '/tests/perf/fixtures/envelopes_50.json'
  local f = io.open(path, 'r')
  if not f then
    error(
      'Missing fixture: '
        .. path
        .. '\nRun: himalaya envelope list --folder INBOX --page-size 50 --page 1 --output json > '
        .. path
    )
  end
  local json = f:read('*a')
  f:close()
  return vim.json.decode(json)
end

local function seed_buffer_lines(bufnr, count)
  vim.bo[bufnr].modifiable = true
  local lines = {}
  for i = 1, count do
    lines[i] = tostring(i)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

local function median(sorted)
  local n = #sorted
  if n == 0 then
    return 0
  end
  if n % 2 == 1 then
    return sorted[math.ceil(n / 2)]
  end
  return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

local function stats(samples)
  if #samples == 0 then
    return { min = 0, max = 0, median = 0, mean = 0 }
  end
  table.sort(samples)
  local sum = 0
  for _, v in ipairs(samples) do
    sum = sum + v
  end
  return {
    min = samples[1],
    max = samples[#samples],
    median = median(samples),
    mean = sum / #samples,
  }
end

local function round2(n)
  return math.floor(n * 100 + 0.5) / 100
end

--- Read current results file (or empty array).
local function read_results()
  local result_path = vim.fn.getcwd() .. '/perf-results.json'
  local results = {}
  pcall(function()
    local f = io.open(result_path, 'r')
    if f then
      results = vim.json.decode(f:read('*a')) or {}
      f:close()
    end
  end)
  return results, result_path
end

--- Append a result entry and write.
local function write_result(entry)
  local results, path = read_results()
  table.insert(results, entry)
  require('himalaya.perf').write(path, results)
end

-- ── benchmark ────────────────────────────────────────────────────

describe('resize perf baseline', function()
  local perf, renderer, listing, email, config
  local original_height
  local envelopes

  before_each(function()
    -- Clear module cache for fresh state
    for k in pairs(package.loaded) do
      if k:match('^himalaya') then
        package.loaded[k] = nil
      end
    end

    -- Stub network/state modules (but NOT renderer/listing/config/perf)
    package.loaded['himalaya.request'] = {
      json = function()
        return nil
      end,
      plain = function()
        return nil
      end,
    }
    package.loaded['himalaya.log'] = {
      info = function() end,
      warn = function() end,
      err = function() end,
      debug = function() end,
    }
    package.loaded['himalaya.state.account'] = {
      current = function()
        return 'bench'
      end,
      select = function() end,
      flag = function(account)
        return account == '' and '' or ('--account ' .. account)
      end,
    }
    package.loaded['himalaya.state.folder'] = {
      current = function()
        return 'INBOX'
      end,
      current_page = function()
        return 1
      end,
      set_page = function() end,
    }
    package.loaded['himalaya.domain.email.probe'] = {
      reset_if_changed = function() end,
      set_total_from_data = function() end,
      total_pages_str = function()
        return '?'
      end,
      start = function() end,
      cancel = function() end,
      restart = function() end,
    }

    -- Load real modules
    config = require('himalaya.config')
    config._reset()
    perf = require('himalaya.perf')
    renderer = require('himalaya.ui.renderer')
    listing = require('himalaya.ui.listing')
    email = require('himalaya.domain.email')

    perf.enable()
    envelopes = load_fixture()

    original_height = vim.api.nvim_win_get_height(0)
  end)

  after_each(function()
    email.cancel_resize()
    perf.disable()
    vim.b.himalaya_buffer_type = nil
    vim.b.himalaya_envelopes = nil
    vim.b.himalaya_page = nil
    vim.b.himalaya_page_size = nil
    vim.b.himalaya_cache_offset = nil
    vim.b.himalaya_query = nil
    pcall(vim.api.nvim_win_set_height, 0, original_height)
  end)

  -- ── renderer.render() ──────────────────────────────────────────

  it('bench: renderer.render()', function()
    local n = #envelopes
    local samples = {}
    for _ = 1, ITERATIONS do
      perf.reset()
      local t0 = vim.fn.reltime()
      renderer.render(envelopes, WIDTH)
      local ms = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
      table.insert(samples, ms)
    end
    local s = stats(samples)
    local snap = perf.snapshot()

    write_result({
      label = 'renderer.render',
      envelopes = n,
      width = WIDTH,
      iterations = ITERATIONS,
      min_ms = round2(s.min),
      max_ms = round2(s.max),
      median_ms = round2(s.median),
      mean_ms = round2(s.mean),
      counters = snap.counters,
    })

    print(
      string.format(
        '\n  renderer.render: min=%.2fms median=%.2fms max=%.2fms (n=%d, %d envs)',
        s.min,
        s.median,
        s.max,
        ITERATIONS,
        n
      )
    )
    print(
      string.format(
        '    fit: %d  strdisplaywidth: %d  format_date: %d',
        snap.counters.fit or 0,
        snap.counters.strdisplaywidth or 0,
        snap.counters.format_date or 0
      )
    )
  end)

  -- ── apply_highlights() + redraw ──────────────────────────────

  it('bench: apply_highlights() + redraw', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local result = renderer.render(envelopes, WIDTH)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
    vim.bo[bufnr].modifiable = false

    local samples = {}
    for _ = 1, ITERATIONS do
      local t0 = vim.fn.reltime()
      listing.apply_highlights(bufnr, envelopes)
      vim.cmd('redraw')
      local ms = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
      table.insert(samples, ms)
    end
    local s = stats(samples)

    write_result({
      label = 'apply_highlights_redraw',
      envelopes = #envelopes,
      iterations = ITERATIONS,
      min_ms = round2(s.min),
      max_ms = round2(s.max),
      median_ms = round2(s.median),
      mean_ms = round2(s.mean),
    })

    print(
      string.format(
        '\n  apply_highlights+redraw: min=%.2fms median=%.2fms max=%.2fms (n=%d, %d envs)',
        s.min,
        s.median,
        s.max,
        ITERATIONS,
        #envelopes
      )
    )
  end)

  -- ── redraw cost (isolated) ────────────────────────────────────

  it('bench: redraw cost (extmarks, no mutation)', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local result = renderer.render(envelopes, WIDTH)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
    vim.bo[bufnr].modifiable = false
    listing.apply_highlights(bufnr, envelopes)

    -- Warm up: first redraw populates internal screen state
    vim.cmd('redraw')

    local samples = {}
    for _ = 1, ITERATIONS do
      local t0 = vim.fn.reltime()
      vim.cmd('redraw')
      local ms = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
      table.insert(samples, ms)
    end
    local s = stats(samples)

    write_result({
      label = 'redraw_only',
      envelopes = #envelopes,
      iterations = ITERATIONS,
      min_ms = round2(s.min),
      max_ms = round2(s.max),
      median_ms = round2(s.median),
      mean_ms = round2(s.mean),
    })

    print(
      string.format(
        '\n  redraw (no mutation): min=%.2fms median=%.2fms max=%.2fms (n=%d)',
        s.min,
        s.median,
        s.max,
        ITERATIONS
      )
    )
  end)

  -- ── resize_listing() height change (Phase 1) + redraw ─────────

  it('bench: resize_listing height change + redraw', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local n = #envelopes

    local result = renderer.render(envelopes, WIDTH)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
    vim.bo[bufnr].modifiable = false
    vim.b.himalaya_buffer_type = 'listing'
    vim.b.himalaya_envelopes = envelopes
    vim.b.himalaya_page = 1
    vim.b.himalaya_page_size = n
    vim.b.himalaya_cache_offset = 0
    vim.b.himalaya_query = ''

    local heights = { math.max(1, n - 10), math.max(1, n - 20) }
    local samples = {}
    local last_snap

    for i = 1, ITERATIONS do
      local h = heights[(i % 2) + 1]
      vim.api.nvim_win_set_height(0, h)
      vim.b.himalaya_page_size = heights[((i + 1) % 2) + 1]
      seed_buffer_lines(bufnr, n)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      perf.reset()
      local t0 = vim.fn.reltime()
      email.resize_listing()
      vim.cmd('redraw')
      local ms = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
      table.insert(samples, ms)
      last_snap = perf.snapshot()

      email.cancel_resize()
    end

    local s = stats(samples)
    write_result({
      label = 'resize_listing_height_change_redraw',
      envelopes = n,
      width = WIDTH,
      iterations = ITERATIONS,
      min_ms = round2(s.min),
      max_ms = round2(s.max),
      median_ms = round2(s.median),
      mean_ms = round2(s.mean),
      last_timers = last_snap and last_snap.timers or {},
      last_counters = last_snap and last_snap.counters or {},
    })

    print(
      string.format(
        '\n  resize_listing (height)+redraw: min=%.2fms median=%.2fms max=%.2fms (n=%d, %d envs)',
        s.min,
        s.median,
        s.max,
        ITERATIONS,
        n
      )
    )
    if last_snap then
      for k, v in pairs(last_snap.timers) do
        print(string.format('    %s: %.2fms', k, v))
      end
      for k, v in pairs(last_snap.counters) do
        print(string.format('    %s: %d calls', k, v))
      end
    end
  end)

  -- ── resize_listing() shrink within cache (no Phase 2) + redraw ─

  it('bench: resize_listing shrink within cache (no Phase 2)', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local n = #envelopes

    local result = renderer.render(envelopes, WIDTH)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
    vim.bo[bufnr].modifiable = false
    vim.b.himalaya_buffer_type = 'listing'
    vim.b.himalaya_envelopes = envelopes
    vim.b.himalaya_page = 1
    vim.b.himalaya_page_size = n
    vim.b.himalaya_cache_offset = 0
    vim.b.himalaya_query = ''

    -- Both heights are smaller than the cache size, so Phase 2 is skipped
    local heights = { math.max(1, n - 10), math.max(1, n - 20) }
    local samples = {}
    local last_snap
    local phase2_called = false
    local orig_json = package.loaded['himalaya.request'].json
    package.loaded['himalaya.request'].json = function(opts)
      phase2_called = true
      return orig_json(opts)
    end

    for i = 1, ITERATIONS do
      local h = heights[(i % 2) + 1]
      vim.api.nvim_win_set_height(0, h)
      vim.b.himalaya_page_size = heights[((i + 1) % 2) + 1]
      seed_buffer_lines(bufnr, n)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      perf.reset()
      local t0 = vim.fn.reltime()
      email.resize_listing()
      vim.cmd('redraw')
      local ms = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
      table.insert(samples, ms)
      last_snap = perf.snapshot()
    end

    package.loaded['himalaya.request'].json = orig_json

    local s = stats(samples)
    write_result({
      label = 'resize_listing_shrink_no_phase2',
      envelopes = n,
      width = WIDTH,
      iterations = ITERATIONS,
      min_ms = round2(s.min),
      max_ms = round2(s.max),
      median_ms = round2(s.median),
      mean_ms = round2(s.mean),
      phase2_fired = phase2_called,
      last_timers = last_snap and last_snap.timers or {},
      last_counters = last_snap and last_snap.counters or {},
    })

    print(
      string.format(
        '\n  resize_listing (shrink, no Phase 2): min=%.2fms median=%.2fms max=%.2fms (n=%d, %d envs)',
        s.min,
        s.median,
        s.max,
        ITERATIONS,
        n
      )
    )
    if last_snap then
      for k, v in pairs(last_snap.timers) do
        print(string.format('    %s: %.2fms', k, v))
      end
    end
    assert.is_false(phase2_called, 'Phase 2 should not fire when cache covers new page')
  end)

  -- ── resize_listing() width-only + redraw ───────────────────────

  it('bench: resize_listing width-only + redraw', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local height = vim.fn.winheight(0)
    local n = #envelopes

    local result = renderer.render(envelopes, WIDTH)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, result.lines)
    vim.bo[bufnr].modifiable = false
    vim.b.himalaya_buffer_type = 'listing'
    vim.b.himalaya_envelopes = envelopes
    vim.b.himalaya_page = 1
    vim.b.himalaya_page_size = height
    vim.b.himalaya_cache_offset = 0
    vim.b.himalaya_query = ''

    local samples = {}
    local last_snap

    for _ = 1, ITERATIONS do
      perf.reset()
      local t0 = vim.fn.reltime()
      email.resize_listing()
      vim.cmd('redraw')
      local ms = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
      table.insert(samples, ms)
      last_snap = perf.snapshot()
    end

    local s = stats(samples)
    write_result({
      label = 'resize_listing_width_only_redraw',
      envelopes = n,
      width = WIDTH,
      iterations = ITERATIONS,
      min_ms = round2(s.min),
      max_ms = round2(s.max),
      median_ms = round2(s.median),
      mean_ms = round2(s.mean),
      last_timers = last_snap and last_snap.timers or {},
      last_counters = last_snap and last_snap.counters or {},
    })

    print(
      string.format(
        '\n  resize_listing (width)+redraw: min=%.2fms median=%.2fms max=%.2fms (n=%d, %d envs)',
        s.min,
        s.median,
        s.max,
        ITERATIONS,
        n
      )
    )
    if last_snap then
      for k, v in pairs(last_snap.timers) do
        print(string.format('    %s: %.2fms', k, v))
      end
      for k, v in pairs(last_snap.counters) do
        print(string.format('    %s: %d calls', k, v))
      end
    end
  end)

  -- ── himalaya CLI call overhead ─────────────────────────────────

  it('bench: himalaya CLI envelope list latency', function()
    local exe = config.get().executable or 'himalaya'
    local cmd = exe .. ' envelope list --folder INBOX --page-size 50 --page 1 --output json'

    -- Check if himalaya is available
    local check = vim.fn.executable(exe)
    if check == 0 then
      print('\n  himalaya CLI: SKIPPED (not found)')
      write_result({
        label = 'himalaya_cli_envelope_list',
        skipped = true,
        reason = exe .. ' not found',
      })
      return
    end

    local samples = {}
    for _ = 1, 5 do -- fewer iterations — real I/O
      local t0 = vim.fn.reltime()
      vim.fn.system(cmd)
      local ms = vim.fn.reltimefloat(vim.fn.reltime(t0)) * 1000
      table.insert(samples, ms)
    end
    local s = stats(samples)

    write_result({
      label = 'himalaya_cli_envelope_list',
      iterations = 5,
      min_ms = round2(s.min),
      max_ms = round2(s.max),
      median_ms = round2(s.median),
      mean_ms = round2(s.mean),
    })

    print(
      string.format(
        '\n  himalaya CLI (envelope list 50): min=%.0fms median=%.0fms max=%.0fms (n=%d)',
        s.min,
        s.median,
        s.max,
        5
      )
    )
  end)
end)
