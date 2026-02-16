local M = {}

function M.define(bufnr, bindings)
  for _, binding in ipairs(bindings) do
    local mode, key, callback, name = binding[1], binding[2], binding[3], binding[4]
    local plug = '<Plug>(himalaya-' .. name .. ')'

    vim.keymap.set(mode, plug, callback, { silent = true, desc = 'Himalaya: ' .. name })

    if vim.fn.hasmapto(plug, mode) == 0 then
      vim.keymap.set(mode, key, plug, { buffer = bufnr, nowait = true })
    end
  end
end

return M
