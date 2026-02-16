local M = {}

function M.select(callback, folders)
  local names = {}
  for _, f in ipairs(folders) do
    table.insert(names, f.name)
  end

  vim.fn['fzf#run']({
    source = names,
    sink = callback,
    down = '25%',
  })
end

return M
