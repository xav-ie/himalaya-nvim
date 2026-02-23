<div align="center">
  <img src="./logo.svg" alt="Logo" width="128" height="128" />
  <h1>Himalaya Vim</h1>
  <p>Neovim front-end for the email client <a href="https://github.com/pimalaya/himalaya">Himalaya CLI</a></p>
  <p>
    <a href="https://github.com/pimalaya/himalaya/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/pimalaya/himalaya?color=success"/></a>
    <a href="https://repology.org/project/himalaya/versions"><img alt="Repology" src="https://img.shields.io/repology/repositories/himalaya?color=success"></a>
    <a href="https://matrix.to/#/#pimalaya:matrix.org"><img alt="Matrix" src="https://img.shields.io/badge/chat-%23pimalaya-blue?style=flat&logo=matrix&logoColor=white"/></a>
    <a href="https://fosstodon.org/@pimalaya"><img alt="Mastodon" src="https://img.shields.io/badge/news-%40pimalaya-blue?style=flat&logo=mastodon&logoColor=white"/></a>
  </p>
</div>

https://github.com/user-attachments/assets/himalaya-demo.mp4

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

## Installation

Install and configure the [Himalaya CLI](https://github.com/pimalaya/himalaya), then add
the plugin with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'pimalaya/himalaya-vim',
  config = function()
    require('himalaya').setup({
      -- see Configuration below
    })
  end,
}
```

> **Note:** `require('himalaya').setup()` is required. It validates the CLI binary and applies configuration.

## Configuration

All options with their defaults:

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
    header   = 'FLGS',
    flagged  = '!',
    unseen   = '*',
    answered = 'R',
    attachment = '@',
  },

  -- Show vertical separators between columns
  gutters = true,

  -- Date format (strftime)
  date_format = '%Y-%m-%d %H:%M',

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

  -- Enable mock mode (no CLI binary or email account needed)
  mock = false,
})
```

### Mock mode

Set `mock = true` to use the plugin with pre-built sample data — no CLI binary
or email account required:

```lua
require('himalaya').setup({ mock = true })
```

This is useful for trying the plugin before configuring an email account,
recording demos, or development.

## Usage

Open the email listing:

```vim
:Himalaya
```

### Flat listing

| Key | Action |
|-----|--------|
| `Enter` | Read email under cursor |
| `]]` | Next page |
| `[[` | Previous page |
| `gt` | Switch to thread view |
| `g/` | Open search popup |
| `g?` | Apply search preset |
| `go` | Toggle sort field/direction |
| `]u` / `[u` | Jump to next/previous unread |
| `]r` / `[r` | Jump to next/previous read |
| `?` | Show keybind help |

### Thread view

| Key | Action |
|-----|--------|
| `Enter` | Read email under cursor |
| `]]` | Next page |
| `[[` | Previous page |
| `gt` | Switch to flat listing |
| `gT` | Toggle reverse order (newest on top) |
| `g/` | Open search popup |
| `g?` | Apply search preset |
| `go` | Toggle sort field/direction |
| `]u` / `[u` | Jump to next/previous unread |
| `?` | Show keybind help |

### Reading

| Key | Action |
|-----|--------|
| `]]` | Next email |
| `[[` | Previous email |
| `gr` | Reply |
| `gR` | Reply all |
| `gf` | Forward |
| `gA` | Download attachments |
| `gC` | Copy to folder |
| `gM` | Move to folder |
| `gD` | Delete |
| `gb` | Open in browser |
| `?` | Show keybind help |

### Search

The search popup (`g/`) provides structured per-field input:

| Field | Description |
|-------|-------------|
| folder | Target folder (Tab to complete) |
| subject | Subject text pattern |
| body | Body text pattern (linked to subject by default) |
| from | Sender pattern |
| to | Recipient pattern |
| when | Date filter (Tab for presets: today, past week, etc.) |
| flag | Flag filter (Tab to complete: Seen, Flagged, etc.) |
| query | Live-updated composite query |

- **Tab** / **Shift-Tab** — navigate between fields (or complete on completable fields)
- **Ctrl-x** — toggle field negation
- **Enter** — submit search
- **Esc** — cancel

### Composing

| Key | Action |
|-----|--------|
| `gw` | Write new email |
| `gr` | Reply to email under cursor |
| `gR` | Reply all |
| `gf` | Forward email |

In the compose buffer:
- `:w` sends the email
- Leaving the buffer auto-saves as draft
- Contact completion: `Ctrl-x Ctrl-u` (requires `complete_contact_cmd`)

### Common bindings (listing and thread view)

| Key | Action |
|-----|--------|
| `ga` | Switch account |
| `gm` | Switch folder |
| `gw` | Write new email |
| `dd` | Delete email |
| `gs` | Mark as seen |
| `gS` | Mark as unseen |
| `gFa` | Add flag |
| `gFr` | Remove flag |
| `gC` | Copy to folder |
| `gM` | Move to folder |
| `gA` | Download attachments |
| `gb` | Open in browser |

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

events.on('EmailsListed', function(data)
  -- data: { account, folder, page, count }
end)

events.on('EmailRead', function(data)
  -- data: { account, folder, email_id, bufnr }
end)

events.on('ComposeOpened', function(data)
  -- data: { account, bufnr, kind }
  -- kind: 'write', 'reply', 'reply_all', 'forward'
end)
```

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

## Sponsoring

[![nlnet](https://nlnet.nl/logo/banner-160x60.png)](https://nlnet.nl/)

Special thanks to the [NLnet foundation](https://nlnet.nl/) and the [European Commission](https://www.ngi.eu/) that have been financially supporting the project for years:

- 2022: [NGI Assure](https://nlnet.nl/project/Himalaya/)
- 2023: [NGI Zero Entrust](https://nlnet.nl/project/Pimalaya/)
- 2024: [NGI Zero Core](https://nlnet.nl/project/Pimalaya-PIM/) *(still ongoing in 2026)*

If you appreciate the project, feel free to donate using one of the following providers:

[![GitHub](https://img.shields.io/badge/-GitHub%20Sponsors-fafbfc?logo=GitHub%20Sponsors)](https://github.com/sponsors/soywod)
[![Ko-fi](https://img.shields.io/badge/-Ko--fi-ff5e5a?logo=Ko-fi&logoColor=ffffff)](https://ko-fi.com/soywod)
[![Buy Me a Coffee](https://img.shields.io/badge/-Buy%20Me%20a%20Coffee-ffdd00?logo=Buy%20Me%20A%20Coffee&logoColor=000000)](https://www.buymeacoffee.com/soywod)
[![Liberapay](https://img.shields.io/badge/-Liberapay-f6c915?logo=Liberapay&logoColor=222222)](https://liberapay.com/soywod)
[![thanks.dev](https://img.shields.io/badge/-thanks.dev-000000?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQuMDk3IiBoZWlnaHQ9IjE3LjU5NyIgY2xhc3M9InctMzYgbWwtMiBsZzpteC0wIHByaW50Om14LTAgcHJpbnQ6aW52ZXJ0IiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxwYXRoIGQ9Ik05Ljc4MyAxNy41OTdINy4zOThjLTEuMTY4IDAtMi4wOTItLjI5Ny0yLjc3My0uODktLjY4LS41OTMtMS4wMi0xLjQ2Mi0xLjAyLTIuNjA2di0xLjM0NmMwLTEuMDE4LS4yMjctMS43NS0uNjc4LTIuMTk1LS40NTItLjQ0Ni0xLjIzMi0uNjY5LTIuMzQtLjY2OUgwVjcuNzA1aC41ODdjMS4xMDggMCAxLjg4OC0uMjIyIDIuMzQtLjY2OC40NTEtLjQ0Ni42NzctMS4xNzcuNjc3LTIuMTk1VjMuNDk2YzAtMS4xNDQuMzQtMi4wMTMgMS4wMjEtMi42MDZDNS4zMDUuMjk3IDYuMjMgMCA3LjM5OCAwaDIuMzg1djEuOTg3aC0uOTg1Yy0uMzYxIDAtLjY4OC4wMjctLjk4LjA4MmExLjcxOSAxLjcxOSAwIDAgMC0uNzM2LjMwN2MtLjIwNS4xNTYtLjM1OC4zODQtLjQ2LjY4Mi0uMTAzLjI5OC0uMTU0LjY4Mi0uMTU0IDEuMTUxVjUuMjNjMCAuODY3LS4yNDkgMS41ODYtLjc0NSAyLjE1NS0uNDk3LjU2OS0xLjE1OCAxLjAwNC0xLjk4MyAxLjMwNXYuMjE3Yy44MjUuMyAxLjQ4Ni43MzYgMS45ODMgMS4zMDUuNDk2LjU3Ljc0NSAxLjI4Ny43NDUgMi4xNTR2MS4wMjFjMCAuNDcuMDUxLjg1NC4xNTMgMS4xNTIuMTAzLjI5OC4yNTYuNTI1LjQ2MS42ODIuMTkzLjE1Ny40MzcuMjYuNzMyLjMxMi4yOTUuMDUuNjIzLjA3Ni45ODQuMDc2aC45ODVabTE0LjMxNC03LjcwNmgtLjU4OGMtMS4xMDggMC0xLjg4OC4yMjMtMi4zNC42NjktLjQ1LjQ0NS0uNjc3IDEuMTc3LS42NzcgMi4xOTVWMTQuMWMwIDEuMTQ0LS4zNCAyLjAxMy0xLjAyIDIuNjA2LS42OC41OTMtMS42MDUuODktMi43NzQuODloLTIuMzg0di0xLjk4OGguOTg0Yy4zNjIgMCAuNjg4LS4wMjcuOTgtLjA4LjI5Mi0uMDU1LjUzOC0uMTU3LjczNy0uMzA4LjIwNC0uMTU3LjM1OC0uMzg0LjQ2LS42ODIuMTAzLS4yOTguMTU0LS42ODIuMTU0LTEuMTUydi0xLjAyYzAtLjg2OC4yNDgtMS41ODYuNzQ1LTIuMTU1LjQ5Ny0uNTcgMS4xNTgtMS4wMDQgMS45ODMtMS4zMDV2LS4yMTdjLS44MjUtLjMwMS0xLjQ4Ni0uNzM2LTEuOTgzLTEuMzA1LS40OTctLjU3LS43NDUtMS4yODgtLjc0NS0yLjE1NXYtMS4wMmMwLS40Ny0uMDUxLS44NTQtLjE1NC0xLjE1Mi0uMTAyLS4yOTgtLjI1Ni0uNTI2LS40Ni0uNjgyYTEuNzE5IDEuNzE5IDAgMCAwLS43MzctLjMwNyA1LjM5NSA1LjM5NSAwIDAgMC0uOTgtLjA4MmgtLjk4NFYwaDIuMzg0YzEuMTY5IDAgMi4wOTMuMjk3IDIuNzc0Ljg5LjY4LjU5MyAxLjAyIDEuNDYyIDEuMDIgMi42MDZ2MS4zNDZjMCAxLjAxOC4yMjYgMS43NS42NzggMi4xOTUuNDUxLjQ0NiAxLjIzMS42NjggMi4zNC42NjhoLjU4N3oiIGZpbGw9IiNmZmYiLz48L3N2Zz4=)](https://thanks.dev/soywod)
[![PayPal](https://img.shields.io/badge/-PayPal-0079c1?logo=PayPal&logoColor=ffffff)](https://www.paypal.com/paypalme/soywod)
