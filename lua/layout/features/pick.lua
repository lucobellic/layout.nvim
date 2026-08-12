--- Group picker — toggle a group with side exclusivity.
---
--- pick(side, group_name): toggle a specific group.
--- prompt(refresh?): show available group keys, wait for key press, toggle.
---
--- prompt() activates pick mode on the statusline module before waiting
--- so that group keys are rendered next to icons during the pick gesture.

local Toggle = require('layout.features.toggle')
local Workspace = require('layout.entities.workspace')
local Group = require('layout.entities.group')
local Statusline = require('layout.features.statusline')
local Rail = require('layout.features.rail')

---@class Layout.Feature.Pick
local Pick = {}

---@class Layout.Feature.Pick.Group
---@field side Layout.Side
---@field name string

--- Toggle a group with side exclusivity.
--- When opening, closes all other open groups on the same side first.
---@public
---@param side Layout.Side
---@param group_name string
function Pick.pick(side, group_name)
  if Workspace:is_open(side, group_name) then
    local closed = Toggle.close_group(side, group_name)
    if closed then return end
  end
  Toggle.close_panel(side)
  Toggle.open_group(side, group_name)
end

--- Toggle all groups assigned to the same picker key as one operation.
--- Opening retains side exclusivity; closing always includes every match.
---@private
---@param groups Layout.Feature.Pick.Group[]
local function pick_groups(groups)
  local any_open = vim.iter(groups):any(function(group)
    return Workspace:is_open(group.side, group.name)
  end)
  if any_open then
    vim.iter(groups):each(function(group)
      Toggle.close_group(group.side, group.name)
    end)
    return
  end

  local closed_sides = {}
  vim.iter(groups):each(function(group)
    if not closed_sides[group.side] then
      Toggle.close_panel(group.side)
      closed_sides[group.side] = true
    end
  end)
  vim.iter(groups):each(function(group)
    Toggle.open_group(group.side, group.name)
  end)
end

--- Enable pick mode on the statusline, redraw, then wait for a key press.
--- Disables pick mode and redraws again before toggling the matching group.
---
--- When pick mode is active, statusline icons include their group key so
--- the user sees which key to press for each group.
---
--- Optionally accepts a refresh callback invoked before each redraw, useful
--- for external statusline plugins (e.g. require('lualine').refresh()).
---@public
---@param refresh? fun()
function Pick.prompt(refresh)
  ---@type table<string, Layout.Feature.Pick.Group[]>
  local keymap = {}
  for side, gname, gdesc in Group:iter() do
    if gdesc.key and gdesc.key ~= '' then
      keymap[gdesc.key] = keymap[gdesc.key] or {}
      table.insert(keymap[gdesc.key], { side = side, name = gname })
    end
  end

  Statusline.pick_mode = true
  Rail:render()
  if refresh then pcall(refresh) end
  vim.schedule(function()
    vim.cmd.redrawtabline()
    vim.cmd.redrawstatus()
  end)

  local char = vim.fn.getcharstr()

  Statusline.pick_mode = false
  Rail:render()
  if refresh then pcall(refresh) end
  vim.schedule(function()
    vim.cmd.redrawtabline()
    vim.cmd.redrawstatus()
  end)

  if char == '\27' then return end

  local groups = keymap[char]
  if groups then
    if #groups == 1 then
      Pick.pick(groups[1].side, groups[1].name)
    else
      pick_groups(groups)
    end
  else
    vim.notify('[layout.nvim] No group found for key: ' .. char, vim.log.levels.WARN)
  end
end

return Pick
