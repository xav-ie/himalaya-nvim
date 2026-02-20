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

### 2. `probe.run_probe` Missing `on_error` Job Cleanup

`probe.lua:70` creates a job via `request.json` without an `on_error`
handler. When the CLI fails, `job` is never set to `nil`. A later
`M.cancel()` then calls `job:kill()` on a stale handle. Every other
request site (`email.lua`, `thread_listing.lua`) has `on_error` handlers
that nil out the handle.

**Fix:** Add `on_error = function() job = nil end` to the `request.json`
call in `run_probe`.

**Files:** `domain/email/probe.lua:70`

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

### 1. `probe.cancel()` Blocks Up to 4 Seconds

`probe.lua:137-147` calls `job:wait(3000)` then `job:wait(1000)` — a
synchronous block on the main thread. This fires on every interactive
action (list, read, delete, copy, move, flag). Reducing the initial
timeout to 200-400ms (enough for SIGTERM on a local process) would
eliminate perceptible freezes.

**Files:** `domain/email/probe.lua:137-147`

### 2. `fit()` O(n) vim.fn Call Loop

`renderer.lua:103-131` truncates over-long strings by scanning backward
from `nchars-1`, calling `vim.fn.strcharpart` + `vim.fn.strdisplaywidth`
per character. Two fixes:

- **ASCII fast path (trivial):** For ASCII-only strings (`s:match('^[\x01-\x7f]*$')`), use
  pure Lua string ops — no vim.fn needed. Covers the vast majority of
  Latin-alphabet email subjects/senders.
- **Binary search (moderate):** For multi-byte strings, bisect on character
  offset since `strdisplaywidth` is monotonically non-decreasing.

**Files:** `ui/renderer.lua:103-131`

### 3. `format_date` Called 2N Times per Render

`compute_layout` calls `format_date` N times purely to measure date
column width, then `render` calls it N more times for the actual strings.
Since `date_format` is a fixed strftime format, its output width is
constant — the width can be computed once with any valid epoch. The
per-envelope loop is unnecessary.

**Fix:** When `date_format` is configured, compute `date_w` as
`#os.date(cfg.date_format, os.time())` and skip the loop. Fall back to
the loop only when `date_format` is nil.

**Files:** `ui/renderer.lua:162-165`

### 4. `date_to_epoch` Re-Parsed in Sort Comparators

`tree.lua:88-95` calls `date_to_epoch` on every `table.sort` comparison.
For a 10-child node that's ~66 `os.time()` calls. Pre-computing into an
`{id → epoch}` cache table before sorting reduces all lookups to O(1).

**Files:** `domain/email/tree.lua:88-95`

### 5. `is_last_child` O(n^2) Nested Loop **(quick win)**

`tree.lua:191-205` scans forward from each row to find siblings. For N
display rows this is O(N^2). A single backward pass tracking
`last_seen_depth[d]` reduces it to O(N).

**Files:** `domain/email/tree.lua:191-205`

### 6. `enrich_with_flags` Fetches All Rows

`thread_listing.lua:100-102` fetches `#all_display_rows` envelopes for
flags. For 500-row thread views this is a large redundant fetch. Limiting
to the visible page size (typically 30-50 rows) is a 10x reduction.
Alternatively, if the thread-fetch flags are fresh enough, skip the
second fetch entirely.

**Files:** `domain/email/thread_listing.lua:97-126`

### 7. Thread `resize()` O(n) Scan on Every WinResized **(quick win)**

`thread_listing.lua:263-270` linearly scans `all_display_rows` to find
the cursor email. The same O(n) pattern appears in `_mark_seen` and
`list()`. Maintaining a module-local `{id → index}` table rebuilt when
`all_display_rows` changes would make all lookups O(1).

**Files:** `domain/email/thread_listing.lua:254-283`

### 8. `_bufwidth` / `gutter_width` Re-Computed on Every Render

`email.lua:60-76` and `listing.lua:44-61` compute identical gutter
widths using `sign place` (a Vimscript exec). Both fire on every resize
and render. Caching per render pass and using `vim.fn.sign_getplaced()`
(Lua API) instead of string-splitting exec output would reduce overhead.

**Files:** `domain/email.lua:60-76`, `ui/listing.lua:44-61`

### 9. `apply_header` Scans All Windows Globally **(quick win)**

`listing.lua:66-75` uses `nvim_list_wins()` (all tabs) instead of
`nvim_tabpage_list_wins(0)` (current tab). In multi-tab sessions this
scans unnecessary windows.

**Files:** `ui/listing.lua:66-75`

### 10. `complete_contact` Uses Blocking `vim.fn.system`

`email.lua:772` runs the contact-lookup command synchronously. For slow
backends (LDAP, remote notmuch) this freezes Neovim during completion.
Switching to `vim.system` (async) with a cached-result pattern would
eliminate the freeze.

**Files:** `domain/email.lua:748-779`

### 11. Probe Sequential Chain (Up to 9 Subprocesses)

`probe.lua:66-119` fires one CLI subprocess per page sequentially. An
exponential doubling strategy (probe page 2, 4, 8, 10) would reduce
worst-case round-trips from 9 to 4. A `--count-only` CLI flag would
eliminate them entirely.

**Files:** `domain/email/probe.lua:66-119`

### 12. Persist Probe Totals Across Folder Revisits

`probe.reset_if_changed()` wipes the totals table on folder/query
change. Keying by `(account, folder, query)` and retaining entries would
make page count instant on revisit.

**Files:** `domain/email/probe.lua`

### 13. Extend `perf` Instrumentation **(quick win)**

Missing timers: `tree.build`, `tree.build_prefix`, `thread_renderer.render`,
`probe.cancel()`, `_bufwidth()`, `enrich_with_flags`. Adding `perf.start/stop`
spans would provide the empirical data to prioritize the other items.

**Files:** `perf.lua`, `domain/email/tree.lua`, `domain/email/thread_listing.lua`, `domain/email/probe.lua`

## Architecture & Code Quality

*Completed items removed: `account_flag` dedup, shared keybinds, shared
renderer layout, config DI, paging extraction, function decomposition.*

### 1. Extract `resolve_target_ids` Helper **(quick win)**

The 7-line ID-resolution block (listing-vs-reading, visual-range-vs-cursor)
is copy-pasted seven times in `email.lua` (`delete`, `copy`, `move`,
`flag_add`, `flag_remove`, `mark_seen`, `mark_unseen`). Extracting into
a single `local function resolve_target_ids(first_line, last_line)` and
calling from each action removes the duplication.

**Files:** `domain/email.lua:466-698`

### 2. Consolidate `gutter_width` / `_bufwidth`

`email.lua:60-76` (`M._bufwidth`) and `listing.lua:44-61`
(`gutter_width`) compute identical gutter metrics with slightly different
signatures. Exporting `listing.gutter_width(winid, bufnr)` and
rewriting `_bufwidth` to call it gives one source of truth.

**Files:** `domain/email.lua:60-76`, `ui/listing.lua:44-61`

### 3. Deduplicate `context_email_id`

`email.lua:173-178` and `compose.lua:13-19` both implement the same
listing-vs-read-buffer email ID resolution. Exporting
`email.context_email_id()` and calling it from compose eliminates the
duplication.

**Files:** `domain/email.lua:173`, `domain/email/compose.lua:13`

### 4. Extract Shared `effective_page_size()` Helper

The two-line `math.max(1, winheight) + winbar guard` pattern appears 6
times across `email.lua` and `thread_listing.lua`. A shared helper
(in `paging.lua` or a new `ui/layout.lua`) would centralize it.

**Files:** `domain/email.lua:167,280`, `domain/email/thread_listing.lua:31,168,184,273`

### 5. Move `_bufwidth` and `_get_email_id_from_line` to UI Layer

Both are UI/parsing concerns living in the domain module (`email.lua`).
`thread_listing.lua` cross-requires `email` specifically for these.
Moving to `ui/listing.lua` would clean up the module boundary.

**Files:** `domain/email.lua:29-31,60-75`

### 6. Remove `on_resize`/`do_resize` Dead Indirection **(quick win)**

`listing.lua:128-156` has `on_resize` calling `do_resize` with no
additional logic. Eliminate the wrapper.

**Files:** `ui/listing.lua:128-156`

### 7. Rename Misleading Underscore-Prefixed Public Functions

`_mark_seen` in `thread_listing.lua` is called from production code
(`email.lua:341`), not just tests. `_register_commands` /
`_register_filetypes` in `init.lua` are initialization entry points.
Renaming to drop the underscore (or to something descriptive like
`mark_seen_optimistic`) aligns with the codebase convention that `_`
means test-only.

**Files:** `domain/email/thread_listing.lua:293`, `init.lua:16,99`

### 8. Fix `nargs = '*'` on Zero-Argument Commands **(quick win)**

Most user commands in `init.lua` use `nargs = '*'` but never inspect
arguments. Changing to `nargs = '0'` would reject accidental arguments
instead of silently ignoring them.

**Files:** `init.lua:44-88`

### 9. Test Coverage Gaps

Untested modules/functions with non-trivial logic:

- `compose.process_draft` — the most complex function with a confirmed
  bug, zero tests
- `domain/email/probe.lua` — probe loop logic, stale-job handling, no
  tests at all
- `ui/search.lua` — reactive state machine, no tests
- `mark_envelope_seen` thread-listing dispatch branch — not covered
- `state/folder.lua` — `set()` page reset and `set_page(0)` clamping
  untested
- `request.lua` — `on_exit` error/parse paths untested

### 10. Remove `_G._himalaya_search_completefunc` Global Leak

`search.lua:203-252` sets a Lua global for `completefunc`. The `if not`
guard prevents updates without restart. Either always assign (remove
guard) or use `vim.fn.complete()` directly to eliminate the global.

**Files:** `ui/search.lua:203-252`
