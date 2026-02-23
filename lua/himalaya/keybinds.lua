local M = {}

function M.define(bufnr, bindings)
  local cfg = require('himalaya.config').get()
  local overrides = cfg.keymaps or {}

  for _, binding in ipairs(bindings) do
    local mode, key, callback, name = binding[1], binding[2], binding[3], binding[4]
    local plug = '<Plug>(himalaya-' .. name .. ')'

    vim.keymap.set(mode, plug, callback, { silent = true, desc = 'Himalaya: ' .. name })

    local user_key = overrides[name]
    if user_key ~= false then
      local actual_key = user_key or key
      if vim.fn.hasmapto(plug, mode) == 0 then
        vim.keymap.set(mode, actual_key, plug, { buffer = bufnr, nowait = true, desc = 'Himalaya: ' .. name })
      end
    end
  end
end

--- Wrap a function that takes (first_line, last_line) for use in visual mode.
--- Gets the visual range, calls fn(first, last), and exits visual mode.
--- @param fn function(first: number, last: number)
--- @return function
function M.visual_range(fn)
  return function()
    local first = vim.fn.line('v')
    local last = vim.fn.line('.')
    if first > last then
      first, last = last, first
    end
    fn(first, last)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  end
end

--- Show a floating window listing all Himalaya keybinds for the current buffer.
function M.show_help()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = {}

  for _, mode in ipairs({ 'n', 'v' }) do
    local maps = vim.api.nvim_buf_get_keymap(bufnr, mode)
    for _, map in ipairs(maps) do
      if map.desc and map.desc:find('^Himalaya:') then
        local name = map.desc:gsub('^Himalaya: ', '')
        local prefix = mode == 'v' and '(v) ' or '    '
        lines[#lines + 1] = string.format('%s%-8s %s', prefix, map.lhs, name)
      end
    end
  end

  table.sort(lines)

  if #lines == 0 then
    lines = { '  No Himalaya keybinds in this buffer' }
  end

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, #l)
  end
  width = math.min(width + 4, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)

  local win = vim.api.nvim_open_win(float_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Keybinds ',
    title_pos = 'center',
  })

  vim.bo[float_buf].modifiable = false
  vim.bo[float_buf].bufhidden = 'wipe'

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = float_buf })
  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = float_buf })
end

--- Define keybinds shared between flat listing and thread listing.
--- Both modes share compose, account, attachment, copy/move, delete,
--- seen/unseen, and flag add/remove bindings.
--- @param bufnr number
function M.shared_listing_keybinds(bufnr)
  local compose = require('himalaya.domain.email.compose')
  local email = require('himalaya.domain.email')
  local account

  M.define(bufnr, {
    { 'n', 'gw', compose.write, 'email-write' },
    { 'n', 'gr', compose.reply, 'email-reply' },
    { 'n', 'gR', compose.reply_all, 'email-reply-all' },
    { 'n', 'gf', compose.forward, 'email-forward' },
    {
      'n',
      'ga',
      function()
        account = account or require('himalaya.domain.account')
        account.select()
      end,
      'account-select',
    },
    { 'n', 'gA', email.download_attachments, 'email-download-attachments' },
    { 'n', 'gC', email.select_folder_then_copy, 'email-select-folder-then-copy' },
    { 'v', 'gC', M.visual_range(email.select_folder_then_copy), 'email-select-folder-then-copy-visual' },
    { 'n', 'gM', email.select_folder_then_move, 'email-select-folder-then-move' },
    { 'v', 'gM', M.visual_range(email.select_folder_then_move), 'email-select-folder-then-move-visual' },
    { 'n', 'dd', email.delete, 'email-delete' },
    { 'v', 'd', M.visual_range(email.delete), 'email-delete-visual' },
    { 'n', 'gs', email.mark_seen, 'email-mark-seen' },
    { 'v', 'gs', M.visual_range(email.mark_seen), 'email-mark-seen-visual' },
    { 'n', 'gS', email.mark_unseen, 'email-mark-unseen' },
    { 'v', 'gS', M.visual_range(email.mark_unseen), 'email-mark-unseen-visual' },
    { 'n', ']u', email.jump_to_next_unread, 'email-next-unread' },
    { 'n', '[u', email.jump_to_prev_unread, 'email-prev-unread' },
    { 'n', ']r', email.jump_to_next_read, 'email-next-read' },
    { 'n', '[r', email.jump_to_prev_read, 'email-prev-read' },
    { 'n', 'gFa', email.flag_add, 'email-flag-add' },
    { 'v', 'gFa', M.visual_range(email.flag_add), 'email-flag-add-visual' },
    { 'n', 'gFr', email.flag_remove, 'email-flag-remove' },
    { 'v', 'gFr', M.visual_range(email.flag_remove), 'email-flag-remove-visual' },
    {
      'n',
      'gm',
      function()
        require('himalaya.domain.folder').select()
      end,
      'folder-select',
    },
    { 'n', 'go', email.open_browser, 'email-open-browser' },
    { 'n', '?', M.show_help, 'help' },
  })
end

return M
