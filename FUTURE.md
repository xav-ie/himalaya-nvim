# Future Improvements

Improvement ideas for himalaya-vim, organized by category.

## UI/UX

### 1. Inline Delete Confirmation with Visual Undo Feedback

Replace the `vim.fn.inputdialog` text prompt for delete/move confirmation with a brief inline status-line message that also highlights the affected rows before acting. Optionally allow an "undo" grace window after the action completes.

The current flow in `M.delete` and `M.move` blocks the editor with a command-line prompt (`'Delete email(s) %s? [Y/n] '`) that shows only raw IDs -- not subjects. Showing the email subject(s) in a highlighted row color before deletion, and presenting the prompt in the status area or a small float, would be less disorienting. A post-action "press u to undo" hint leveraging the existing `saved_cursor_id` restore mechanism would reduce anxiety around destructive operations.

**Files:** `domain/email.lua`, `config.lua`, `ui/listing.lua`

### 2. Keymap Help Float

A buffer-local `?` binding on all himalaya filetypes that opens a small centered floating window listing the current buffer's keybindings and their descriptions, drawn from the `keybinds.define` tables.

The `keybinds.define` function already stores both a `<Plug>` name and a human-readable name string for every binding. New users and infrequent users have no discoverable way to learn available actions without reading the README. The `g`-prefix bindings are not mnemonic enough to memorize without help.

**Files:** `keybinds.lua`, `ui/listing.lua`, `ui/thread_listing.lua`, `ui/reading.lua`, `ui/writing.lua`

### 3. Unread Count and Active-Filter Status in the Winbar Header

Extend the winbar header to include a small status suffix: unread count for the current page and an indicator when a search filter is active.

Right now the buffer name carries query state, but there is no at-a-glance unread counter visible at all times, and no obvious visual distinction between "no filter" and an active search. The envelope data is already in `vim.b.himalaya_envelopes`; counting unseen flags is trivial.

**Files:** `ui/renderer.lua`, `domain/email.lua`, `ui/listing.lua`, `domain/email/thread_listing.lua`

### 4. Compose: Structured Header Editing with Field-Aware Cursor Placement

When the compose/reply/forward write buffer opens, automatically move the cursor to the appropriate header field: new compose lands on `To:`, reply lands on the body (since `To:` and `Subject:` are pre-filled), and forward lands on `To:`. Currently `open_write_buffer` always calls `vim.cmd('0')` which places the cursor on line 1 regardless of context.

**Files:** `domain/email/compose.lua`, `ui/writing.lua`

### 5. Search Popup: Live Result Count Feedback

Show a dynamically updated "N matches" count in the search popup's border title or as a virtual-text annotation on the `query:` line, updated with debounce as the user types in the search fields.

The search popup already has a reactive system where field edits propagate to the `query:` line in real time. However, the user has no way to know whether their search will return 0, 3, or 300 emails until they press `<CR>` and wait for the full fetch.

**Files:** `ui/search.lua`, `request.lua`

### 6. Reading Buffer: Persistent Navigation Between Emails (Next/Previous)

Add `]e` / `[e` (or `gj` / `gk`) bindings on the reading buffer that navigate to the next or previous email in the listing without returning focus to the listing window first.

The reading buffer currently offers reply, forward, copy, move, delete, and browser-open -- but no way to move to the adjacent email without switching windows and pressing `<CR>` again.

**Files:** `ui/reading.lua`, `domain/email.lua`, `domain/email/thread_listing.lua`

### 7. Draft Save: Autosave on a Timer

Add a configurable periodic autosave (e.g. every 60 seconds) for the compose buffer, in addition to the existing `BufWriteCmd` / `BufLeave` triggers that call `compose.save_draft()`.

If Neovim crashes, or the user closes the window with `:q!` while distracted, the draft is gone. A `vim.uv.new_timer()` autosave following the same pattern used in `email.lua`'s resize debouncer would protect long-form email composition.

**Files:** `domain/email/compose.lua`, `ui/writing.lua`, `config.lua`

### 8. Thread View: Collapsed/Expanded Toggle per Thread Root

In thread-listing mode, allow pressing `<Tab>` (or `za`) on a thread root line to fold/unfold its replies in-place, rather than showing all threads fully expanded at all times.

The thread renderer already constructs tree-prefix strings and the tree builder tracks `depth`, `is_last_child`, and `thread_idx`. When an inbox has 10 threads each with 8 replies, the current rendering shows all 80+ lines simultaneously, making it hard to get a high-level overview.

**Files:** `domain/email/tree.lua`, `domain/email/thread_listing.lua`, `ui/thread_listing.lua`, `ui/thread_renderer.lua`

## Performance & Reliability

### 1. Eliminate the Synchronous Probe Cancellation Block

`probe.cancel()` calls `job:wait(3000)` followed by `job:wait(1000)` -- a synchronous block on the main Neovim thread -- to ensure the CLI process releases its database lock before a new fetch starts.

Any user action that triggers a new fetch blocks the UI for up to 4 seconds in the worst case. A non-blocking approach using `vim.uv` timers to delay the new fetch until the probe exits would eliminate this stall entirely.

**Files:** `domain/email/probe.lua`, `domain/email.lua`

### 2. Cache Date Parsing Results

Both `renderer.format_date()` and `date_to_epoch()` in `tree.lua` re-parse the same ISO date strings every time they are called -- with full regex matching, `os.time()` construction, and timezone arithmetic each time. `format_date` is called at least twice per envelope per render pass.

A per-render memoization table keyed on the raw date string would reduce N envelope renders from 2N `os.time()` calls to at most N on first render, and 0 on re-renders of the same dataset.

**Files:** `ui/renderer.lua`, `domain/email/tree.lua`

### 3. Replace the Quadratic `fit()` Truncation Loop with Binary Search

The `renderer.fit()` function truncates over-long strings by iterating from `nchars-1` down to 0, calling `vim.fn.strcharpart()` and `vim.fn.strdisplaywidth()` on every candidate prefix. This is O(N) Vimscript FFI calls per truncation.

Since `strdisplaywidth` is monotonically non-decreasing, binary search would find the correct truncation point in O(log N) FFI calls.

**Files:** `ui/renderer.lua`

### 4. Make `enrich_with_flags` Page-Aware

`enrich_with_flags()` always fetches `#all_display_rows` envelopes, meaning for a mailbox with 500 threaded messages it fires a CLI request for all 500 envelopes just to get flag data.

Only the currently visible page slice (typically 30-50 rows) needs immediate flag enrichment. Background enrichment of adjacent pages could be done lazily.

**Files:** `domain/email/thread_listing.lua`

### 5. Deduplicate Redundant `_bufwidth()` and Gutter Computations During Resize

During `resize_listing()`, `M._bufwidth()` queries multiple window options each time. Similarly, `listing.apply_header()` calls `gutter_width()` per window, which duplicates the sign query. `WinResized` can fire many times per second during a drag resize.

Caching the computed buffer width for the duration of a single render call would eliminate the duplicate queries.

**Files:** `domain/email.lua`, `ui/listing.lua`, `ui/renderer.lua`

### 6. Persist the Probe `totals` Table Across Folder Revisits

`probe.reset_if_changed()` wipes the entire `totals` table whenever the account, folder, or query changes. Returning to a previously visited folder restarts the full probe chain from scratch.

Keying the totals table by `(account, folder, query)` tuples and retaining all entries -- only invalidating the specific key on a mutating action -- would make page count display instant on revisit.

**Files:** `domain/email/probe.lua`, `domain/email.lua`

### 7. Replace the Blocking `vim.fn.system` in Contact Completion with Async `vim.system`

`M.complete_contact()` calls `vim.fn.system(cmd)` -- a fully synchronous, blocking shell invocation -- to run the user-configured contact completion command. This runs on the main thread during omnifunc completion.

If the contact lookup command is slow, this blocks all of Neovim until it returns.

**Files:** `domain/email.lua`

### 8. Extend `perf` Instrumentation to Thread Listing and Probe Code Paths

The `perf` module is currently only wired into `resize_listing` and the flat renderer. The thread listing, `enrich_with_flags`, `tree.build`, `tree.build_prefix`, and `probe.run_probe` paths are entirely un-instrumented.

Adding `perf.start/stop` spans around these paths would provide the empirical data needed to prioritize the other improvements.

**Files:** `perf.lua`, `domain/email/tree.lua`, `domain/email/thread_listing.lua`, `domain/email/probe.lua`

## Architecture & Code Quality

### 1. Extract a Shared `listing_context` Module

`email.lua` (flat listing) and `email/thread_listing.lua` (thread listing) duplicate parallel logic: module-local state variables, page-size computation, and the `_mark_seen` / `mark_envelope_seen` split.

A `listing_context` module could own these shared concerns, making both modes consistent by construction and reducing the surface area for bugs.

**Files:** `domain/email.lua`, `domain/email/thread_listing.lua`

### 2. Eliminate the Four Copies of `account_flag()`

The private helper `local function account_flag(account)` is duplicated verbatim in four files: `email.lua`, `thread_listing.lua`, `compose.lua`, and `folder.lua`.

Moving it to `state/account.lua` as `M.flag()` would make it a single source of truth.

**Files:** `domain/email.lua`, `domain/email/thread_listing.lua`, `domain/email/compose.lua`, `domain/folder.lua`, `state/account.lua`

### 3. Consolidate the Duplicate Keybind Tables

Both `listing.lua` and `thread_listing.lua` define nearly identical keybind tables in their `setup()` functions. The shared actions are copy-pasted identically. Only 3-4 bindings differ between the two modes.

Extracting a `shared_keybinds(bufnr)` function would make both listing setups call it, then add only their mode-specific bindings on top.

**Files:** `ui/listing.lua`, `ui/thread_listing.lua`, `keybinds.lua`

### 4. Separate Rendering Logic from Buffer/Window Mutation

`on_list_with` and `resize_listing` are large functions that interleave three distinct concerns: computing pagination/slice math, mutating buffer state, and orchestrating re-renders.

Extracting the pure-computation parts (page math, slice selection) into separate functions would make them unit-testable without a full Neovim environment.

**Files:** `domain/email.lua`, `tests/domain/email_spec.lua`

### 5. Replace Module-Level Mutable State with Explicit State Objects

`email.lua`, `thread_listing.lua`, and `probe.lua` each hold mutable state as module-level locals. Because Neovim's Lua modules are singletons, this state is shared across all operations. Tests must `package.loaded['...'] = nil` between each case to reset it.

Encapsulating state in a returned table or constructor function would allow multiple independent instances, make state transitions explicit, and remove the need for `_test_only` accessors.

**Files:** `domain/email.lua`, `domain/email/thread_listing.lua`, `domain/email/probe.lua`

### 6. Unify the Two Renderer Modules Under a Shared Layout Engine

`renderer.lua` and `thread_renderer.lua` share 90% of their layout code: column-width computation, overhead/gutter constants, `row_fmt` string, and header/separator construction. `thread_renderer.lua` redefines `FLAG_ORDER`, `BOX_V`, `BOX_H`, `BOX_CROSS` locally.

Extracting column-width + header/separator computation into a shared function would eliminate the duplication.

**Files:** `ui/renderer.lua`, `ui/thread_renderer.lua`

### 7. Move `config.get()` Inline-Call Pattern Toward Dependency Injection

Across multiple modules, `config.get()` is called at the point of use inside functions rather than being passed as a parameter. Tests that need to vary config settings must either `config.setup(...)` globally or reload the module.

Passing `cfg` as a parameter to rendering functions would make them referentially transparent, enabling property-based testing and removing the need for `_reset()` as a test-cleanup hack.

**Files:** `config.lua`, `ui/renderer.lua`, `ui/thread_renderer.lua`, `domain/email.lua`, `domain/email/compose.lua`
