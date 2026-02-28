local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local folder = require('himalaya.domain.folder')
local probe = require('himalaya.domain.email.probe')
local perf = require('himalaya.perf')
local win = require('himalaya.ui.win')

local M = {}

local ns = vim.api.nvim_create_namespace('himalaya_seen')

--- Extract numeric email ID from a listing line.
--- @param line string
--- @return string
function M.get_email_id_from_line(line)
  return line:match('%d+') or ''
end

--- Compute the effective page size (visible rows) for the current window.
--- Accounts for winbar: if not yet set, reserves one line for it.
--- @return number
function M.effective_page_size()
  local ps = math.max(1, vim.fn.winheight(0))
  if vim.wo.winbar == '' then
    ps = math.max(1, ps - 1)
  end
  return ps
end

--- Define highlight groups for the email listing view.
function M.define_highlights()
  vim.api.nvim_set_hl(0, 'HimalayaSeparator', { default = true, link = 'VertSplit' })
  vim.api.nvim_set_hl(0, 'HimalayaId', { default = true, link = 'Identifier' })
  vim.api.nvim_set_hl(0, 'HimalayaFlags', { default = true, link = 'Special' })
  vim.api.nvim_set_hl(0, 'HimalayaSubject', { default = true, link = 'String' })
  vim.api.nvim_set_hl(0, 'HimalayaSender', { default = true, link = 'Structure' })
  vim.api.nvim_set_hl(0, 'HimalayaDate', { default = true, link = 'Constant' })
  vim.api.nvim_set_hl(0, 'HimalayaHead', { default = true, bold = true, underline = true })
end

local sep = '│'

--- Find all │ (U+2502) separator byte positions in a line.
--- @param line string
--- @return table[] list of {start_byte, end_byte} (0-based start, 0-based exclusive end)
local function find_separators(line)
  local seps = {}
  local start = 1
  while true do
    local s, e = line:find(sep, start, true)
    if not s then
      break
    end
    seps[#seps + 1] = { s - 1, e }
    start = e + 1
  end
  return seps
end

--- Compute the gutter width (number column, fold column, sign column) for a window.
--- @param winid number
--- @param bufnr number
--- @return number
function M.gutter_width(winid, bufnr)
  local wo = vim.wo[winid]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local numberwidth = math.max(wo.numberwidth, #tostring(line_count) + 1)
  local numwidth = (wo.number or wo.relativenumber) and numberwidth or 0
  local foldwidth = tonumber(wo.foldcolumn) or 0

  local signwidth = 0
  if wo.signcolumn == 'yes' then
    signwidth = 2
  elseif wo.signcolumn == 'auto' then
    local placed = vim.fn.sign_getplaced(bufnr)
    signwidth = (placed[1] and #placed[1].signs > 0) and 2 or 0
  end

  return numwidth + foldwidth + signwidth
end

--- Set the header as a sticky winbar at the top of the listing window.
--- @param bufnr number
--- @param header string
function M.apply_header(bufnr, header)
  local winid = win.find_by_bufnr(bufnr)
  if not winid then
    return
  end
  local pad = string.rep(' ', M.gutter_width(winid, bufnr))
  local escaped = header:gsub('%%', '%%%%')
  vim.wo[winid].winbar = '%#HimalayaHead#' .. pad .. escaped
end

local col_groups = { 'HimalayaId', 'HimalayaFlags', 'HimalayaSubject', 'HimalayaSender', 'HimalayaDate' }
local compact_col_groups = { 'HimalayaId', 'HimalayaSubject', 'HimalayaSender', 'HimalayaDate' }

--- Apply per-column extmark highlights to unseen lines; seen/unknown lines
--- receive separator extmarks only (default Normal text).
--- @param bufnr number
--- @param envelopes table[]
--- @param opts? table  Optional: { flags_compacted = boolean }
function M.apply_highlights(bufnr, envelopes, opts)
  perf.start('apply_highlights')
  local compacted = opts and opts.flags_compacted or false
  local expected_seps = compacted and 3 or 4
  local groups = compacted and compact_col_groups or col_groups

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    local row = i - 1
    local seps = find_separators(line)
    if #seps < expected_seps then
      goto continue
    end

    -- Separator extmarks (always applied)
    for _, sp in ipairs(seps) do
      vim.api.nvim_buf_set_extmark(bufnr, ns, row, sp[1], {
        end_col = sp[2],
        hl_group = 'HimalayaSeparator',
        priority = 200,
      })
    end

    -- Column extmarks (only for unseen lines with known flags)
    local env = envelopes[i]
    local flags = env and env.flags
    if flags then
      local seen = false
      for _, f in ipairs(flags) do
        if f == 'Seen' then
          seen = true
          break
        end
      end
      if not seen then
        local ranges = {}
        ranges[1] = { 0, seps[1][1] }
        for s = 1, expected_seps - 1 do
          ranges[#ranges + 1] = { seps[s][2], seps[s + 1][1] }
        end
        ranges[#ranges + 1] = { seps[expected_seps][2], #line }
        for j, range in ipairs(ranges) do
          if range[2] > range[1] then
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, range[1], {
              end_col = range[2],
              hl_group = groups[j],
              priority = 200,
            })
          end
        end
      end
    end

    ::continue::
  end
  perf.stop('apply_highlights')
end

--- Remove column extmarks from a single line, keeping separator extmarks only.
--- Used for optimistic mark-as-seen without a full re-render.
--- @param bufnr number
--- @param line_idx number 0-based line index
function M.mark_line_as_seen(bufnr, line_idx)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { line_idx, 0 }, { line_idx, -1 }, {})
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_del_extmark(bufnr, ns, mark[1])
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
  if #lines == 0 then
    return
  end
  local seps = find_separators(lines[1])
  for _, sp in ipairs(seps) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, sp[1], {
      end_col = sp[2],
      hl_group = 'HimalayaSeparator',
      priority = 200,
    })
  end
end

--- Set up the listing buffer: options, highlights, syntax, and keybinds.
--- @param bufnr number
function M.setup(bufnr)
  vim.bo[bufnr].buftype = 'nofile'
  vim.api.nvim_buf_call(bufnr, function()
    vim.wo.cursorline = true
    vim.wo.wrap = true
    vim.wo.scrolloff = 0
  end)
  vim.bo[bufnr].modifiable = false

  M.define_highlights()

  keybinds.shared_listing_keybinds(bufnr)
  keybinds.define(bufnr, {
    { 'n', '[[', folder.select_previous_page, 'folder-select-previous-page' },
    { 'n', ']]', folder.select_next_page, 'folder-select-next-page' },
    { 'n', '<cr>', email.read, 'email-read' },
    { 'n', 'g/', email.set_list_envelopes_query, 'email-set-list-envelopes-query' },
    { 'n', 'g?', email.apply_search_preset, 'email-search-preset' },
    {
      'n',
      'gt',
      function()
        local id = M.get_email_id_from_line(vim.api.nvim_get_current_line())
        require('himalaya.domain.email.thread_listing').list(nil, { restore_email_id = id })
      end,
      'thread-listing-toggle',
    },
  })

  keybinds.register_which_key_groups(bufnr, {
    { 'gF', 'Flags' },
    { ']', 'Next' },
    { '[', 'Prev' },
  })

  local augroup = vim.api.nvim_create_augroup('HimalayaListing', { clear = true })
  local function on_resize()
    local winid = win.find_by_bufnr(bufnr)
    if winid then
      vim.api.nvim_win_call(winid, function()
        email.resize_listing()
      end)
    end
  end
  vim.api.nvim_create_autocmd('VimResized', {
    group = augroup,
    callback = on_resize,
  })
  vim.api.nvim_create_autocmd('WinResized', {
    group = augroup,
    callback = on_resize,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      require('himalaya.sync').stop()
      email.cleanup()
      probe.cleanup()
    end,
  })

  require('himalaya.sync').start()
end

M.define_highlights()

return M
