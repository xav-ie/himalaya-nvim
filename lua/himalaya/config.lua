local M = {}

local defaults = {
  -- Path to the himalaya CLI binary
  executable = 'himalaya',

  -- Path to a custom himalaya config file (nil = CLI default)
  config_path = nil,

  -- Folder/account picker: 'native', 'fzf', 'fzf-lua', or 'telescope'
  -- nil = auto-detect (telescope > fzf-lua > fzf > native)
  folder_picker = nil,

  -- Show preview in Telescope picker
  telescope_preview = false,

  -- Shell command for contact completion (omnifunc); %s = query
  complete_contact_cmd = nil,

  -- Additional flags for flag completion
  custom_flags = {},

  -- Prompt before destructive actions (delete, move)
  always_confirm = true,

  -- Flag display characters in the listing
  flags = {
    header = 'FLGS',
    flagged = '!',
    unseen = '*',
    answered = 'R',
    attachment = '@',
  },

  -- Compact flags into the subject column instead of a separate column.
  -- nil/false: never (5-column layout), true: when narrow, "always": always.
  compact_flags = true,

  -- Compact IDs: remove the ID column and reclaim its width for the subject.
  -- nil/false: never, true: when narrow, "always": always.
  compact_ids = nil,

  -- Show vertical separators between columns
  gutters = true,

  -- Date format (strftime)
  date_format = '%Y-%m-%d %H:%M',

  -- Compact date format used when the listing is too narrow for the full FROM column.
  compact_date_format = '%m/%d',

  -- Start in thread view instead of flat listing
  thread_view = false,

  -- Show newest messages at top in thread view
  thread_reverse = false,

  -- Named search presets for quick access via g?
  search_presets = {},

  -- Override default keybinds (key = plug-name, value = key or false)
  keymaps = {},

  -- Periodically re-fetch envelopes in the background
  background_sync = false,

  -- Background sync interval in seconds
  sync_interval = 60,

  -- Per-account email signatures: string or { account_name = string }
  signature = nil,

  -- Reading pane split configuration.
  -- threshold: listing width at which 'over' vs 'under' is chosen.
  -- size: 0.0–1.0 = fraction of space; >1 = absolute cols/rows (shared default)
  -- over/under: direction string ('left'|'right'|'above'|'below')
  --   or table { side = direction, size = number } to override size per branch.
  reading_split = {
    threshold = 115,
    size = 0.6,
    over = 'right',
    under = 'below',
  },

  -- Enable mock mode (no CLI binary or email account needed)
  mock = false,
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
