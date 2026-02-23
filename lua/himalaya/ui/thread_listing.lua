local keybinds = require('himalaya.keybinds')
local thread_listing = require('himalaya.domain.email.thread_listing')
local win = require('himalaya.ui.win')

local M = {}

--- Set up the thread listing buffer: options, highlights, and keybinds.
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

  keybinds.shared_listing_keybinds(bufnr)
  keybinds.define(bufnr, {
    { 'n', '<cr>', thread_listing.read, 'thread-email-read' },
    { 'n', '[[', thread_listing.previous_page, 'thread-previous-page' },
    { 'n', ']]', thread_listing.next_page, 'thread-next-page' },
    { 'n', 'g/', thread_listing.set_thread_query, 'thread-search' },
    { 'n', 'g?', thread_listing.apply_search_preset, 'thread-search-preset' },
    { 'n', 'gt', thread_listing.toggle_to_flat, 'thread-toggle-flat' },
    { 'n', 'gT', thread_listing.toggle_reverse, 'thread-toggle-reverse' },
  })

  local augroup = vim.api.nvim_create_augroup('HimalayaThreadListing', { clear = true })
  local function on_resize()
    local winid = win.find_by_bufnr(bufnr)
    if winid then
      vim.api.nvim_win_call(winid, function()
        thread_listing.resize()
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
      thread_listing.cleanup()
      require('himalaya.domain.email.probe').cleanup()
    end,
  })

  require('himalaya.sync').start()
end

return M
