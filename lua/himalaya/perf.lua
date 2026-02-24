--- Lightweight performance measurement for resize rendering.
---
--- Interactive use (prints to :messages after each resize):
---   require('himalaya.perf').enable({ notify = true })
---
--- Silent collection (benchmarks use snapshot() / write()):
---   require('himalaya.perf').enable()
---
--- Disable:
---   require('himalaya.perf').disable()

local M = {}

local enabled = false
local notify = false -- whether report() prints to vim.notify
local timers = {} -- name → { start, elapsed_ms }
local counters = {} -- name → count

--- Enable measurement collection.
--- @param opts? { notify: boolean }  if notify=true, report() prints to vim.notify
function M.enable(opts)
  enabled = true
  notify = opts and opts.notify or false
end

function M.disable()
  enabled = false
  notify = false
end

function M.is_enabled()
  return enabled
end

--- Reset all timers and counters for a new measurement cycle.
function M.reset()
  timers = {}
  counters = {}
end

--- Start a named timer.
--- @param name string
function M.start(name)
  if not enabled then
    return
  end
  timers[name] = { start = vim.fn.reltime(), elapsed_ms = 0 }
end

--- Stop a named timer and accumulate elapsed time.
--- @param name string
function M.stop(name)
  if not enabled then
    return
  end
  local t = timers[name]
  if not t then
    return
  end
  t.elapsed_ms = t.elapsed_ms + vim.fn.reltimefloat(vim.fn.reltime(t.start)) * 1000
end

--- Increment a named counter.
--- @param name string
function M.count(name)
  if not enabled then
    return
  end
  counters[name] = (counters[name] or 0) + 1
end

--- Return a plain table snapshot of current timers and counters.
--- @return table { timers = { name = ms, ... }, counters = { name = n, ... } }
function M.snapshot()
  local t = {}
  for name, data in pairs(timers) do
    t[name] = data.elapsed_ms
  end
  local c = {}
  for name, n in pairs(counters) do
    c[name] = n
  end
  return { timers = t, counters = c }
end

--- Report all timers and counters via vim.notify (only when notify=true).
function M.report()
  if not enabled or not notify then
    return
  end
  local lines = { 'himalaya perf:' }
  local tnames = {}
  for name in pairs(timers) do
    table.insert(tnames, name)
  end
  table.sort(tnames)
  for _, name in ipairs(tnames) do
    table.insert(lines, string.format('  %s: %.2fms', name, timers[name].elapsed_ms))
  end
  local cnames = {}
  for name in pairs(counters) do
    table.insert(cnames, name)
  end
  table.sort(cnames)
  for _, name in ipairs(cnames) do
    table.insert(lines, string.format('  %s: %d calls', name, counters[name]))
  end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

--- Write a results table to a JSON file (appends to an array).
--- @param path string  absolute path to output file
--- @param results table  array of { label, timers, counters } entries
function M.write(path, results)
  local json = vim.json.encode(results)
  local f = io.open(path, 'w')
  if not f then
    error('perf: cannot open ' .. path)
  end
  f:write(json .. '\n')
  f:close()
end

return M
