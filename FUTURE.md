# Future Improvements

Improvement ideas for himalaya-vim, organized by category. Items marked
with **(quick win)** can typically be done in under 30 minutes each.

*Completed bugs: `vim.fn.delete(draft)` wrong variable in
`process_draft`.*

## UI/UX

*Completed/removed items: search folder field stale on reopen,
page boundary navigation feedback, search popup key hints (declined),
HimalayaSeen link target (declined), draft prompt BufLeave → BufHidden,
loading indicator during async fetches, next/prev email navigation
in reading buffer, compose targets reading window, thread/flat toggle
preserves cursor, thread flags pre-populated from cache, CLI error
messages combined + debug routed to :messages.*

### 1. Confirmation Dialogs Use `vim.fn.inputdialog`

`email.lua:477,547` uses `inputdialog` with a `'_cancel_'` sentinel for
delete/move confirmation. The prompt shows raw IDs with no context
(subject/sender), blocks the event loop, and accepts only single-char
`y`/`Y`. `vim.ui.select` with "Yes, delete" / "No, cancel" options
showing the subject would be less disorienting.

**Files:** `domain/email.lua:477,547`

### 2. Flag Picker Uses Freetext Input

`email.lua:606,640` uses `vim.fn.input` for flag add/remove with no
indication of which flags are already set. Replacing with `vim.ui.select`
showing current flag state (checked/unchecked) would be more
discoverable.

**Files:** `domain/email.lua:606,640`

### 3. Keybind Discoverability — No Help Float

All actions use `g`-prefix keybinds (gw, gr, gR, gf, etc.) with no
built-in help. A `?` binding that opens a float listing all active
keybinds would help new users. The `desc` metadata is already in place
on every binding. Optional `which-key` integration could also be added.

**Files:** `keybinds.lua`, `ui/listing.lua`, `ui/reading.lua`

### 4. Send Has No Preview or Validation

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
