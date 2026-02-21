local M = {}

function M.info(msg)
  vim.notify(msg, vim.log.levels.INFO)
end

function M.warn(msg)
  vim.notify(msg, vim.log.levels.WARN)
end

function M.err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

--- Write debug trace to :messages when `vim.g.himalaya_debug` is set.
--- Accepts printf-style arguments to avoid string allocation when disabled.
--- @param fmt string  format string (or plain message)
--- @param ... any     format arguments
function M.debug(fmt, ...)
  if not vim.g.himalaya_debug then return end
  local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
  vim.api.nvim_echo({{ msg, 'Comment' }}, true, {})
end

return M
