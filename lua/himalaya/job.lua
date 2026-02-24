local M = {}

--- Kill a vim.system handle and wait for the process to exit.
--- This ensures the CLI's database lock is released before returning.
--- @param handle userdata  vim.system handle
function M.kill_and_wait(handle)
  if not handle then
    return
  end
  handle:kill()
  pcall(handle.wait, handle, 500)
end

function M.run(cmd, opts)
  local sys_opts = {
    text = true,
    env = { RUST_LOG = 'off' },
  }

  if opts.stdin then
    sys_opts.stdin = opts.stdin
  end

  return vim.system(cmd, sys_opts, function(result)
    vim.schedule(function()
      opts.on_exit(result.stdout or '', result.stderr or '', result.code)
    end)
  end)
end

return M
