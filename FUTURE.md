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
thread-listing module-local display state remains module-level).*

*No open items — section cleared.*

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
`folder.select_next_page` buffer type dispatch,
missing test coverage (`perf`, `account`, `thread_listing`, pickers,
`listing`/`reading`/`writing` setup, `ui/win`, `init`).*

*No open items — section cleared.*
