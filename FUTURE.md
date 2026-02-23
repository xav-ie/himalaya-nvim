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

*24 items completed, 11 declined (see git history for details).*

- **Buffer/window validity guards in async callbacks** — Several
  async callbacks (`probe.lua` post-probe rename, `thread_listing.lua`
  enrich, `win.lua` traversal) mutate buffers/windows without checking
  if they were closed during the async delay. Add `pcall` +
  `nvim_buf_is_valid()` / `nvim_win_is_valid()` guards to prevent
  rare E36/E315 errors on fast tab-switch during in-flight operations.

- **Event/hook system for extensibility** — Define lifecycle events
  (`Before_Send`, `After_Read`, `After_Fetch`, `New_Email`) and let
  users register callbacks via `require('himalaya.events').on(...)`.
  Enables custom integrations (signatures, task capture, notifications)
  without forking. Zero overhead with no subscribers.

- **State lifecycle management** — Module-local state in `email.lua`,
  `thread_listing.lua`, and `probe.lua` (timers, job handles, caches)
  has no cleanup on buffer close. Introduce `BufDelete`/`BufUnload`
  hooks to clean up stale timers, job handles, and cached data.
  Prevents leaks in long sessions with many folder/account switches.
