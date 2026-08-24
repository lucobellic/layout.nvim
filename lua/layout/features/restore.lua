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
--- Replaces configured groups with their previously saved views.
---@public
---@param config Layout.Config
---@param clear_missing? boolean Close configured groups when no snapshot exists.
function Restore.restore(config, clear_missing)
  local state = Store.load(config)
  if not state then
    if clear_missing then
      vim.iter(Constants.sides):each(function(side)
        Toggle.close_panel(side)
      end)
    end
    return
  end

  vim.iter(Constants.sides):each(function(side)
    local saved = state.sides[side] or {}
    for _, gname in ipairs(Group:list(side)) do
      Toggle.close_group(side, gname)
      local group_state = saved[gname]
      if group_state then
        local selected = nil
        if type(group_state) == 'table' then
          selected = {}
          for key, value in pairs(group_state) do
            if type(key) == 'string' and value == true then selected[key] = true end
            if type(key) == 'number' and type(value) == 'string' then selected[value] = true end
          end
        end
        Toggle.open_group(side, gname, selected)
      end
    end
  end)
end

return Restore
