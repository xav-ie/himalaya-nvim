local keybinds = require('himalaya.keybinds')
local thread_listing = require('himalaya.domain.email.thread_listing')

local M = {}

--- Apply full 5-column syntax (same as flat listing) plus tree connector overlay.
--- Per-column coloring is active; read/unread distinction comes from extmark-based
--- seen highlights applied in render_page after flag enrichment.
--- @param bufnr number
local function apply_syntax(bufnr)
  local listing = require('himalaya.ui.listing')
  listing.apply_syntax(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd([[
      syntax match HimalayaTree /\%u250c\%u2500\|\%u251c\%u2500\|\%u2514\%u2500\|\%u2502 / contained containedin=HimalayaSubject
    ]])
  end)
end

--- Set up the thread listing buffer: options, highlights, syntax, and keybinds.
--- @param bufnr number
function M.setup(bufnr)
  vim.bo[bufnr].buftype = 'nofile'
  vim.api.nvim_buf_call(bufnr, function()
    vim.wo.cursorline = true
    vim.wo.wrap = true
    vim.wo.scrolloff = 0
  end)
  vim.bo[bufnr].modifiable = false

  local listing = require('himalaya.ui.listing')
  listing.define_highlights()
  vim.api.nvim_set_hl(0, 'HimalayaTree', { default = true, link = 'Comment' })

  apply_syntax(bufnr)

  keybinds.shared_listing_keybinds(bufnr)
  keybinds.define(bufnr, {
    { 'n', '<cr>', thread_listing.read,              'thread-email-read' },
    { 'n', 'gp',   thread_listing.previous_page,     'thread-previous-page' },
    { 'n', 'gn',   thread_listing.next_page,          'thread-next-page' },
    { 'n', 'g/',   thread_listing.set_thread_query,   'thread-search' },
    { 'n', 'gt',   thread_listing.toggle_to_flat,     'thread-toggle-flat' },
    { 'n', 'gT',   thread_listing.toggle_reverse,     'thread-toggle-reverse' },
  })

  local augroup = vim.api.nvim_create_augroup('HimalayaThreadListing', { clear = true })
  local function on_resize()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
        vim.api.nvim_win_call(winid, function()
          thread_listing.resize()
        end)
        break
      end
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
end

return M
