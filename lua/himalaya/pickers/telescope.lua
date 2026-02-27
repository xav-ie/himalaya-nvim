local config = require('himalaya.config')

local M = {}

function M.select(callback, folders)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  local sorters = require('telescope.sorters')
  local previewers = require('telescope.previewers')

  local cfg = config.get()
  local previewer = nil

  local finder_opts = {
    results = folders,
    entry_maker = function(entry)
      return {
        value = entry.name,
        display = entry.name,
        ordinal = entry.name,
      }
    end,
  }

  if cfg.telescope_preview then
    previewer = previewers.display_content.new({})
    finder_opts.entry_maker = function(entry)
      return {
        value = entry.name,
        display = entry.name,
        ordinal = entry.name,
        preview_command = function(e, bufnr)
          vim.api.nvim_buf_call(bufnr, function()
            local account_mod = require('himalaya.state.account')
            local email_mod = require('himalaya.domain.email')
            local account = account_mod.default()
            local ok, output = pcall(email_mod.list_with, account, e.value, 1, '')
            if not ok then
              vim.cmd('redraw')
              vim.bo.modifiable = true
              local errors = vim.split(tostring(output), '\n')
              errors[1] = 'Errors: ' .. errors[1]
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, errors)
            end
          end)
        end,
      }
    end
  end

  pickers
    .new({}, {
      results_title = 'Folders',
      finder = finders.new_table(finder_opts),
      sorter = sorters.get_generic_fuzzy_sorter(),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          callback(selection.display)
        end)
        return true
      end,
      previewer = previewer,
    })
    :find()
end

return M
