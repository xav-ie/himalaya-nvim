local M = {}

--- Write a line to /tmp/himalaya-debug.log (temporary debugging aid).
local function trace(msg)
  local f = io.open('/tmp/himalaya-debug.log', 'a')
  if f then
    f:write(os.date('%H:%M:%S') .. ' ' .. msg .. '\n')
    f:close()
  end
end

-- Intercept vim.notify to catch any "parse JSON" error regardless of source.
local _real_notify = vim.notify
vim.notify = function(msg, level, ...)
  if type(msg) == 'string' and msg:find('parse JSON') then
    trace('NOTIFY level=' .. tostring(level) .. ' msg=' .. msg:sub(1, 200)
      .. '\n  ' .. debug.traceback('', 2):gsub('\n', '\n  '))
  end
  return _real_notify(msg, level, ...)
end

function M.info(msg)
  vim.notify(msg, vim.log.levels.INFO)
end

function M.warn(msg)
  vim.notify(msg, vim.log.levels.WARN)
end

function M.err(msg)
  trace('LOG_ERR msg=' .. msg:sub(1, 200) .. '\n  ' .. debug.traceback('', 2):gsub('\n', '\n  '))
  vim.notify(msg, vim.log.levels.ERROR)
end

function M.debug(msg)
  vim.notify(msg, vim.log.levels.DEBUG)
end

return M
