--- Restore workspace state from disk.
---
--- Reads the saved state for the current cwd and replays the open
--- sequence by invoking each view's `open`.

---@class Layout.Feature.Restore
local Restore = {}

local Store = require('layout.shared.store')
local Toggle = require('layout.features.toggle')
local Group = require('layout.entities.group')
local Constants = require('layout.shared.constants')

--- Restore workspace state from disk.
--- Reopens groups that were previously open.
---@public
---@param config Layout.Config
function Restore.restore(config)
  local state = Store.load(config)
  if not state or not state.sides then return end

  vim.iter(Constants.sides):each(function(side)
    local saved = state.sides[side] or {}
    for _, gname in ipairs(Group:list(side)) do
      if saved[gname] then
        Toggle.open_group(side, gname)
      end
    end
  end)
end

return Restore
