# Future Improvements

Improvement ideas for himalaya-vim, organized by category.

*9 bugs fixed (process_draft, answered flag, lock contention,
double-send, compose window, flags, bufnr safety, visual-mode IDs).*

## UI/UX

*26 items completed, 12 declined (see git history for details).*

- ~~**Adaptive column layout for narrow terminals**~~ — Done. FROM
  column collapses to 2-char initials when `from_w < 12`, freeing
  space for the subject column (`dfbff5b`, `822541d`).

- ~~**Search input validation**~~ — Done. CLI errors from bad queries
  are now surfaced via stderr error logging (`a3e14a7`).

- **Compose templates** — Support user-defined Lua templates in
  config that auto-populate cc/bcc/signature fields in compose
  buffers, accelerating repetitive email composition.

## Plugin Integration

- ~~**which-key.nvim group labels**~~ — Done. Group labels for `gF`,
  `]`, `[` are auto-registered when which-key is installed (`g` is
  left alone since it holds native Neovim bindings).

- **Telescope extension** — Build a full Telescope extension with
  live email search (with preview), account switcher, and search
  preset picker, going beyond the current folder-only picker.

## Performance

*19 items completed, 8 declined (see git history for details).
No open items — section cleared.*

## Architecture & Code Quality

*27 items completed, 11 declined (see git history for details).
No open items — section cleared.*
