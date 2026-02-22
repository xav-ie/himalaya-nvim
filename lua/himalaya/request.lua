local config = require('himalaya.config')
local job = require('himalaya.job')
local log = require('himalaya.log')

local M = {}

function M._build_cmd(cmd_fmt, args, output_mode)
  local cfg = config.get()
  local subcmd = #args > 0 and string.format(cmd_fmt, unpack(args)) or cmd_fmt

  local parts = { cfg.executable, '--output', output_mode }

  if cfg.config_path then
    table.insert(parts, '--config')
    table.insert(parts, cfg.config_path)
  end

  for word in subcmd:gmatch('%S+') do
    table.insert(parts, word)
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
