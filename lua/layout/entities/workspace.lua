--- Workspace state — tracks which groups are currently open per side.
---
--- Provides the in-memory open/closed state (per tabpage) and serialization
--- helpers for persistence (consumed by features/save and features/restore).

---@class Layout.Entity.Workspace
---@field private state table<Layout.Side, table<string, boolean>> Open/closed state per side and group name
local Workspace = {
  state = {},
}

local View = require('layout.entities.view')

--- Ensure the current tabpage has a state entry.
---@package
---@return table<Layout.Side, table<string, boolean>>
function Workspace:ensure_tab()
  local t = vim.api.nvim_get_current_tabpage()
  if not self.state[t] then self.state[t] = { left = {}, right = {}, bottom = {} } end
  return self.state[t]
end

--- Reset workspace state (all tabpages).
---@package
function Workspace:clear()
  self.state = {}
end

--- Mark a group as open on a side in the current tabpage.
---@public
---@param side Layout.Side
---@param group_name string
function Workspace:mark_open(side, group_name)
  local st = self:ensure_tab()
  if not st[side] then st[side] = {} end
  st[side][group_name] = true
end

--- Mark a group as closed on a side in the current tabpage.
---@public
---@param side Layout.Side
---@param group_name string
function Workspace:mark_closed(side, group_name)
  local st = self:ensure_tab()
  if st and st[side] then st[side][group_name] = nil end
end

--- Check whether a group is currently open in the current tabpage.
---@public
---@param side Layout.Side
---@param group_name string
---@return boolean
function Workspace:is_open(side, group_name)
  for match in View:iter_matches() do
    if match.side == side and match.group == group_name then return true end
  end
  local st = self:ensure_tab()
  return st ~= nil and st[side] ~= nil and st[side][group_name] == true
end

--- List open group names on a side in the current tabpage.
---@public
---@param side Layout.Side
---@return string[]
function Workspace:open_groups(side)
  local st = self:ensure_tab()
  if not st or not st[side] then return {} end
  return vim.tbl_keys(st[side])
end

--- Serialize current tabpage state to a plain table (for JSON persistence).
---@public
---@return table<Layout.Side, table<string, boolean>>
function Workspace:to_table()
  local st = self:ensure_tab()
  return vim.deepcopy(st)
end

--- Restore state from a serialized table into the current tabpage.
---@public
---@param tbl table<Layout.Side, table<string, boolean>>
function Workspace:from_table(tbl)
  self.state[vim.api.nvim_get_current_tabpage()] = vim.deepcopy(tbl)
end

return Workspace
