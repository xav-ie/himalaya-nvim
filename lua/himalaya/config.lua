local M = {}

local defaults = {
  executable = 'himalaya',
  config_path = nil,
  folder_picker = nil,
  telescope_preview = false,
  complete_contact_cmd = nil,
  custom_flags = {},
  always_confirm = true,
  use_nerd = false,
  show_unseen_flag = true,
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
  current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

function M.get()
  return current
end

function M._reset()
  current = vim.deepcopy(defaults)
end

return M
