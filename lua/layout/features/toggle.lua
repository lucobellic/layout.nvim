--- features/toggle.lua
--- Toggle a group or panel — open or close tool windows.
---
--- `toggle_group(side, group_name)`: if open → close; if closed → open.
--- `toggle_panel(side)`: toggle all groups on a side.

local Group = require('layout.entities.group')
local Panel = require('layout.entities.panel')
local View = require('layout.entities.view')
local ViewState = require('layout.shared.view_state')
local Workspace = require('layout.entities.workspace')

---@class Layout.Feature.Toggle
local Toggle = {}

--- Run the open command/function for a view.
---@private
---@param view Layout.View.Entry
local function run_open(view)
  local open = view.open
  if not open then return end
  if type(open) == 'function' then
    pcall(open)
  elseif type(open) == 'string' then
    pcall(vim.cmd, open)
  end
end

--- Collect the non-floating windows created by `fn` by diffing the
--- tabpage window list around the call.
---@private
---@param fn fun()
---@return integer[] created winids
local function windows_created_by(fn)
  local before = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    before[winid] = true
  end
  fn()
  local created = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if
      not before[winid]
      and vim.api.nvim_win_is_valid(winid)
      and vim.api.nvim_win_get_config(winid).relative == ''
    then
      created[#created + 1] = winid
    end
  end
  return created
end

--- Maximum scheduled arrange attempts before yielding to the
--- event-driven debounced arrangement.
---@private
local ARRANGE_MAX_ATTEMPTS = 6

--- Trigger placement immediately after opening, then keep re-applying on
--- scheduled ticks until all `expected` view names are classified by their
--- filter (i.e. their buffers are detected) — or the attempt budget runs
--- out.  Tool plugins commonly defer `filetype` setting with
---`vim.schedule`, so the first pass cannot recognise the freshly opened
--- windows and they remain stacked in their default split position.
--- Re-running on the next event-loop ticks collapses the
--- open→detect→arrange sequence into a single visual update, removing the
--- brief "stacked then arranged" flicker.
---
--- The `presumed` map speculatively classifies windows spawned by the
--- view's own `open` command, so the first synchronous pass can place
--- them before any redraw even when the filter cannot match yet (e.g.
--- the tool plugin defers setting `filetype`).  It is consumed by the
--- first pass only — later passes rely on the authoritative filter.
---@private
---@param expected? table<string, boolean>  view names to wait for
---@param presumed? Layout.Entity.Panel.Presumed
local function arrange_now(expected, presumed)
  local attempts = 0
  local function converged()
    if not expected then return true end
    local found = {}
    for match in View:iter_matches() do
      if expected[match.name] then found[match.name] = true end
    end
    for name in pairs(expected) do
      if not found[name] then return false end
    end
    return true
  end
  local function step()
    Panel:arrange(nil, presumed)
    presumed = nil
    attempts = attempts + 1
    if attempts < ARRANGE_MAX_ATTEMPTS and not converged() then
      vim.schedule(step)
    end
  end
  step()
end

--- Close tool windows that belong to a specific group.
---@private
---@param side Layout.Side
---@param group_name string
---@return boolean closed_any
local function close_wins(side, group_name)
  return vim.iter(View:iter_matches()):fold(false, function(closed, match)
    if match.side == side and match.group == group_name then
      local ok = pcall(vim.api.nvim_win_close, match.winid, true)
      closed = closed or ok
    end
    return closed
  end)
end

--- Open all views in a group by running their `open` command.
---@public
---@param side Layout.Side
---@param group_name string
function Toggle.open_group(side, group_name)
  local gdesc = Group:get(side, group_name)
  if not gdesc then return end
  ViewState:save()
  local views = Group:views_ordered(side, group_name)
  ---@type Layout.Entity.Panel.Presumed
  local presumed = {}
  vim.iter(views):each(function(v)
    local created = windows_created_by(function()
      run_open(v.view)
    end)
    for _, winid in ipairs(created) do
      presumed[winid] = { side = side, group = group_name, vname = v.name, ve = v.view }
    end
  end)
  Workspace:mark_open(side, group_name)
  local expected = {}
  vim.iter(views):each(function(v)
    expected[v.name] = true
  end)
  arrange_now(expected, presumed)
end

--- Close a group: close all tool windows belonging to it.
---@public
---@param side Layout.Side
---@param group_name string
---@return boolean closed_any
function Toggle.close_group(side, group_name)
  local closed = close_wins(side, group_name)
  Workspace:mark_closed(side, group_name)
  return closed
end

--- Toggle a group: open if closed, close if open.
---@public
---@param side Layout.Side
---@param group_name string
function Toggle.toggle_group(side, group_name)
  if Workspace:is_open(side, group_name) then
    local closed = Toggle.close_group(side, group_name)
    if closed then return end
  end
  Toggle.open_group(side, group_name)
end

--- Close all groups on a side.
---@public
---@param side Layout.Side
function Toggle.close_panel(side)
  vim.iter(Group:list(side)):each(function(gname)
    close_wins(side, gname)
    Workspace:mark_closed(side, gname)
  end)
end

--- Open all groups on a side.
---@public
---@param side Layout.Side
function Toggle.open_panel(side)
  vim.iter(Group:list(side)):each(function(gname)
    Toggle.open_group(side, gname)
  end)
end

return Toggle
