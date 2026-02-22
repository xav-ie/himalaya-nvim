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
HimalayaSeen link target (declined), reading buffer close keybind (declined),
draft prompt BufLeave → BufHidden,
loading indicator during async fetches, next/prev email navigation
in reading buffer, compose targets reading window, thread/flat toggle
preserves cursor, thread flags pre-populated from cache, CLI error
messages combined + debug routed to :messages, confirmation dialogs
show email count, flag picker uses vim.ui.select, configurable keybinds
with help float (`?`), :w sends email + BufHidden prompts for draft,
thread page navigation boundary feedback, `ga`/`gA` keybind consistency,
`open_browser` from listing buffer, thread listing loading indicator,
account/folder picker current-selection annotation,
`download_attachments` structured feedback,
`account_state.list()` async cache with background refresh,
per-buffer account/folder state (`state/folder.lua` singleton eliminated,
`state/account.lua` global `current_account` replaced with per-buffer
`vim.b.himalaya_account/folder` via `state/context.lua` resolver;
thread-listing module-local display state remains module-level),
`vim.notify()` for page boundary feedback (replaced `vim.cmd('echohl …')`
with `log.warn()` across folder/thread_listing),
account/folder winbar context on reading/writing buffers.*

*Declined ideas: structured attachment download parsing (CLI already
formats output), draft badge in listing (unvalidated need), folder
picker inline help (violates picker UX conventions), batch operation
results summary (CLI doesn't expose per-email results), unread `◆`
badge (full-line dimming already better), search query syntax hints
(docs problem not UI problem), keybind hint on reading buffer open
(violates Vim non-intrusiveness), compose empty-body warning (CLI
handles it), compose header/body separator (`mail` filetype already
highlights headers differently; artificial separator would break CLI
template).*

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

*Declined ideas: ID-to-line cache for flat listing (called 1x per email
open on 20-50 items; ~1ms), lazy date parsing (needed for sort before
render), batch strdisplaywidth in `fit()` (most strings ASCII; network
I/O dominates 10x), single-pass seen highlights (already single-pass;
proposal misread code), contact completion inverted index (external
command dominates 100x; prefix refinement cache exists), skip
enrich_with_flags for far pages (intentional design trade-off), track
reading buffers in a set (1-5ms on 5-20 buffers; network dominates
100x), lazy syntax highlighting (applied 1x at buffer setup not in
render loop). Real bottleneck is network I/O (hundreds of ms); Lua-side
proposals save 1-10ms on cold paths.*

*No open items — section cleared.*

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
`folder.select_next_page` buffer type dispatch,
missing test coverage (`perf`, `account`, `thread_listing`, pickers,
`listing`/`reading`/`writing` setup, `ui/win`, `init`).*

*Declined ideas: EmmyLua type annotations (low ROI; Lua LSP fragile),
explicit data validators (CLI is source of truth; defensive access
exists), request/CLI abstraction (already done well in `request.lua`),
centralize buffer vars further (core done in `context.lua`; direct
`vim.b.*` access is idiomatic), decompose `email.lua` (large but not
disorganized; premature without friction), standardized error types
(over-engineering for Neovim plugin; `log.lua` is right level), state
invariant documentation (already covered by 7850 lines of tests),
extract renderer layout (pure functions already testable in-place),
search query DSL (current builder is clear; 728 lines reflects domain
complexity not debt), integration tests for key workflows (unit tests
already cover critical paths individually — compose answered flag,
mark_envelope_seen dispatch, page boundary warnings; mocked-boundary
integration tests would only test buffer variable propagation with no
realistic independent failure mode).*

*No open items — section cleared.*
