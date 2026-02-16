local M = {}

function M.select(callback, folders)
  local names = {}
  for _, f in ipairs(folders) do
    table.insert(names, f.name)
  end

  vim.ui.select(names, { prompt = 'Select folder: ' }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

return M
