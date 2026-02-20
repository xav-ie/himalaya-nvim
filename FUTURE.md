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
messages combined + debug routed to :messages, confirmation dialogs
show email count, flag picker uses vim.ui.select, configurable keybinds
with help float (`?`), :w sends email + BufHidden prompts for draft.*

All UI/UX items have been completed.

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
