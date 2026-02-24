local M = {}

--- Resolve account and folder for the current buffer context.
--- Reads vim.b.* from the given buffer, falls back to the listing
--- buffer in the current tab, then to defaults.
--- @param bufnr? number
--- @return string account
--- @return string folder
function M.resolve(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local account = vim.b[bufnr].himalaya_account
  local folder = vim.b[bufnr].himalaya_folder
  if account and folder then
    return account, folder
  end
  local win = require('himalaya.ui.win')
  local _, listing_bufnr = win.find_by_buftype({ 'listing', 'thread-listing' })
  if listing_bufnr then
    account = account or vim.b[listing_bufnr].himalaya_account
    folder = folder or vim.b[listing_bufnr].himalaya_folder
  end
  return account or '', folder or 'INBOX'
end

--- Stamp a buffer with account and folder context.
--- @param bufnr number
--- @param account string
--- @param folder string
function M.stamp(bufnr, account, folder)
  vim.b[bufnr].himalaya_account = account
  vim.b[bufnr].himalaya_folder = folder
end

return M
