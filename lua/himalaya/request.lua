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

function M.json(opts)
  local args = opts.args or {}
  log.info(string.format('%s...', opts.msg))
  local cmd = M._build_cmd(opts.cmd, args, 'json')

  job.run(cmd, {
    stdin = opts.stdin,
    on_exit = function(stdout, stderr, code)
      if code ~= 0 and stderr ~= '' then
        log.err(stderr)
        return
      end
      local ok, data = pcall(vim.json.decode, stdout)
      if not ok then
        log.err('Failed to parse JSON: ' .. stdout)
        return
      end
      opts.on_data(data)
      vim.cmd('redraw')
      log.info(string.format('%s [OK]', opts.msg))
    end,
  })
end

function M.plain(opts)
  local args = opts.args or {}
  log.info(string.format('%s...', opts.msg))
  local cmd = M._build_cmd(opts.cmd, args, 'plain')

  job.run(cmd, {
    stdin = opts.stdin,
    on_exit = function(stdout, stderr, code)
      if code ~= 0 and stderr ~= '' then
        log.err(stderr)
        return
      end
      opts.on_data(stdout)
      vim.cmd('redraw')
      log.info(string.format('%s [OK]', opts.msg))
    end,
  })
end

return M
