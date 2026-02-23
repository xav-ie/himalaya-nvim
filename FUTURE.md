# Future Improvements

Improvement ideas for himalaya-vim, organized by category.

*9 bugs fixed (process_draft, answered flag, lock contention,
double-send, compose window, flags, bufnr safety, visual-mode IDs).*

## UI/UX

*25 items completed, 12 declined (see git history for details).*

- **Persistent mailbox state** — Save browsing position (account,
  folder, page, scroll offset, search query) per account to a JSON
  file. `:Himalaya` restores last state on next session, so daily
  users resume where they left off.

- **Search history and saved presets** — Recall recent search queries
  and define quick-filter presets in config (e.g.,
  `unread = 'flag unseen'`, `flagged = 'flag flagged'`). Reduces
  repetitive query building for common filters.

- **Background sync / new-mail notification** — Opt-in polling via
  `vim.uv.new_timer()` at a configurable interval. `vim.notify()` on
  new envelopes, update listing buffer in-place if visible. Behind
  `background_sync = true` config. Depends on event/hook system
  (Architecture item) for extensibility.

## Performance

*19 items completed, 8 declined (see git history for details).
No open items — section cleared.*

## Architecture & Code Quality

*27 items completed, 11 declined (see git history for details).
No open items — section cleared.*
