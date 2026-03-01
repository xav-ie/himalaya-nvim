#!/usr/bin/env -S nvim --headless -l
--- Generate doc sections from source and inject them between GEN markers.
---
--- Usage:
---   nvim --headless -l scripts/gen-docs.lua              -- generate docs
---   nvim --headless -l scripts/gen-docs.lua --bump       -- bump media cache version
---   nvim --headless -l scripts/gen-docs.lua --media=5    -- set media cache version to 5
---   nvim --headless -l scripts/gen-docs.lua --salt=b     -- set salt prefix (?v=b1)
---
--- Markers in target files:
---   <!-- GEN:name -->              static content replaced by gen_<name>()
---   <!-- /GEN:name -->
---
---   <!-- GEN:name key="val" -->    content generated from marker attributes
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

--- Parse key="value" attributes from a marker's opening tag.
local function parse_attrs(s)
  local attrs = {}
  for k, v in (s or ''):gmatch('(%w+)="([^"]*)"') do
    attrs[k] = v
  end
  return attrs
end

--- Replace content between every <!-- GEN:name ... --> / <!-- /GEN:name -->
--- pair. Attributes on the opening tag are parsed and passed to `generator`.
local function inject_generated(doc, name, generator)
  local lines = vim.split(doc, '\n')
  local result = {}
  local open_pat = '^<!%-%- GEN:' .. name .. '%s'
  local close_pat = '^<!%-%- /GEN:' .. name .. ' %-%->'
  local i = 1
  while i <= #lines do
    local attr_str = lines[i]:match('^<!%-%- GEN:' .. name .. '%s+(.-) *%-%->')
    if attr_str then
      result[#result + 1] = lines[i]
      result[#result + 1] = generator(parse_attrs(attr_str))
      i = i + 1
      while i <= #lines and not lines[i]:match(close_pat) do
        i = i + 1
      end
      if i <= #lines then
        result[#result + 1] = lines[i]
      end
    else
      result[#result + 1] = lines[i]
    end
    i = i + 1
  end
  return table.concat(result, '\n')
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

-- ── Media cache-busting ─────────────────────────────────────────────────────

local cache_path = root .. '/scripts/.media-cache'

--- Read persisted cache-bust state (version + salt) from scripts/.media-cache.
local function read_cache()
  local f = io.open(cache_path, 'r')
  if not f then
    return 1, nil
  end
  local t = {}
  for line in f:lines() do
    local k, v = line:match('^(%w+)=(.*)$')
    if k then
      t[k] = v
    end
  end
  f:close()
  return tonumber(t.version) or 1, t.salt ~= '' and t.salt or nil
end

--- Persist cache-bust state to scripts/.media-cache.
local function write_cache(version, salt)
  local f = assert(io.open(cache_path, 'w'), 'cannot write ' .. cache_path)
  f:write('version=' .. version .. '\n')
  f:write('salt=' .. (salt or '') .. '\n')
  f:close()
end

local media_version, media_salt = read_cache()

--- Generate an SVG + video-link block from marker attributes.
--- Expects: src="name" alt="Alt text"
local function gen_media(attrs)
  local base = 'https://himalaya-nvim.xav.ie'
  local qs = '?v=' .. (media_salt or '') .. media_version
  return string.format(
    '<img src="%s/%s.svg%s" width="100%%" alt="%s">\n'
      .. '<p align="center"><a href="%s/%s.mp4%s">▶ Watch as video</a></p>',
    base,
    attrs.src,
    qs,
    attrs.alt,
    base,
    attrs.src,
    qs
  )
end

-- ── Main ─────────────────────────────────────────────────────────────────────

-- Parse CLI args — flags update persisted state
local cache_dirty = false
if arg then
  for _, a in ipairs(arg) do
    if a == '--bump' then
      media_version = media_version + 1
      cache_dirty = true
    else
      local n = a:match('^%-%-media=(%d+)$')
      if n then
        media_version = tonumber(n)
        cache_dirty = true
      end
      local s = a:match('^%-%-salt=(.*)$')
      if s then
        media_salt = s ~= '' and s or nil
        cache_dirty = true
      end
    end
  end
end
if cache_dirty then
  write_cache(media_version, media_salt)
end

local config_block = gen_config()
local events_table = gen_events()

local readme_path = root .. '/README.md'
local readme = read(readme_path)
readme = inject(readme, 'config', config_block)
readme = inject_generated(readme, 'media', gen_media)
write(readme_path, readme)
print('  README.md       GEN:config')
print('  README.md       GEN:media  v=' .. (media_version or '-'))

local contrib_path = root .. '/CONTRIBUTING.md'
local contrib = read(contrib_path)
contrib = inject(contrib, 'events', events_table)
write(contrib_path, contrib)
print('  CONTRIBUTING.md GEN:events')
