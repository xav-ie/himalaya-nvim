local M = {}

function M.select(callback, folders)
  local fzf_lua = require('fzf-lua')

  local names = {}
  for _, f in ipairs(folders) do
    table.insert(names, f.name)
  end

  fzf_lua.fzf_exec(names, {
    prompt = 'Folders> ',
    actions = {
      ['default'] = function(selected)
        callback(selected[1])
      end,
    },
  })
end

return M
