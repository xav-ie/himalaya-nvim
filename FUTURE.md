# Future Improvements

Improvement ideas for himalaya-vim, organized by category.

*Completed bugs: `vim.fn.delete(draft)` wrong variable in
`process_draft`.*

## Bugs

### 1. `compose.send` fires "answered" flag unconditionally

After `:w` sends an email, a second CLI command adds the "answered" flag
using `current_id` — even for new compositions and forwards where
`current_id` is empty or refers to an unrelated email. The flag-add also
fires without waiting for the send to succeed (data corruption if send
fails).

**Files:** `domain/email/compose.lua:144-161`

### 2. Database lock contention on rapid mode switch

`thread_listing.list()` does not cancel the flat listing's probe or
fetch jobs before issuing its `envelope thread` command. Both processes
compete for the same id-mapper database lock, producing "could not
acquire lock" errors.

**Files:** `domain/email/thread_listing.lua:151-228`,
`domain/email.lua:274-335`, `domain/email/probe.lua`

### 3. No double-send guard on `:w`

After a successful send, the compose buffer remains open and modifiable.
Pressing `:w` again dispatches another full send. The `sent` flag only
guards `process_draft`, not `send()` itself.

**Files:** `domain/email/compose.lua:133-161`

### 4. `process_draft` infinite loop on empty input

The `while true` loop re-prompts on unrecognized input. Pressing Enter
without typing returns `''`, which matches no branch, so the loop
repeats with no escape hatch.

**Files:** `domain/email/compose.lua:176-200`

### 5. `open_write_buffer` creates double window for new compose

For `msg == 'write'`, `botright new` (line 37) creates a split, then the
window-count check at line 39 is always false (already 2 windows), so
the code falls through to the reading-window search + `silent! edit`.
This may open two windows or replace the listing buffer.

**Files:** `domain/email/compose.lua:34-60`

### 6. `flags.lua` uses "Drafts" instead of "Draft"

The IMAP standard flag is `\Draft` (singular). `'Drafts'` in
`default_flags` may fail or silently do nothing when passed to the CLI.

**Files:** `domain/email/flags.lua:5`

### 7. `vim.bo` without bufnr in async callbacks

`on_list_with` uses `vim.bo.modifiable`, `vim.bo.filetype` etc. without
specifying a buffer number. If the user switches buffers between request
dispatch and callback, the wrong buffer gets its options set.

**Files:** `domain/email.lua:205-244`

### 8. Visual-mode ops include IDs from blank lines

`get_email_id_under_cursors()` collects empty strings for lines without
email IDs. These become extra spaces in the CLI command, potentially
causing parse failures.

**Files:** `domain/email.lua:51-59`

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
`complete_contact` prefix cache, probe exponential doubling.*

### 1. `mark_envelope_seen` full re-renders listing for one flag change

When the user reads an email, the entire listing is re-rendered (50
envelopes × `format_flags` + `format_date` + `fit` ×5 columns) plus all
extmarks are cleared and recreated. The thread listing correctly does a
single-extmark update instead.

**Files:** `domain/email.lua:347-401`, `ui/listing.lua:98-118`

### 2. Duplicated date parsing between renderer and tree

`renderer.format_date` and `tree.date_to_epoch` both parse the same ISO
date string with nearly identical regex and timezone arithmetic. For
thread listings, every envelope gets parsed twice.

**Files:** `ui/renderer.lua:64-95`, `domain/email/tree.lua:9-26`

### 3. `thread_renderer` calls `strdisplaywidth` per row for known-width prefixes

Tree prefixes are built from known 2-column-wide Unicode box-drawing
characters. The display width can be computed as `depth * 2` in pure Lua
instead of crossing the Lua→Vim bridge 50 times per render.

**Files:** `ui/thread_renderer.lua:28`

### 4. `log.debug` always formats strings even when not visible

Every CLI exit calls `log.debug` 2-4 times with `string.format`. Debug
logging is always on (no level check), creating string allocations for
probe fetches that nobody reads.

**Files:** `log.lua:18`, `request.lua:33-39`

### 5. `fit()` multi-byte fallback is O(n) linear scan

When truncating multi-byte strings (CJK, emoji), the code scans backward
from `nchars-1` calling `strdisplaywidth` at each step. Binary search
would reduce O(n) to O(log n) bridge crossings.

**Files:** `ui/renderer.lua:131-144`

### 6. `folder.open_picker` re-fetches folder list every time

Each folder operation (copy, move, select) spawns a `himalaya folder
list` CLI subprocess. Folder lists change infrequently; caching with a
TTL would eliminate repeated CLI calls.

**Files:** `domain/folder.lua:10-38`

### 7. Thread listing `WinResized` uses `nvim_list_wins` instead of tab-scoped

The thread listing WinResized handler scans all windows across all tabs
instead of just the current tabpage.

**Files:** `domain/email/thread_listing.lua` (resize handler)

## Architecture & Code Quality

*Completed items removed: `account_flag` dedup, shared keybinds, shared
renderer layout, config DI, paging extraction, function decomposition,
`resolve_target_ids` helper, `on_resize`/`do_resize` dead indirection,
`nargs` fix on zero-argument commands, `gutter_width` consolidation,
`context_email_id` dedup, `effective_page_size()` shared helper,
`get_email_id_from_line` moved to UI layer, underscore-prefix renames,
`_G._himalaya_search_completefunc` guard removal,
`set_page(0)` clamping + `request.on_exit` path tests.*

### 1. Duplicated "find reading/listing window" traversal (9 occurrences)

Multiple modules iterate `nvim_tabpage_list_wins`, check validity, get
buffer, and match on `himalaya_buffer_type` or buffer name. Some check
the buffer type var, some check the name — inconsistent detection.

**Files:** `domain/email.lua` (4×), `domain/email/compose.lua` (1×),
`domain/email/thread_listing.lua` (1×), `ui/listing.lua` (2×),
`ui/reading.lua` (1×)

### 2. Dead code: `flags.complete()` and `autoload/` directory

`flags.complete()` returns a newline-joined string for VimScript. It is
never called from Lua code (flag operations now use `vim.ui.select`).
The entire `autoload/` directory is vestigial.

**Files:** `domain/email/flags.lua:13-15`, `autoload/`

### 3. `config.get()` returns mutable reference

Any module can accidentally mutate the config table.
`thread_listing.toggle_reverse()` already does this intentionally,
bypassing `config.setup()`.

**Files:** `config.lua:31`, `domain/email/thread_listing.lua:261-262`

### 4. `search.open` bypasses `account_state.flag()`

Manually constructs `'--account ' .. account` instead of using the
shared helper. Would diverge if `flag()` is ever updated.

**Files:** `ui/search.lua:245`

### 5. `compose.open_write_buffer` — `found_reading` has no branching effect

The variable is set but the function unconditionally runs `vim.cmd('edit')`
regardless of its value.

**Files:** `domain/email/compose.lua:43-55`

### 6. Missing test coverage

No tests for: `perf.lua`, `domain/account.lua` (picker rotation),
`ui/thread_listing.lua` (setup/keybinds), picker modules beyond native.
UI setup test files (`listing_spec`, `reading_spec`, `writing_spec`) are
minimal stubs.

### 7. `probe.on_cancel_cb` can be silently overwritten

If `probe.cancel(callback)` is called twice rapidly, the first callback
is discarded without ever firing. Could leave the UI in a permanent
"loading..." state.

**Files:** `domain/email/probe.lua:12, 92-106, 166-174`

### 8. `folder.select_next_page` doesn't check buffer type

The `HimalayaNextPage` command calls `folder.select_next_page()`
unconditionally. In thread mode, it uses flat-listing line-count
heuristics against thread buffer content.

**Files:** `domain/folder.lua:58-63`, `init.lua:79`
