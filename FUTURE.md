# Future Improvements

Improvement ideas for himalaya-vim, organized by category. Items marked
with **(quick win)** can typically be done in under 30 minutes each.

*Completed bugs: `vim.fn.delete(draft)` wrong variable in
`process_draft`.*

## UI/UX

*Completed/removed items: search folder field stale on reopen,
page boundary navigation feedback, search popup key hints (declined),
HimalayaSeen link target (declined).*

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

### 4. No Next/Previous Email Navigation in Reading Buffer

The reading buffer has reply, forward, copy, move, delete, and
browser-open bindings but no way to advance to the adjacent email
without switching windows. Adding `gn`/`gp` that find the listing
window, move cursor, and call `read()` would match standard email client
behavior.

**Files:** `ui/reading.lua:21`, `domain/email.lua`

### 5. Compose Opens in Wrong Window

`compose.lua:39-53` opens reply/forward in the current window when
multiple windows exist (via `edit`), which replaces the listing. It
should prefer the reading window to keep the listing visible.

**Files:** `domain/email/compose.lua:39-53`

### 6. Flag Picker Uses Freetext Input

`email.lua:606,640` uses `vim.fn.input` for flag add/remove with no
indication of which flags are already set. Replacing with `vim.ui.select`
showing current flag state (checked/unchecked) would be more
discoverable.

**Files:** `domain/email.lua:606,640`

### 7. Keybind Discoverability — No Help Float

All actions use `g`-prefix keybinds (gw, gr, gR, gf, etc.) with no
built-in help. A `?` binding that opens a float listing all active
keybinds would help new users. The `desc` metadata is already in place
on every binding. Optional `which-key` integration could also be added.

**Files:** `keybinds.lua`, `ui/listing.lua`, `ui/reading.lua`

### 8. Thread/Flat Toggle Loses Cursor Position

`gt` toggle between flat and thread modes always jumps to page 1 line 1.
Both modes have cursor-restoration infrastructure (`saved_cursor_id`,
`restore_email_id`). Capturing the current email ID before toggling and
passing it to the target mode's list function would preserve context.

**Files:** `domain/email/thread_listing.lua:217`, `ui/listing.lua:123`

### 9. Thread Flags Column Blinks on Initial Render

Thread listing renders empty flags columns, then re-renders with real
flags after `enrich_with_flags` completes. A placeholder or using the
thread-fetch flags as initial data would eliminate the flash.

**Files:** `domain/email/thread_listing.lua:97`, `ui/thread_renderer.lua:18`

### 10. Raw CLI Errors in Notifications

`request.lua:43` fires two separate `vim.notify` calls (one for the
failure message, one for raw stderr). The CLI stderr often contains
long Rust backtraces. Combining into one notification and parsing common
error patterns would be more useful. `log.debug` also sends to
`vim.notify` at DEBUG level, spilling into notification history.

**Files:** `request.lua:43`, `log.lua:11`

### 11. Send Has No Preview or Validation

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
probe totals persistence, perf instrumentation spans,
`complete_contact` prefix cache, probe exponential doubling.*

All performance items have been completed.


## Architecture & Code Quality

*Completed items removed: `account_flag` dedup, shared keybinds, shared
renderer layout, config DI, paging extraction, function decomposition,
`resolve_target_ids` helper, `on_resize`/`do_resize` dead indirection,
`nargs` fix on zero-argument commands, `gutter_width` consolidation,
`context_email_id` dedup, `effective_page_size()` shared helper,
`get_email_id_from_line` moved to UI layer, underscore-prefix renames,
`_G._himalaya_search_completefunc` guard removal,
`set_page(0)` clamping + `request.on_exit` path tests.*

All architecture items have been completed.
