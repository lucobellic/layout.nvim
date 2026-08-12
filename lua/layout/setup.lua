--- Plugins setup orchestration: merge config, normalize, register views,
--- wire commands and autocmds.
---
--- Called by `init.lua` via `require("layout").setup(opts)`.

---@class Layout.Setup
local M = {}

local Autocmds = require('layout.autocmds')
local Commands = require('layout.commands')
local Config = require('layout.shared.config')
local Group = require('layout.entities.group')
local Panel = require('layout.entities.panel')
local Rail = require('layout.features.rail')
local Restore = require('layout.features.restore')
local Statusline = require('layout.features.statusline')
local Ui = require('layout.shared.ui')
local View = require('layout.entities.view')
local ViewState = require('layout.shared.view_state')

---@public
---@param opts? table
---@return Layout.Registry
function M.setup(opts)
  local resolved = Config.merge(opts)
  local registry = Config.normalize(resolved)

  -- Allow windows to shrink to zero so user-initiated center splits and
  -- closes do not push panel windows out of their declared size.  With the
  -- default winminheight=1 / winminwidth=1, Neovim refuses to shrink the
  -- center frame below one row/column and instead grows it, eating into
  -- panel space (the bottom panel in particular) even though panel
  -- windows carry winfixwidth/winfixheight.
  vim.o.winminheight = 0
  vim.o.winminwidth = 0

  View:register(registry)
  Group:register(registry)
  Panel:set_registry(registry)
  Panel:set_rail(Rail)
  ViewState:setup()

  if resolved.statusline then
    Statusline:setup(registry, resolved.statusline)
    local counts = {}
    for _, side in ipairs({ 'left', 'right', 'bottom' }) do
      counts[side] = #Group:list(side)
    end
    Ui:setup(counts, resolved.statusline.colors)
    Rail:setup(resolved.statusline.rail, resolved.statusline.clickable)
  else
    Rail:setup({ enabled = false, mode = 'float', position = 'left', width = 1, padding = 0, groups = {} }, false)
  end

  Autocmds:setup(registry, resolved)
  Commands:setup(resolved)

  if resolved.workspaces and resolved.workspaces.auto_restore then
    vim.schedule(function()
      Restore.restore(resolved)
    end)
  end

  return registry
end

return M
