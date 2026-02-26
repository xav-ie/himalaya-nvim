local config = require('himalaya.config')
local job = require('himalaya.job')
local log = require('himalaya.log')

local M = {}

function M._build_cmd(cmd_fmt, args, output_mode)
  local cfg = config.get()
  local parts = { cfg.executable, '--output', output_mode }

  if cfg.config_path then
    table.insert(parts, '--config')
    table.insert(parts, cfg.config_path)
  end

  -- Parse the format string token by token instead of using string.format
  -- then splitting by whitespace (which breaks folder names with spaces).
  -- Format specifiers:
  --   %s = split by whitespace (for multi-token fragments like account flags, queries)
  --   %q = single token, kept as-is (for values like folder names that may contain spaces)
  --   %d = numeric, converted to string
  local arg_idx = 0
  local pos = 1
  while pos <= #cmd_fmt do
    local spec_start, spec_end, spec = cmd_fmt:find('(%%[qsd])', pos)
    if spec_start then
      local static = cmd_fmt:sub(pos, spec_start - 1)
      for word in static:gmatch('%S+') do
        table.insert(parts, word)
      end
      arg_idx = arg_idx + 1
      local val = args[arg_idx]
      if spec == '%q' then
        if val ~= nil and tostring(val) ~= '' then
          table.insert(parts, tostring(val))
        end
      elseif spec == '%d' then
        table.insert(parts, tostring(val))
      else -- %s: split by whitespace (preserves current behavior)
        local s = tostring(val)
        if s ~= '' then
          for word in s:gmatch('%S+') do
            table.insert(parts, word)
          end
        end
      end
      pos = spec_end + 1
    else
      local static = cmd_fmt:sub(pos)
      for word in static:gmatch('%S+') do
        table.insert(parts, word)
      end
      break
    end
  end

  return parts
end

local function on_exit(cmd, opts, parse_fn)
  return function(stdout, stderr, code)
    -- When the caller provides is_stale(), bail out before any work.
    -- This lets killed-job callbacks exit immediately without parsing,
    -- logging, or invoking any user callbacks.
    if opts.is_stale and opts.is_stale() then
      return
    end

    local cmd_str = table.concat(cmd, ' ')
    log.debug('[himalaya] cmd: %s', cmd_str)
    log.debug('[himalaya] exit code: %d', code)
    if stderr ~= '' then
      log.debug('[himalaya] stderr: %s', stderr)
    end
    if stdout ~= '' then
      log.debug('[himalaya] stdout (%d chars): %s', #stdout, stdout:sub(1, 200))
    end

    if code ~= 0 then
      if not opts.silent then
        local msg = string.format('%s [FAIL] (exit code %d)', opts.msg, code)
        if stderr ~= '' then
          -- Show only the first meaningful line to avoid dumping backtraces
          local first_line = stderr:match('^[^\n]+') or stderr
          msg = msg .. ': ' .. first_line
        end
        log.err(msg)
      end
      if opts.on_error then
        opts.on_error()
      end
      return
    end

    -- CLI may exit 0 but write errors to stderr (e.g. query parse failures).
    -- Strip ANSI escapes and check for the standard "Error:" prefix.
    if stderr ~= '' then
      local plain_stderr = stderr:gsub('\27%[[%d;]*m', '')
      if plain_stderr:match('^%s*Error:') then
        if not opts.silent then
          local first_line = plain_stderr:match('^%s*Error:%s*([^\n]+)') or plain_stderr:match('^[^\n]+')
          log.err(string.format('%s: %s', opts.msg, first_line))
        end
        if opts.on_error then
          opts.on_error()
        end
        return
      end
    end

    local data = parse_fn(stdout)
    if data == nil then
      if opts.on_error then
        opts.on_error()
      end
      return
    end
    opts.on_data(data)
    vim.cmd('redraw')
  end
end

function M.json(opts)
  local mock = require('himalaya.mock')
  if mock.enabled() then
    return mock.json(opts)
  end

  local args = opts.args or {}
  local cmd = M._build_cmd(opts.cmd, args, 'json')

  return job.run(cmd, {
    stdin = opts.stdin,
    on_exit = on_exit(cmd, opts, function(stdout)
      if stdout:match('^%s*$') then
        return {}
      end
      local ok, data = pcall(vim.json.decode, stdout)
      if not ok then
        if not opts.silent then
          log.err('Failed to parse JSON: ' .. stdout)
        end
        return nil
      end
      return data
    end),
  })
end

function M.plain(opts)
  local mock = require('himalaya.mock')
  if mock.enabled() then
    return mock.plain(opts)
  end

  local args = opts.args or {}
  local cmd = M._build_cmd(opts.cmd, args, 'plain')

  return job.run(cmd, {
    stdin = opts.stdin,
    on_exit = on_exit(cmd, opts, function(stdout)
      return stdout
    end),
  })
end

return M
