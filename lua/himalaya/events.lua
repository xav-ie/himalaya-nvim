local log = require('himalaya.log')

local M = {}

--- Complete list of events emitted by the plugin.
--- Each entry: { name, payload = { field, ... }, note? }
M.catalog = {
  { name = 'EmailsListed', payload = { 'account', 'folder', 'page', 'count' } },
  { name = 'EmailRead', payload = { 'account', 'folder', 'email_id', 'bufnr' } },
  { name = 'EmailDeleted', payload = { 'account', 'folder', 'ids' } },
  { name = 'EmailCopied', payload = { 'account', 'folder', 'ids', 'target_folder' } },
  { name = 'EmailMoved', payload = { 'account', 'folder', 'ids', 'target_folder' } },
  { name = 'EmailFlagAdded', payload = { 'account', 'folder', 'ids', 'flag' } },
  { name = 'EmailFlagRemoved', payload = { 'account', 'folder', 'ids', 'flag' } },
  { name = 'EmailMarkedSeen', payload = { 'account', 'folder', 'ids' } },
  { name = 'EmailMarkedUnseen', payload = { 'account', 'folder', 'ids' } },
  {
    name = 'ComposeOpened',
    payload = { 'account', 'folder', 'mode', 'bufnr' },
    note = 'mode: `write`, `reply`, `reply_all`, `forward`',
  },
  { name = 'EmailSent', payload = { 'account', 'folder', 'reply_id' } },
  { name = 'DraftSaved', payload = { 'account' } },
  { name = 'FolderChanged', payload = { 'account', 'folder' } },
  {
    name = 'NewMail',
    payload = { 'account', 'folder', 'count', 'new_ids' },
    note = 'fired by background sync',
  },
}

local registered = {}
for _, e in ipairs(M.catalog) do
  registered[e.name] = true
end

local listeners = {}
local next_id = 1

--- Register a listener for an event.
--- @param event string
--- @param fn function
--- @return number id
function M.on(event, fn)
  if not listeners[event] then
    listeners[event] = {}
  end
  local id = next_id
  next_id = next_id + 1
  table.insert(listeners[event], { id = id, fn = fn, once = false })
  return id
end

--- Register a one-shot listener for an event.
--- @param event string
--- @param fn function
--- @return number id
function M.once(event, fn)
  if not listeners[event] then
    listeners[event] = {}
  end
  local id = next_id
  next_id = next_id + 1
  table.insert(listeners[event], { id = id, fn = fn, once = true })
  return id
end

--- Unsubscribe a listener by id.
--- @param id number
function M.off(id)
  for event, subs in pairs(listeners) do
    for i, sub in ipairs(subs) do
      if sub.id == id then
        table.remove(subs, i)
        if #subs == 0 then
          listeners[event] = nil
        end
        return
      end
    end
  end
end

--- Fire an event. No-op when there are no listeners (zero overhead).
--- Each listener is pcall-wrapped; errors are logged without aborting others.
--- @param event string
--- @param data? table
function M.emit(event, data)
  assert(registered[event], '[himalaya.events] unregistered event: ' .. event)
  local subs = listeners[event]
  if not subs then
    return
  end
  -- Iterate forward for natural call order; collect once-indices to remove after.
  local remove = {}
  for i, sub in ipairs(subs) do
    local ok, err = pcall(sub.fn, data)
    if not ok then
      log.warn(string.format('[himalaya.events] %s listener error: %s', event, tostring(err)))
    end
    if sub.once then
      remove[#remove + 1] = i
    end
  end
  -- Remove in reverse so indices stay valid.
  for j = #remove, 1, -1 do
    table.remove(subs, remove[j])
  end
  if #subs == 0 then
    listeners[event] = nil
  end
end

--- Return the number of listeners for an event.
--- @param event string
--- @return number
function M.count(event)
  local subs = listeners[event]
  return subs and #subs or 0
end

--- Clear all state. For test isolation.
function M._reset()
  listeners = {}
  next_id = 1
end

return M
