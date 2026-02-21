# Future Improvements

Improvement ideas for himalaya-vim, organized by category.

*Completed bugs: `vim.fn.delete(draft)` wrong variable in
`process_draft`, answered flag unconditional + fires before send succeeds,
database lock contention on rapid mode switch, no double-send guard on `:w`,
`process_draft` infinite loop on empty input, double window for new compose,
`flags.lua` "Drafts" → "Draft", `vim.bo` without bufnr in async callbacks,
visual-mode ops include IDs from blank lines.*

## UI/UX

*Completed/removed items: search folder field stale on reopen,
page boundary navigation feedback, search popup key hints (declined),
HimalayaSeen link target (declined), draft prompt BufLeave → BufHidden,
loading indicator during async fetches, next/prev email navigation
in reading buffer, compose targets reading window, thread/flat toggle
preserves cursor, thread flags pre-populated from cache, CLI error
messages combined + debug routed to :messages, confirmation dialogs
show email count, flag picker uses vim.ui.select, configurable keybinds
with help float (`?`), :w sends email + BufHidden prompts for draft.*

### 1. Thread listing has no loading indicator

The flat listing shows a "loading..." winbar during fetches. The thread
listing does not — on slow connections, users see stale content with no
feedback.

**Files:** `domain/email/thread_listing.lua:143-228`

### 2. Thread page navigation has no first/last page feedback

Flat listing shows "Already on first/last page" warnings. Thread listing
silently does nothing when the user is already at the boundary.

**Files:** `domain/email/thread_listing.lua:231-239`

### 3. Reading buffer has no close keybind

The reading buffer has keybinds for compose, navigate, attachments, etc.
but no quick way to close and return focus to the listing. Users must
use `:q` or `<C-w>c`.

**Files:** `ui/reading.lua:32-58`

### 4. Account/folder picker doesn't show current selection

Both pickers rotate the list but don't visually indicate which entry is
already active. The user must memorize or look at the buffer title.

**Files:** `domain/account.lua:19-26`, `domain/folder.lua:10-38`

### 5. `ga` keybind inconsistent between listing and reading

In the listing, `ga` = account select, `gA` = download attachments.
In the reading buffer, `ga` = download attachments. No account select
in reading.

**Files:** `ui/reading.lua:49`, `keybinds.lua:102-105`

### 6. `download_attachments` gives no path or count feedback

Shows raw CLI output on success. No indication of where files were saved,
how many, or whether there were no attachments.

**Files:** `domain/email.lua:714-726`

### 7. `account_state.list()` blocks UI with synchronous wait

Uses `vim.system(cmd):wait()` which freezes Neovim until the CLI returns.
Fires on `:Himalaya <Tab>` completion and account picker.

**Files:** `state/account.lua:27`

### 8. `open_browser` only available from reading buffer

No listing-level keybind — user must first open the email, then press
`go`. Two steps for a single action.

**Files:** `domain/email.lua:729-740`, `ui/reading.lua`

### 9. Folder state is global singleton

`current_folder`, `current_page`, `current_account` are module-level
locals. Opening `:Himalaya` in two tabs shares state; changing folder in
one tab changes it in the other. Could target wrong folder for
delete/move/copy.

**Files:** `state/folder.lua`, `state/account.lua`

## Performance

*Completed items removed: `probe.cancel()` non-blocking callback,
`fit()` ASCII fast path, `format_date` one-sample width, `date_to_epoch`
epoch cache, `is_last_child` O(n) backward pass, `apply_header`
tab-scoped window scan, thread `resize()` O(1) id-to-index lookup,
`sign_getplaced` API, `enrich_with_flags` 200-envelope cap,
probe totals persistence, perf instrumentation spans,
`complete_contact` prefix cache, probe exponential doubling,
`mark_envelope_seen` single-line update instead of full re-render,
deduplicated date parsing → `tree.date_to_epoch` shared,
thread prefix width `depth * 2` pure Lua (no strdisplaywidth),
`log.debug` gated behind `vim.g.himalaya_debug` + lazy format args,
`fit()` multi-byte binary search O(log n),
`folder.open_picker` 60s folder list cache,
thread listing WinResized tab-scoped.*

## Architecture & Code Quality

*Completed items removed: `account_flag` dedup, shared keybinds, shared
renderer layout, config DI, paging extraction, function decomposition,
`resolve_target_ids` helper, `on_resize`/`do_resize` dead indirection,
`nargs` fix on zero-argument commands, `gutter_width` consolidation,
`context_email_id` dedup, `effective_page_size()` shared helper,
`get_email_id_from_line` moved to UI layer, underscore-prefix renames,
`_G._himalaya_search_completefunc` guard removal,
`set_page(0)` clamping + `request.on_exit` path tests,
`found_reading` dead variable in `open_write_buffer`,
window traversal dedup → `ui/win.lua` helper,
dead code `flags.complete()` + `autoload/` directory,
`config.set()` for proper mutation + `toggle_reverse` fix,
`search.open` account flag bypass,
`probe.on_cancel_cb` double-cancel callback loss,
`folder.select_next_page` buffer type dispatch.*

### 1. Missing test coverage

No tests for: `perf.lua`, `domain/account.lua` (picker rotation),
`ui/thread_listing.lua` (setup/keybinds), picker modules beyond native.
UI setup test files (`listing_spec`, `reading_spec`, `writing_spec`) are
minimal stubs.
