--- Save the current workspace state to disk.
---
--- Serializes which groups are open and which views (by filetype) are
--- active within each group, per side.

---@class Layout.Feature.Save
local M = {}

local store = require('layout.shared.store')
local view_entity = require('layout.entities.view')

--- Build a snapshot of the current tabpage's open views.
--- Returns { sides = { left = { [group] = ["ft1", "ft2"] }, ... } }
---@private
---@return table
local function snapshot()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  return vim.iter(wins):fold({ sides = { left = {}, right = {}, bottom = {} } }, function(data, winid)
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local side, group_name, view_name = view_entity:match_by_buf(bufnr, winid)
      if side and group_name and view_name then
        local ft = vim.bo[bufnr].filetype
        if ft and ft ~= '' then
          data.sides[side][group_name] = data.sides[side][group_name] or {}
          table.insert(data.sides[side][group_name], ft)
        end
      end
    end
    return data
  end)
end

--- Save the current workspace for the active cwd.
---@public
---@param config Layout.Config
function M.save(config)
  if not config.workspaces or not config.workspaces.auto_save then return end
  local data = snapshot()
  store.save(config, data)
end

return M
