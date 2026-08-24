--- Save the current workspace state to disk.
---
--- Serializes which groups are open and which configured views are
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
  return vim
    .iter(view_entity:iter_matches())
    :fold({ sides = { left = {}, right = {}, bottom = {} } }, function(data, match)
      data.sides[match.side][match.group] = data.sides[match.side][match.group] or {}
      data.sides[match.side][match.group][match.name] = true
      return data
    end)
end

--- Save the current workspace for the active cwd.
---@public
---@param config Layout.Config
function M.save(config)
  local data = snapshot()
  store.save(config, data)
end

return M
