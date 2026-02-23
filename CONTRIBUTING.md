# Contributing

## Philosophy

Contributions are welcome when they benefit the broad user base. If a feature
is useful to most people — better defaults, bug fixes, missing keybinds,
improved UX — it belongs in this plugin.

If a feature is specific to a particular workflow, email provider, or personal
preference, it likely belongs in a separate plugin built on top of the [events
system](#events-system). See [writing a plugin](#writing-a-plugin) below.

When in doubt, open an issue first to discuss whether the change is a good fit
before spending time on an implementation.

**Including tests significantly increases the likelihood of a PR being merged.**
The project enforces 90% coverage per file in CI. If you're adding behaviour,
add specs for it.

---

## Development setup

### Prerequisites

The project uses [Nix](https://nixos.org/) for a fully reproducible dev
environment. Install Nix with the
[DeterminateSystems installer](https://github.com/DeterminateSystems/nix-installer)
if you don't have it.

### Enter the dev shell

```sh
nix develop
```

This provides Neovim, busted, nlua, luacheck, stylua, VHS, ffmpeg, and
everything else needed to work on the plugin.

### Run the plugin from source

```sh
nvim -u demo/init.lua
```

This loads the plugin directly from the working tree with mock mode enabled — no
CLI binary or email account needed. See [mock mode](#mock-mode) below.

---

## Mock mode

The plugin ships with built-in sample data (23 emails across 4 threads, 8
contacts, multiple folders) that works without the Himalaya CLI binary:

```lua
require('himalaya').setup({ mock = true })
```

Mock mode is the recommended way to develop and iterate on UI changes. It
preserves async behaviour (`vim.schedule`) so the experience matches real usage.

The mock data lives in `lua/himalaya/mock/data.lua`. The request interceptor is
in `lua/himalaya/mock.lua` — it maps CLI command strings to mock responses,
making it straightforward to add new mock commands when needed.

---

## Testing

Tests use [busted](https://lunarmodules.github.io/busted/) with
[nlua](https://github.com/mfussenegger/nlua) (Neovim as the Lua interpreter).
Spec files mirror the `lua/himalaya/` directory structure under `tests/himalaya/`.

```sh
make test          # run the full test suite
make coverage      # run tests and generate luacov.report.out
make coverage-check  # enforce 90% minimum per file (runs in CI)
```

A single spec file:

```sh
nix develop --command busted tests/himalaya/domain/email/compose_spec.lua
```

**Tests are a first-class contribution.** PRs that add tests for existing
untested code are welcome on their own merits, even without other changes. If
your PR changes behaviour and doesn't include specs, expect a review asking for
them.

Test structure conventions:
- Use `insulate` blocks to isolate state between test groups
- Call `events._reset()` in `before_each` when testing code that emits events
- Stub external calls (CLI, `vim.system`) rather than hitting real processes
- Prefer testing the public interface of a module, not its internals

---

## Linting and formatting

```sh
make lint          # luacheck lua/ tests/
make fmt           # format in place (stylua + nixfmt via nix fmt)
make fmt-check     # fail if anything is unformatted (runs in CI)
```

Key style settings (from `.stylua.toml`):
- 2-space indentation
- 120-column line width
- Single quotes preferred
- Parentheses always on function calls

CI runs format check, lint, and coverage-check in parallel. A PR must pass all
three.

---

## Recording demos

Demos are recorded with [VHS](https://github.com/charmbracelet/vhs). Tape
files live in `demo/` alongside the output mp4s.

```sh
vhs demo/listing.tape              # record a single tape
nix run .#build-demo               # render all tapes + apply video filters
nix run .#upload-demo              # upload to Cloudflare R2 (requires credentials)
```

The `demo/init.lua` file sets up a minimal Neovim environment (no external
plugins) with mock mode and a `:Msg` command for on-screen captions. Wrap key
names in `<...>` to render them in a distinct highlight colour:

```
:Msg Navigate with <j>/<k> — read with <Enter>
```

Demo settings: 1920×1080, Maple Mono NF size 24, Builtin Dark theme, 0.5×
playback speed.

---

## Events system

All significant actions in the plugin emit an event via `lua/himalaya/events.lua`.
This is the primary extension point — you can hook into any of these from your
own config or plugin without touching the core code.

### API

```lua
local events = require('himalaya.events')

-- Persistent listener; returns an id you can use to unsubscribe
local id = events.on('EmailRead', function(data) ... end)

-- One-shot listener; auto-removed after the first emit
events.once('EmailSent', function(data) ... end)

-- Unsubscribe
events.off(id)
```

Listeners are called in registration order. Each listener is `pcall`-wrapped,
so an error in yours won't break others or the plugin itself — it gets logged as
a warning.

### All events

<!-- GEN:events -->
| Event | Payload |
|-------|---------|
| `EmailsListed` | `{ account, folder, page, count }` |
| `EmailRead` | `{ account, folder, email_id, bufnr }` |
| `EmailDeleted` | `{ account, folder, ids }` |
| `EmailCopied` | `{ account, folder, ids, target_folder }` |
| `EmailMoved` | `{ account, folder, ids, target_folder }` |
| `EmailFlagAdded` | `{ account, folder, ids, flag }` |
| `EmailFlagRemoved` | `{ account, folder, ids, flag }` |
| `EmailMarkedSeen` | `{ account, folder, ids }` |
| `EmailMarkedUnseen` | `{ account, folder, ids }` |
| `ComposeOpened` | `{ account, folder, mode, bufnr }` — mode: `write`, `reply`, `reply_all`, `forward` |
| `EmailSent` | `{ account, folder, reply_id }` |
| `DraftSaved` | `{ account }` |
| `FolderChanged` | `{ account, folder }` |
| `NewMail` | `{ account, folder, count, new_ids }` — fired by background sync |
<!-- /GEN:events -->

---

## Writing a plugin

If your idea is useful to you but probably not to everyone, the right place for
it is a standalone Neovim plugin that depends on himalaya-vim. The events system
is designed for exactly this.

### Minimal plugin example

A plugin that shows a notification whenever new mail arrives:

```lua
-- lua/himalaya-notify/init.lua
local M = {}

function M.setup(opts)
  opts = opts or {}
  local events = require('himalaya.events')

  events.on('NewMail', function(data)
    vim.notify(
      string.format('%d new mail in %s/%s', data.count, data.account, data.folder),
      vim.log.levels.INFO
    )
  end)
end

return M
```

Users then add it to their config after `require('himalaya').setup(...)`:

```lua
require('himalaya').setup({ background_sync = true, sync_interval = 30 })
require('himalaya-notify').setup()
```

### Using buffer variables

When a himalaya buffer is active, it exposes context via buffer-local variables
you can read from event handlers or mappings:

```lua
vim.b.himalaya_account   -- current account name
vim.b.himalaya_folder    -- current folder
vim.b.himalaya_page      -- current page number
```

### Responding to compose events

The `ComposeOpened` event fires after the compose buffer is created. You can
use `bufnr` to add buffer-local mappings or modify the buffer:

```lua
events.on('ComposeOpened', function(data)
  if data.mode == 'write' then
    -- Add a custom mapping in new-email buffers only
    vim.keymap.set('n', '<leader>e', my_template_picker, { buffer = data.bufnr })
  end
end)
```

### Plugin checklist

- Name your plugin `himalaya-<something>.nvim` so it's discoverable
- Guard against himalaya not being loaded: `if not pcall(require, 'himalaya') then return end`
- Clean up listeners on plugin teardown with `events.off(id)`
- Put it on GitHub and mention it in a Discussions post or issue so others can find it
