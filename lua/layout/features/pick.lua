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

---@class Layout.Feature.Pick
local Pick = {}

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
  local keymap = {}
  for side, gname, gdesc in Group:iter() do
    if gdesc.key and gdesc.key ~= '' then keymap[gdesc.key] = { side = side, name = gname } end
  end

  Statusline.pick_mode = true
  if refresh then pcall(refresh) end
  vim.schedule(function()
    vim.cmd.redrawtabline()
    vim.cmd.redrawstatus()
  end)

  local char = vim.fn.getcharstr()

  Statusline.pick_mode = false
  if refresh then pcall(refresh) end
  vim.schedule(function()
    vim.cmd.redrawtabline()
    vim.cmd.redrawstatus()
  end)

  local group = keymap[char]
  if group then
    Pick.pick(group.side, group.name)
  else
    vim.notify('[layout.nvim] No group found for key: ' .. char, vim.log.levels.WARN)
  end
end

return Pick
