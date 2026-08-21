--- Panel orchestration — builds a Placement.Spec from the current tabpage
--- and the registry, then applies the placement engine to reserve panels.
---
--- This is the bridge between user config and the placement engine.

--- Raw window item collected during scanning, before key assignment.
---@class Layout.Entity.Panel.RawSlot
---@field winid integer
---@field bufnr integer
---@field vname string
---@field gname string
---@field key? string Per-occurrence key (e.g. "bottom:debug:2") or nil
---@field ve Layout.View.Entry?

---@class Layout.Entity.Panel.Slot : Placement.Slot
---@field _key? string Stable per-occurrence view key.
---@field _vname string View name.
---@field _gname string Group name.

--- Speculative classification for a window whose filter cannot match yet.
--- Keyed by winid; produced by the toggle feature for windows spawned by
--- a view's own `open` command.
---@class Layout.Entity.Panel.PresumedEntry
---@field side Layout.Side
---@field group string
---@field vname string
---@field ve Layout.View.Entry

---@alias Layout.Entity.Panel.Presumed table<integer, Layout.Entity.Panel.PresumedEntry>

local Constants = require('layout.shared.constants')
local placement = require('layout.shared.placement')
local size_model = require('layout.entities.panel.model.size')
local view_entity = require('layout.entities.view')
local view_state = require('layout.shared.view_state')

---@class Layout.Entity.Panel
---@field registry Layout.Registry? Registry reference for the current tabpage, set via `set_registry`.
---@field rail Layout.Feature.Rail? Rail provider included in placement when using buffer mode.
local Panel = {
  registry = nil,
  rail = nil,
}

--- Assign per-occurrence keys to raw slots on a side and return the final
--- sorted slot list with sizes resolved.  Slots are ordered first by the
--- group declaration position and then by the view position within the group.
---@private
---@param side Layout.Side
---@param raw Layout.Entity.Panel.RawSlot[]
---@param order { group: table<string, integer>, view: table<string, integer> }
---@return Layout.Entity.Panel.Slot[]
local function finalize_side_slots(side, raw, order)
  if #raw == 0 then return {} end

  ---@alias RawSlotKeys { with_key: Layout.Entity.Panel.RawSlot[], without_key: Layout.Entity.Panel.RawSlot[] }

  ---@param keys RawSlotKeys
  ---@param item Layout.Entity.Panel.RawSlot
  ---@type RawSlotKeys
  local keys = vim.iter(raw):fold({ with_key = {}, without_key = {} }, function(keys, item)
    local k = item.key and keys.with_key or keys.without_key
    table.insert(k, item)
    return keys
  end)

  ---@param total_counts table<string, integer>
  ---@param item Layout.Entity.Panel.RawSlot
  ---@type table<string, integer>
  local total_counts = vim.iter(raw):fold({}, function(total_counts, item)
    local identity = item.gname .. '\0' .. item.vname
    total_counts[identity] = (total_counts[identity] or 0) + 1
    return total_counts
  end)

  ---@param max_idx table<string, number>
  ---@param item Layout.Entity.Panel.RawSlot
  ---@type table<string, number>
  local max_idx = vim.iter(keys.with_key):fold({}, function(max_idx, item)
    local identity = item.gname .. '\0' .. item.vname
    local idx = item.key:match(':(%d+)$')
    if idx then max_idx[identity] = math.max(max_idx[identity] or 0, tonumber(idx)) end
    return max_idx
  end)

  ---@param item Layout.Entity.Panel.RawSlot
  vim.iter(keys.without_key):each(function(item)
    local identity = item.gname .. '\0' .. item.vname
    local base = side .. ':' .. item.gname .. ':' .. item.vname
    if total_counts[identity] > 1 then
      local n = (max_idx[identity] or 0) + 1
      max_idx[identity] = n
      item.key = base .. ':' .. n
    else
      item.key = base
    end
  end)

  ---@type Layout.Entity.Panel.Slot[]
  local slots = vim
    .iter(raw)
    :map(
      ---@param item Layout.Entity.Panel.RawSlot
      function(item)
        return {
          winid = item.winid,
          bufnr = item.bufnr,
          _key = item.key,
          _vname = item.vname,
          _gname = item.gname,
          size = size_model:get_slot(item.key, item.ve and item.ve.size),
        }
      end
    )
    :totable()

  table.sort(slots, function(a, b)
    local ga = order.group[a._gname or ''] or 9999
    local gb = order.group[b._gname or ''] or 9999
    if ga ~= gb then return ga < gb end
    local va = order.view[(a._gname or '') .. '\0' .. (a._vname or '')] or 9999
    local vb = order.view[(b._gname or '') .. '\0' .. (b._vname or '')] or 9999
    if va ~= vb then return va < vb end
    local na = tonumber(((a._key or ''):match(':(%d+)$'))) or 0
    local nb = tonumber(((b._key or ''):match(':(%d+)$'))) or 0
    return na < nb
  end)

  return slots
end

--- Store the registry reference so features can drive arrangement without
--- carrying their own copy.
---@public
---@param registry Layout.Registry
function Panel:set_registry(registry)
  self.registry = registry
end

---Set the rail provider used to reserve buffer-mode rails during placement.
---@public
---@param rail Layout.Feature.Rail
---@return nil
function Panel:set_rail(rail)
  self.rail = rail
end

---Build and place the current tabpage panel layout.
---@private
---@param registry Layout.Registry
---@param presumed? Layout.Entity.Panel.Presumed
---@return boolean placed Whether managed slots were placed.
local function arrange(registry, presumed)
  local current_wins = vim.api.nvim_tabpage_list_wins(0)

  ---@type table<Layout.Side, Layout.Entity.Panel.RawSlot[]>
  local raw = { left = {}, right = {}, bottom = {} }
  vim.iter(current_wins):each(function(winid)
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative == '' then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local side, gname, vname, ve = view_entity:match_by_buf(bufnr, winid)
      if not side and presumed and presumed[winid] then
        local p = presumed[winid]
        side, gname, vname, ve = p.side, p.group, p.vname, p.ve
      end
      if side then
        local ok, existing_key = pcall(vim.api.nvim_win_get_var, winid, 'layout_view_key')
        local key = (ok and type(existing_key) == 'string' and existing_key) or nil
        table.insert(raw[side], {
          winid = winid,
          bufnr = bufnr,
          vname = vname,
          gname = gname,
          key = key,
          ve = ve,
        })
      end
    end
  end)

  local has_slots = vim.iter(Constants.sides):any(function(side)
    return #raw[side] > 0
  end)
  local rail = Panel.rail and Panel.rail:placement_spec() or nil
  if not has_slots and not rail then return false end

  ---@type table<Layout.Side, { group: table<string, integer>, view: table<string, integer> }>
  local order_maps = {}
  vim.iter(Constants.sides):each(function(side)
    local se = registry[side]
    if se and se._order then
      local group_map = {}
      local view_map = {}
      local gpos = 0
      vim.iter(se._order):each(function(gname)
        gpos = gpos + 1
        group_map[gname] = gpos
        local ge = se.groups[gname]
        if ge and ge._order then
          vim.iter(ge._order):enumerate():each(function(vpos, vname)
            view_map[gname .. '\0' .. vname] = vpos
          end)
        end
      end)
      order_maps[side] = { group = group_map, view = view_map }
    end
  end)

  ---@type table<Layout.Side, Layout.Entity.Panel.Slot[]>
  local side_slots = {}
  vim.iter(Constants.sides):each(function(side)
    side_slots[side] = finalize_side_slots(side, raw[side], order_maps[side] or { group = {}, view = {} })
  end)

  ---@type table<Layout.Side, Placement.Region>
  local regions = {}
  vim.iter(Constants.sides):each(function(side)
    local se = registry[side]
    if se and #side_slots[side] > 0 then
      ---@type Placement.Region
      local region = {
        size = size_model:get(side, se.size),
        slots = side_slots[side],
      }
      if side == 'bottom' and se.align then region.align = se.align end
      regions[side] = region
    end
  end)

  ---@type Placement.Spec
  local spec = {
    center = true,
    rail = rail,
    left = regions.left,
    right = regions.right,
    bottom = regions.bottom,
  }

  placement.place(spec)

  vim.iter(Constants.sides):each(function(side)
    for _, slot in ipairs(side_slots[side]) do
      if slot._key and vim.api.nvim_win_is_valid(slot.winid) then
        pcall(vim.api.nvim_win_set_var, slot.winid, 'layout_view_key', slot._key)
      end
      vim.b[slot.bufnr].layout = {
        side = side,
        group = slot._gname,
        view = slot._vname,
        enabled = true,
      }
    end
  end)

  return true
end

---Scan the current tabpage and transactionally apply its panel layout.
---
---Stable user geometry is captured before placement locks resize observation.
---Successful placement commits expected dimensions; failure always releases
---the lock while preserving dirty topology for a later retry.
---
---@public
---@param registry? Layout.Registry
---@param presumed? Layout.Entity.Panel.Presumed
function Panel:arrange(registry, presumed)
  registry = registry or self.registry
  if vim.fn.getcmdwintype() ~= '' or vim.v.exiting ~= vim.NIL then
    size_model:mark_topology_changed()
    return
  end
  if not registry or not size_model:begin_placement() then return end
  local saved_views = view_state:save()

  local ok, placed = xpcall(function()
    return arrange(registry, presumed)
  end, debug.traceback)
  if not ok then
    size_model:abort_placement()
    view_state:restore(saved_views)
    error(placed)
  end

  if placed then
    size_model:commit_live()
  else
    size_model:settle_topology()
  end
  view_state:restore(saved_views)
end

return Panel
