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
  keymaps = {},
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
  current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

function M.get()
  return current
end

--- Set a single config key.
--- @param key string
--- @param value any
function M.set(key, value)
  current[key] = value
end

function M._reset()
  current = vim.deepcopy(defaults)
end

return M
