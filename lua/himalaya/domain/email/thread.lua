local M = {}

function M.fold(line)
  if line:sub(1, 1) == '>' then
    return '1'
  end
  return nil
end

function M.foldexpr(lnum)
  return M.fold(vim.fn.getline(lnum)) or '0'
end

return M
