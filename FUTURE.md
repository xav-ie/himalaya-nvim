# Future Improvements

Improvement ideas for himalaya-vim, organized by category. Items marked
with **(quick win)** can typically be done in under 30 minutes each.

## Bugs

### 1. `vim.fn.delete(draft)` Deletes Wrong Variable in `process_draft`

`compose.lua:147` calls `vim.fn.delete(draft)` in the send `on_data`
callback, but `draft` is the module-local string holding email content,
not a file path. The intended target is `draft_file` (the temp file).
The call silently does nothing, leaking temp files. The draft branch
on the line below correctly uses `vim.fn.delete(draft_file)`.

**Fix:** Change `vim.fn.delete(draft)` to `vim.fn.delete(draft_file)`.

**Files:** `domain/email/compose.lua:147`

## UI/UX

### 1. Draft Prompt Fires on Every BufLeave

`writing.lua:33` triggers `compose.process_draft()` on `BufLeave`,
meaning the "(s)end, (d)raft, (q)uit or (c)ancel?" prompt fires when
the user merely switches windows (e.g., to check a reference email).
The cancel path uses `error('Prompt:Interrupt')` to re-open the buffer,
which is a code smell that can leak into error logs.

**Fix:** Change the autocmd trigger to `BufDelete`/`QuitPre` (deliberate
close) rather than every `BufLeave`. Auto-save draft silently on
`BufLeave` and restore on re-enter. Replace `vim.fn.input` loop with
`vim.ui.select`.

**Files:** `ui/writing.lua:33`, `domain/email/compose.lua:127-189`

### 2. Confirmation Dialogs Use `vim.fn.inputdialog`

`email.lua:477,547` uses `inputdialog` with a `'_cancel_'` sentinel for
delete/move confirmation. The prompt shows raw IDs with no context
(subject/sender), blocks the event loop, and accepts only single-char
`y`/`Y`. `vim.ui.select` with "Yes, delete" / "No, cancel" options
showing the subject would be less disorienting.

**Files:** `domain/email.lua:477,547`

### 3. No Loading Indicator During Async Fetches

When navigating pages or switching folders, the listing appears frozen
until data arrives. No spinner, progress indicator, or "loading" message
is shown. The `fetch_job` handle exists; setting a winbar indicator like
`[loading...]` while it's active and clearing on completion/error is
straightforward.

**Files:** `domain/email.lua:259-308`, `ui/listing.lua:66`

### 4. Search Popup Has No Key Hints **(quick win)**

The search float has `<Tab>` completion, `<C-x>` negation toggle, and
`<CR>` submit, but none of these are documented in the popup. Adding a
`footer` to `nvim_open_win` (Neovim 0.10+) is a 2-line change.

**Files:** `ui/search.lua:153`

### 5. No Next/Previous Email Navigation in Reading Buffer

The reading buffer has reply, forward, copy, move, delete, and
browser-open bindings but no way to advance to the adjacent email
without switching windows. Adding `gn`/`gp` that find the listing
window, move cursor, and call `read()` would match standard email client
behavior.

**Files:** `ui/reading.lua:21`, `domain/email.lua`

### 6. Search Folder Field Stale on Reopen **(quick win)**

When restoring `last_state` in search.lua, the folder field uses the
previous search's folder rather than `current_folder`. If the user
changed folder via `gm` between searches, the search targets the wrong
folder.

**Fix:** Override the saved folder field with `current_folder` when
`last_state` exists.

**Files:** `ui/search.lua:541-567`

### 7. Compose Opens in Wrong Window

`compose.lua:39-53` opens reply/forward in the current window when
multiple windows exist (via `edit`), which replaces the listing. It
should prefer the reading window to keep the listing visible.

**Files:** `domain/email/compose.lua:39-53`

### 8. Flag Picker Uses Freetext Input

`email.lua:606,640` uses `vim.fn.input` for flag add/remove with no
indication of which flags are already set. Replacing with `vim.ui.select`
showing current flag state (checked/unchecked) would be more
discoverable.

**Files:** `domain/email.lua:606,640`

### 9. Keybind Discoverability — No Help Float

All actions use `g`-prefix keybinds (gw, gr, gR, gf, etc.) with no
built-in help. A `?` binding that opens a float listing all active
keybinds would help new users. The `desc` metadata is already in place
on every binding. Optional `which-key` integration could also be added.

**Files:** `keybinds.lua`, `ui/listing.lua`, `ui/reading.lua`

### 10. Thread/Flat Toggle Loses Cursor Position

`gt` toggle between flat and thread modes always jumps to page 1 line 1.
Both modes have cursor-restoration infrastructure (`saved_cursor_id`,
`restore_email_id`). Capturing the current email ID before toggling and
passing it to the target mode's list function would preserve context.

**Files:** `domain/email/thread_listing.lua:217`, `ui/listing.lua:123`

### 11. Page Boundary Navigation Has No Feedback **(quick win)**

Pressing `gp` on page 1 or `gn` on the last page gives no feedback.
Adding a brief `vim.notify('Already on last page', INFO)` at the
early-return points would tell the user the command registered.

**Files:** `domain/folder.lua:62,73`

### 12. HimalayaSeen Links to Normal **(quick win)**

`listing.lua:19` defaults `HimalayaSeen` to `{ link = 'Normal' }`.
In some colorschemes Normal is styled, making seen emails more prominent
than unseen. `{ link = 'Comment' }` is conventionally dimmed in all
colorschemes and is a better default. Adding an explicit
`HimalayaUnseen` group would also help.

**Files:** `ui/listing.lua:19`

### 13. Thread Flags Column Blinks on Initial Render

Thread listing renders empty flags columns, then re-renders with real
flags after `enrich_with_flags` completes. A placeholder or using the
thread-fetch flags as initial data would eliminate the flash.

**Files:** `domain/email/thread_listing.lua:97`, `ui/thread_renderer.lua:18`

### 14. Raw CLI Errors in Notifications

`request.lua:43` fires two separate `vim.notify` calls (one for the
failure message, one for raw stderr). The CLI stderr often contains
long Rust backtraces. Combining into one notification and parsing common
error patterns would be more useful. `log.debug` also sends to
`vim.notify` at DEBUG level, spilling into notification history.

**Files:** `request.lua:43`, `log.lua:11`

### 15. Send Has No Preview or Validation

`compose.process_draft` sends immediately on `s<CR>` with no
confirmation showing recipients/subject. No warning on empty To: or
Subject: fields. A summary line before sending would reduce accidental
sends.

**Files:** `domain/email/compose.lua:127-159`

## Performance

*Completed items removed: `probe.cancel()` non-blocking callback,
`fit()` ASCII fast path, `format_date` one-sample width, `date_to_epoch`
epoch cache, `is_last_child` O(n) backward pass, `apply_header`
tab-scoped window scan, thread `resize()` O(1) id-to-index lookup,
`sign_getplaced` API, `enrich_with_flags` 200-envelope cap,
probe totals persistence, perf instrumentation spans.*

### 1. `complete_contact` Uses Blocking `vim.fn.system`

`email.lua:772` runs the contact-lookup command synchronously. For slow
backends (LDAP, remote notmuch) this freezes Neovim during completion.
Switching to `vim.system` (async) with a cached-result pattern would
eliminate the freeze.

**Files:** `domain/email.lua:748-779`

### 2. Probe Sequential Chain (Up to 9 Subprocesses)

`probe.lua:66-119` fires one CLI subprocess per page sequentially. An
exponential doubling strategy (probe page 2, 4, 8, 10) would reduce
worst-case round-trips from 9 to 4. A `--count-only` CLI flag would
eliminate them entirely.

**Files:** `domain/email/probe.lua:66-119`


## Architecture & Code Quality

*Completed items removed: `account_flag` dedup, shared keybinds, shared
renderer layout, config DI, paging extraction, function decomposition,
`resolve_target_ids` helper, `on_resize`/`do_resize` dead indirection,
`nargs` fix on zero-argument commands, `gutter_width` consolidation.*

### 1. Deduplicate `context_email_id`

`email.lua:173-178` and `compose.lua:13-19` both implement the same
listing-vs-read-buffer email ID resolution. Exporting
`email.context_email_id()` and calling it from compose eliminates the
duplication.

**Files:** `domain/email.lua:173`, `domain/email/compose.lua:13`

### 2. Extract Shared `effective_page_size()` Helper

The two-line `math.max(1, winheight) + winbar guard` pattern appears 6
times across `email.lua` and `thread_listing.lua`. A shared helper
(in `paging.lua` or a new `ui/layout.lua`) would centralize it.

**Files:** `domain/email.lua:167,280`, `domain/email/thread_listing.lua:31,168,184,273`

### 3. Move `_get_email_id_from_line` to UI Layer

`_get_email_id_from_line` is a UI/parsing concern living in the domain
module (`email.lua`). `thread_listing.lua` cross-requires `email`
specifically for it. Moving to `ui/listing.lua` would clean up the
module boundary. (`_bufwidth` was already consolidated into
`listing.gutter_width`.)

**Files:** `domain/email.lua:29-31`

### 4. Rename Misleading Underscore-Prefixed Public Functions

`_mark_seen` in `thread_listing.lua` is called from production code
(`email.lua:341`), not just tests. `_register_commands` /
`_register_filetypes` in `init.lua` are initialization entry points.
Renaming to drop the underscore (or to something descriptive like
`mark_seen_optimistic`) aligns with the codebase convention that `_`
means test-only.

**Files:** `domain/email/thread_listing.lua:293`, `init.lua:16,99`

### 5. Test Coverage Gaps

Untested modules/functions with non-trivial logic:

- `compose.process_draft` — the most complex function with a confirmed
  bug, zero tests
- `domain/email/probe.lua` — probe loop logic, stale-job handling
  (basic totals/persistence tested, sequential probe chain untested)
- `ui/search.lua` — reactive state machine, no tests
- `mark_envelope_seen` thread-listing dispatch branch — not covered
- `state/folder.lua` — `set()` page reset and `set_page(0)` clamping
  untested
- `request.lua` — `on_exit` error/parse paths untested

### 6. Remove `_G._himalaya_search_completefunc` Global Leak

`search.lua:203-252` sets a Lua global for `completefunc`. The `if not`
guard prevents updates without restart. Either always assign (remove
guard) or use `vim.fn.complete()` directly to eliminate the global.

**Files:** `ui/search.lua:203-252`
