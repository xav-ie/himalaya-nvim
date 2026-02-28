<div align="center">
  <img src="./logo.svg" alt="Logo" width="128" height="128" />
  <h1>Himalaya Nvim</h1>
  <p>Neovim front-end for the email client <a href="https://github.com/xav-ie/himalaya">Himalaya CLI</a></p>
  <p><em>🌱 A heavily modified fork of <a href="https://github.com/pimalaya/himalaya-vim">pimalaya/himalaya-vim</a></em></p>
  <p>
    <a href="https://github.com/xav-ie/himalaya/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/xav-ie/himalaya?color=success"/></a>
    <a href="https://github.com/xav-ie/himalaya-nvim/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/xav-ie/himalaya-nvim/actions/workflows/ci.yml/badge.svg"/></a>
  </p>
</div>

<img src="https://himalaya-nvim.xav.ie/himalaya.svg" width="100%" alt="Himalaya demo">
<p align="center"><a href="https://himalaya-nvim.xav.ie/himalaya.mp4">▶ Watch as video</a></p>

## Features

- **Flat envelope listing** — adaptive column layout, pagination, flag indicators, unread highlighting
- **Threaded view** — Unicode tree connectors, reverse toggle, per-thread grouping
- **Structured search** — popup with per-field input, field negation, date presets, live query preview
- **Sort toggle** — sort by date, from, subject, or to in ascending/descending order
- **Email reading** — split view with quoted-text folding and `]]`/`[[` navigation between emails
- **Composing** — write, reply, reply-all, forward with auto-save drafts and contact completion
- **Flag management** — mark seen/unseen, add/remove arbitrary flags, visual-mode bulk operations
- **Folder operations** — switch folders, copy/move emails between folders
- **Per-account signatures** — global or per-account email signatures
- **Background sync** — periodic re-fetch while idle
- **Events system** — hook into `EmailsListed`, `EmailRead`, `ComposeOpened`, and more
- **Picker integration** — native, fzf, fzf-lua, or Telescope for account/folder selection
- **Mock mode** — try the plugin without a real email account or CLI binary

## Requirements

- Neovim >= 0.10
- [Himalaya CLI](https://pimalaya.org/himalaya/cli/latest/installation/) (not needed in mock mode)

**Optional picker integrations** (auto-detected if installed):
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [fzf.vim](https://github.com/junegunn/fzf.vim)

Falls back to a built-in native picker if none are present.

## Installation

Install and configure the [Himalaya CLI](https://github.com/xav-ie/himalaya), then add
the plugin with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'xav-ie/himalaya-nvim',
  cmd = 'Himalaya',
  config = function()
    require('himalaya').setup({})
  end,
}
```

> **Note:** `require('himalaya').setup()` is required. It validates the CLI binary and applies configuration.

> **Try it without an account:** pass `mock = true` to explore the full UI with built-in sample data — no CLI binary or email account needed. See [mock mode](#mock-mode) in CONTRIBUTING.md.

## Configuration

All options with their defaults:

<!-- GEN:config -->
```lua
require('himalaya').setup({
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
    over  = 'right',
    under = 'below',
  },

  -- Enable mock mode (no CLI binary or email account needed)
  mock = false,
})
```
<!-- /GEN:config -->

## Usage

Open the email listing:

```vim
:Himalaya
```

<img src="https://himalaya-nvim.xav.ie/listing.svg" width="100%" alt="Listing demo">
<p align="center"><a href="https://himalaya-nvim.xav.ie/listing.mp4">▶ Watch as video</a></p>

### Flat listing

| Key         | Action                       |
| ----------- | ---------------------------- |
| `Enter`     | Read email under cursor      |
| `]]`        | Next page                    |
| `[[`        | Previous page                |
| `gt`        | Switch to thread view        |
| `g/`        | Open search popup            |
| `g?`        | Apply search preset          |
| `go`        | Toggle sort field/direction  |
| `]u` / `[u` | Jump to next/previous unread |
| `]r` / `[r` | Jump to next/previous read   |
| `?`         | Show keybind help            |

### Thread view

| Key         | Action                               |
| ----------- | ------------------------------------ |
| `Enter`     | Read email under cursor              |
| `]]`        | Next page                            |
| `[[`        | Previous page                        |
| `gt`        | Switch to flat listing               |
| `gT`        | Toggle reverse order (newest on top) |
| `g/`        | Open search popup                    |
| `g?`        | Apply search preset                  |
| `go`        | Toggle sort field/direction          |
| `]u` / `[u` | Jump to next/previous unread         |
| `?`         | Show keybind help                    |

<img src="https://himalaya-nvim.xav.ie/reply.svg" width="100%" alt="Reply demo">
<p align="center"><a href="https://himalaya-nvim.xav.ie/reply.mp4">▶ Watch as video</a></p>

### Reading

| Key  | Action               |
| ---- | -------------------- |
| `]]` | Next email           |
| `[[` | Previous email       |
| `gr` | Reply                |
| `gR` | Reply all            |
| `gf` | Forward              |
| `gA` | Download attachments |
| `gC` | Copy to folder       |
| `gM` | Move to folder       |
| `gD` | Delete               |
| `gb` | Open in browser      |
| `?`  | Show keybind help    |

<img src="https://himalaya-nvim.xav.ie/search.svg" width="100%" alt="Search demo">
<p align="center"><a href="https://himalaya-nvim.xav.ie/search.mp4">▶ Watch as video</a></p>

### Search

The search popup (`g/`) provides structured per-field input:

| Field   | Description                                           |
| ------- | ----------------------------------------------------- |
| folder  | Target folder (Tab to complete)                       |
| subject | Subject text pattern                                  |
| body    | Body text pattern (linked to subject by default)      |
| from    | Sender pattern                                        |
| to      | Recipient pattern                                     |
| when    | Date filter (Tab for presets: today, past week, etc.) |
| flag    | Flag filter (Tab to complete: Seen, Flagged, etc.)    |
| query   | Live-updated composite query                          |

- **Tab** / **Shift-Tab** — navigate between fields (or complete on completable fields)
- **Ctrl-x** — toggle field negation
- **Enter** — submit search
- **Esc** — cancel

<img src="https://himalaya-nvim.xav.ie/compose.svg" width="100%" alt="Compose demo">
<p align="center"><a href="https://himalaya-nvim.xav.ie/compose.mp4">▶ Watch as video</a></p>

### Composing

| Key  | Action                      |
| ---- | --------------------------- |
| `gw` | Write new email             |
| `gr` | Reply to email under cursor |
| `gR` | Reply all                   |
| `gf` | Forward email               |

In the compose buffer:

- `:w` sends the email
- Leaving the buffer auto-saves as draft
- Contact completion: `Ctrl-x Ctrl-u` (requires `complete_contact_cmd`)

### Common bindings (listing and thread view)

| Key   | Action               |
| ----- | -------------------- |
| `ga`  | Switch account       |
| `gm`  | Switch folder        |
| `gw`  | Write new email      |
| `dd`  | Delete email         |
| `gs`  | Mark as seen         |
| `gS`  | Mark as unseen       |
| `gFa` | Add flag             |
| `gFr` | Remove flag          |
| `gC`  | Copy to folder       |
| `gM`  | Move to folder       |
| `gA`  | Download attachments |
| `gb`  | Open in browser      |

Visual mode: `d`, `gs`, `gS`, `gFa`, `gFr`, `gC`, `gM` work on selected range.

## Customization

### Keymap overrides

Remap any binding by its plug name, or set to `false` to disable:

```lua
require('himalaya').setup({
  keymaps = {
    ['email-read'] = 'o',           -- open email with 'o' instead of Enter
    ['email-delete'] = false,       -- disable dd delete
    ['email-toggle-sort'] = 'gO',   -- remap sort toggle
  },
})
```

### Events

Subscribe to plugin events for custom behavior:

```lua
local events = require('himalaya.events')

events.on('EmailsListed', function(data) ... end)
events.on('EmailRead', function(data) ... end)
events.on('ComposeOpened', function(data) ... end)
```

See [CONTRIBUTING.md](./CONTRIBUTING.md#all-events) for the full list of events and their payloads.

### Signatures

Set a global signature or per-account signatures:

```lua
require('himalaya').setup({
  -- Global signature
  signature = '\n--\nSent with himalaya',

  -- Or per-account
  signature = {
    personal = '\n--\nJohn Doe',
    work = '\n--\nJohn Doe\nSoftware Engineer\nAcme Corp',
  },
})
```

### Search presets

Define named search presets for quick access via `g?`:

```lua
require('himalaya').setup({
  search_presets = {
    { name = 'Unread', query = 'not flag Seen' },
    { name = 'Flagged', query = 'flag Flagged' },
    { name = 'This week', query = 'after ' .. os.date('%Y-%m-%d', os.time() - 7 * 86400) },
  },
})
```

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup, testing, the
full events reference, and a guide to writing plugins that extend himalaya-nvim.
