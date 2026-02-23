#!/usr/bin/env -S nvim --headless -l
--- Generate doc sections from source and inject them between GEN markers.
---
--- Usage:
---   nvim --headless -l scripts/gen-docs.lua
---   nix run .#gen-docs
---
--- Markers in target files:
---   <!-- GEN:name -->
---   ...replaced content...
---   <!-- /GEN:name -->

local script_path = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(script_path, ':p:h:h')

-- ── IO helpers ────────────────────────────────────────────────────────────────

local function read(path)
  local f = assert(io.open(path, 'r'), 'cannot read ' .. path)
  local s = f:read('*a')
  f:close()
  return s
end

local function write(path, content)
  local f = assert(io.open(path, 'w'), 'cannot write ' .. path)
  f:write(content)
  f:close()
end

-- ── Template injection ────────────────────────────────────────────────────────

--- Replace the content between <!-- GEN:name --> and <!-- /GEN:name --> markers.
local function inject(doc, name, content)
  local open = '<!-- GEN:' .. name .. ' -->'
  local close = '<!-- /GEN:' .. name .. ' -->'
  local s = doc:find(open, 1, true)
  local e = doc:find(close, 1, true)
  assert(s, 'marker GEN:' .. name .. ' not found')
  assert(e, 'marker /GEN:' .. name .. ' not found')
  return doc:sub(1, s + #open - 1) .. '\n' .. content .. '\n' .. doc:sub(e)
end

-- ── Generators ───────────────────────────────────────────────────────────────

--- Build the annotated config block from config.lua's defaults table.
local function gen_config()
  local src = read(root .. '/lua/himalaya/config.lua')
  local lines = vim.split(src, '\n')
  local result, depth, started = {}, 0, false

  for _, line in ipairs(lines) do
    if not started then
      if line:match('^local defaults = {') then
        started = true
        depth = 1
        result[#result + 1] = line:gsub('^local defaults = {', "require('himalaya').setup({")
      end
    else
      for ch in line:gmatch('.') do
        if ch == '{' then
          depth = depth + 1
        elseif ch == '}' then
          depth = depth - 1
        end
      end
      if depth == 0 then
        result[#result + 1] = line:gsub('^}', '})')
        break
      else
        result[#result + 1] = line
      end
    end
  end

  assert(#result > 0, 'could not find defaults block in config.lua')
  return '```lua\n' .. table.concat(result, '\n') .. '\n```'
end

--- Build the events table from the catalog in events.lua.
local function gen_events()
  package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
  local events = require('himalaya.events')

  local rows = {
    '| Event | Payload |',
    '|-------|---------|',
  }
  for _, e in ipairs(events.catalog) do
    local payload = '`{ ' .. table.concat(e.payload, ', ') .. ' }`'
    if e.note then
      payload = payload .. ' — ' .. e.note
    end
    rows[#rows + 1] = '| `' .. e.name .. '` | ' .. payload .. ' |'
  end
  return table.concat(rows, '\n')
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local config_block = gen_config()
local events_table = gen_events()

local readme_path = root .. '/README.md'
local readme = read(readme_path)
readme = inject(readme, 'config', config_block)
write(readme_path, readme)
print('  README.md       GEN:config')

local contrib_path = root .. '/CONTRIBUTING.md'
local contrib = read(contrib_path)
contrib = inject(contrib, 'events', events_table)
write(contrib_path, contrib)
print('  CONTRIBUTING.md GEN:events')
