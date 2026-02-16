# Himalaya-Vim: VimScript to Lua Migration Design

## Summary

Migrate the entire himalaya-vim plugin from VimScript to Lua, targeting Neovim 0.10+ only. Drop Vim 8 support. Add tests with plenary.nvim alongside each module migration. Add vimdoc help file.

## Constraints

- **Neovim 0.10+ only** — enables `vim.system()`, `vim.uv`, and modern Lua APIs
- **Bottom-up migration** — leaf modules first, entry point last
- **Coexistence during migration** — Lua calls VimScript via `vim.fn` for not-yet-migrated code; VimScript calls Lua via `luaeval` for already-migrated code
- **No user-facing command changes** — same Ex commands (`:Himalaya`, `:HimalayaWrite`, etc.)
- **Tests written alongside each module** — plenary.nvim with describe/it blocks

## Module Structure

```
lua/himalaya/
  init.lua              -- Entry point, setup(), command registration
  log.lua               -- Logging via vim.notify
  job.lua               -- Async CLI execution via vim.system()
  request.lua           -- JSON/plain request helpers wrapping job
  keybinds.lua          -- <Plug> mapping registration
  config.lua            -- User config with defaults (replaces g: vars)
  state/
    account.lua         -- Current account state
    folder.lua          -- Current folder + page state
  domain/
    folder.lua          -- Folder operations + picker dispatch
    email.lua           -- Core email CRUD operations
    email/
      flags.lua         -- Flag completion
      thread.lua        -- Thread folding
  pickers/
    init.lua            -- Auto-detect and dispatch to available picker
    native.lua          -- vim.ui.select based
    fzf.lua             -- fzf.vim integration
    fzflua.lua          -- fzf-lua integration
    telescope.lua       -- telescope integration
  ui/
    listing.lua         -- Envelope listing buffer setup, keymaps, highlights
    reading.lua         -- Email reading buffer setup, keymaps, highlights
    writing.lua         -- Compose buffer setup, keymaps, autocmds

plugin/himalaya.lua     -- Thin shim: registers commands, calls require('himalaya')
doc/himalaya.txt        -- Vimdoc help file

tests/
  himalaya/
    config_spec.lua
    job_spec.lua
    request_spec.lua
    keybinds_spec.lua
    domain/
      email_spec.lua
      folder_spec.lua
      email/
        flags_spec.lua
        thread_spec.lua
    ui/
      listing_spec.lua
      reading_spec.lua
      writing_spec.lua
    pickers/
      native_spec.lua
```

## Configuration

Replace scattered `g:himalaya_*` variables with a single `setup()` call:

```lua
require('himalaya').setup({
  executable = 'himalaya',
  config_path = nil,
  folder_picker = nil,          -- auto-detect: telescope > fzflua > fzf > native
  telescope_preview = false,
  complete_contact_cmd = nil,
  custom_flags = {},
  always_confirm = true,
})
```

`config.lua` stores defaults, deep-merges user overrides with `vim.tbl_deep_extend`, and exposes `config.get()` for other modules.

`plugin/himalaya.lua` registers Ex commands unconditionally (lazy-loading friendly). `setup()` is the user's responsibility.

## Async Job System

Replace the Neovim `jobstart()`/`chansend()` + Vim 8 `job_start()`/`ch_sendraw()` dual backend with a single `vim.system()` implementation.

- `job.run(cmd, opts)` — spawns `vim.system()` with the himalaya binary, collects stdout/stderr
- Stdin piping via `vim.system()`'s `stdin` option (replaces the ` -- ` splitting convention)
- `RUST_LOG=off` set via `vim.system()`'s `env` option
- Error handling: non-zero exit + non-empty stderr triggers `log.error()`

`request.lua` wraps `job.run()`:
- `request.json()` — adds `--output json`, parses with `vim.json.decode()`
- `request.plain()` — adds `--output plain`, joins lines
- Prepends `--config <path>` when configured

## Buffer Management

Replace buffer name string matching with `vim.b` (buffer-local variables):

```lua
-- listing buffer metadata
vim.b[bufnr].himalaya = {
  type = 'listing',
  folder = 'INBOX',
  page = 1,
  query = '',
}
```

Keep human-readable buffer names for display, but use `vim.b` for programmatic identification.

Keymaps registered with `vim.keymap.set` using `buffer = bufnr`. `<Plug>` mapping pattern preserved for user remapping.

## Syntax Highlighting

Convert VimScript syntax files to Lua-based highlighting:
- Highlight groups defined with `vim.api.nvim_set_hl`
- Applied to buffer content with `vim.api.nvim_buf_add_highlight` or extmarks
- No `.vim` syntax files will remain

The reading and writing buffers delegate to mail filetype highlighting by setting `filetype=mail`.

## Native Picker

Replace `input()` based native picker with `vim.ui.select()`:
- Integrates automatically with dressing.nvim and similar UI plugins
- Cleaner API, no manual index selection

## Testing Strategy

**Test framework:** plenary.nvim (busted-style describe/it blocks)

**Test categories:**

1. **Unit tests** — pure Lua logic (config merging, flag list building, fold expressions, command string construction)
2. **Integration tests** — require Neovim API (buffer creation, keymaps, autocmds, commands)
3. **Mock-based tests** — stub `vim.system()` and request layer to verify correct CLI command dispatch

**Timing:** Each module gets tests written alongside its migration, verifying behavior preservation.

## Migration Order

### Phase 1: Foundation

1. `log.lua` — replaces `himalaya#log#*`
2. `config.lua` — replaces `g:himalaya_*` variable reads
3. `job.lua` — replaces `himalaya#job#start`
4. `request.lua` — replaces `himalaya#request#json` / `himalaya#request#plain`

### Phase 2: State & Domain Utilities

5. `state/account.lua` — replaces `himalaya#domain#account#*`
6. `state/folder.lua` — replaces folder/page state
7. `domain/email/flags.lua` — replaces flag completion
8. `domain/email/thread.lua` — replaces fold expression
9. `keybinds.lua` — replaces `himalaya#keybinds#define`

### Phase 3: Pickers

10. `pickers/native.lua` — vim.ui.select based
11. `pickers/fzf.lua` — fzf.vim integration
12. `pickers/fzflua.lua` — expand existing Lua file
13. `pickers/telescope.lua` — expand existing Lua file
14. `pickers/init.lua` — auto-detection + dispatch
15. `domain/folder.lua` — folder operations using new pickers

### Phase 4: Core Domain

16. `domain/email.lua` — all email operations (~404 lines of VimScript)

### Phase 5: UI

17. `ui/listing.lua` — envelope listing buffer, keymaps, highlights
18. `ui/reading.lua` — email reading buffer, keymaps, highlights
19. `ui/writing.lua` — compose buffer, keymaps, autocmds

### Phase 6: Entry Point & Cleanup

20. `init.lua` + `plugin/himalaya.lua` — replace `plugin/himalaya.vim`
21. Delete all remaining `.vim` files
22. Add `doc/himalaya.txt` vimdoc help file
