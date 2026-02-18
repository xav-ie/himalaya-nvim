local M = {}
local current_folder = 'INBOX'
local current_page = 1

function M.current()
  return current_folder
end

function M.current_page()
  return current_page
end

function M.set(name)
  current_folder = name
  current_page = 1
end

function M.next_page()
  current_page = current_page + 1
end

function M.previous_page()
  current_page = math.max(1, current_page - 1)
end

function M.set_page(n)
  current_page = math.max(1, n)
end

return M
