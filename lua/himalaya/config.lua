local M = {}

local defaults = {
  executable = 'himalaya',
  config_path = nil,
  folder_picker = nil,
  telescope_preview = false,
  complete_contact_cmd = nil,
  custom_flags = {},
  always_confirm = true,
  flags = {
    header = 'FLGS',
    flagged = '!',
    unseen = '*',
    answered = 'R',
    attachment = '@',
  },
  gutters = true,
  date_format = '%Y-%m-%d %H:%M',
  thread_view = false,
  thread_reverse = false,
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
