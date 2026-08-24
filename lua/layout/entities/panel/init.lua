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

---@class Layout.Entity.Panel.Order
---@field group table<string, integer>
---@field view table<string, integer>

---@class Layout.Entity.Panel.RawSlotKeys
---@field with_key Layout.Entity.Panel.RawSlot[]
---@field without_key Layout.Entity.Panel.RawSlot[]

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

---Separate slots with persisted keys from slots that still need assignment.
---@param raw Layout.Entity.Panel.RawSlot[]
---@return Layout.Entity.Panel.RawSlotKeys
local function partition_slot_keys(raw)
  return vim.iter(raw):fold({ with_key = {}, without_key = {} }, function(keys, item)
    local destination = item.key and keys.with_key or keys.without_key
    destination[#destination + 1] = item
    return keys
  end)
end

---Count windows sharing each group and view identity.
---@param raw Layout.Entity.Panel.RawSlot[]
---@return table<string, integer>
local function count_slot_identities(raw)
  return vim.iter(raw):fold({}, function(counts, item)
    local identity = item.gname .. '\0' .. item.vname
    counts[identity] = (counts[identity] or 0) + 1
    return counts
  end)
end

---Find the highest persisted occurrence index for each view identity.
---@param slots Layout.Entity.Panel.RawSlot[]
---@return table<string, integer>
local function indexed_slot_maxima(slots)
  return vim.iter(slots):fold({}, function(maxima, item)
    local identity = item.gname .. '\0' .. item.vname
    local index = item.key and item.key:match(':(%d+)$') or nil
    if index then maxima[identity] = math.max(maxima[identity] or 0, tonumber(index)) end
    return maxima
  end)
end

---Assign stable keys to slots that do not already have one.
---@param side Layout.Side
---@param slots Layout.Entity.Panel.RawSlot[]
---@param counts table<string, integer>
---@param maxima table<string, integer>
---@return nil
local function assign_slot_keys(side, slots, counts, maxima)
  for _, item in ipairs(slots) do
    local identity = item.gname .. '\0' .. item.vname
    local base = side .. ':' .. item.gname .. ':' .. item.vname
    if counts[identity] > 1 then
      local index = (maxima[identity] or 0) + 1
      maxima[identity] = index
      item.key = base .. ':' .. index
    else
      item.key = base
    end
  end
end

---Convert scanned windows into placement slots with resolved sizes.
---@param raw Layout.Entity.Panel.RawSlot[]
---@return Layout.Entity.Panel.Slot[]
local function materialize_slots(raw)
  return vim
    .iter(raw)
    :map(function(item)
      return {
        winid = item.winid,
        bufnr = item.bufnr,
        _key = item.key,
        _vname = item.vname,
        _gname = item.gname,
        size = size_model:get_slot(item.key, item.ve and item.ve.size),
      }
    end)
    :totable()
end

---Build a comparator that follows configured group and view order.
---@param order Layout.Entity.Panel.Order
---@return fun(left: Layout.Entity.Panel.Slot, right: Layout.Entity.Panel.Slot): boolean
local function slot_comparator(order)
  return function(left, right)
    local left_group = order.group[left._gname or ''] or 9999
    local right_group = order.group[right._gname or ''] or 9999
    if left_group ~= right_group then return left_group < right_group end
    local left_view = order.view[(left._gname or '') .. '\0' .. (left._vname or '')] or 9999
    local right_view = order.view[(right._gname or '') .. '\0' .. (right._vname or '')] or 9999
    if left_view ~= right_view then return left_view < right_view end
    local left_index = tonumber(((left._key or ''):match(':(%d+)$'))) or 0
    local right_index = tonumber(((right._key or ''):match(':(%d+)$'))) or 0
    return left_index < right_index
  end
end

--- Assign per-occurrence keys to raw slots on a side and return the final
--- sorted slot list with sizes resolved.  Slots are ordered first by the
--- group declaration position and then by the view position within the group.
---@private
---@param side Layout.Side
---@param raw Layout.Entity.Panel.RawSlot[]
---@param order Layout.Entity.Panel.Order
---@return Layout.Entity.Panel.Slot[]
local function finalize_side_slots(side, raw, order)
  if #raw == 0 then return {} end
  local keys = partition_slot_keys(raw)
  local counts = count_slot_identities(raw)
  local maxima = indexed_slot_maxima(keys.with_key)
  assign_slot_keys(side, keys.without_key, counts, maxima)
  local slots = materialize_slots(raw)
  table.sort(slots, slot_comparator(order))
  return slots
end

---Classify normal tabpage windows into raw panel slots.
---@param wins integer[]
---@param presumed? Layout.Entity.Panel.Presumed
---@return table<Layout.Side, Layout.Entity.Panel.RawSlot[]>
local function collect_raw_slots(wins, presumed)
  local raw = { left = {}, right = {}, bottom = {} }
  for _, winid in ipairs(wins) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative == '' then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local side, gname, vname, ve = view_entity:match_by_buf(bufnr, winid)
      if not side and presumed and presumed[winid] then
        local entry = presumed[winid]
        side, gname, vname, ve = entry.side, entry.group, entry.vname, entry.ve
      end
      if side then
        local ok, existing_key = pcall(vim.api.nvim_win_get_var, winid, 'layout_view_key')
        raw[side][#raw[side] + 1] = {
          winid = winid,
          bufnr = bufnr,
          vname = vname,
          gname = gname,
          key = ok and type(existing_key) == 'string' and existing_key or nil,
          ve = ve,
        }
      end
    end
  end
  return raw
end

---Build configured group and view position maps for each side.
---@param registry Layout.Registry
---@return table<Layout.Side, Layout.Entity.Panel.Order>
local function build_order_maps(registry)
  local maps = {}
  for _, side in ipairs(Constants.sides) do
    local side_entry = registry[side]
    if side_entry and side_entry._order then
      local order = { group = {}, view = {} }
      for group_position, group_name in ipairs(side_entry._order) do
        order.group[group_name] = group_position
        local group_entry = side_entry.groups[group_name]
        for view_position, view_name in ipairs(group_entry and group_entry._order or {}) do
          order.view[group_name .. '\0' .. view_name] = view_position
        end
      end
      maps[side] = order
    end
  end
  return maps
end

---Finalize scanned slots for every panel side.
---@param raw table<Layout.Side, Layout.Entity.Panel.RawSlot[]>
---@param order_maps table<Layout.Side, Layout.Entity.Panel.Order>
---@return table<Layout.Side, Layout.Entity.Panel.Slot[]>
local function build_side_slots(raw, order_maps)
  local slots = {}
  for _, side in ipairs(Constants.sides) do
    slots[side] = finalize_side_slots(side, raw[side], order_maps[side] or { group = {}, view = {} })
  end
  return slots
end

---Build placement regions from configured panel sizes and active slots.
---@param registry Layout.Registry
---Persist stable keys and public buffer metadata after placement.
---@param side_slots table<Layout.Side, Layout.Entity.Panel.Slot[]>
---@return table<Layout.Side, Placement.Region>
local function build_regions(registry, side_slots)
  local regions = {}
  for _, side in ipairs(Constants.sides) do
    local side_entry = registry[side]
    if side_entry and #side_slots[side] > 0 then
      local region = { size = size_model:get(side, side_entry.size), slots = side_slots[side] }
      if side == 'bottom' and side_entry.align then region.align = side_entry.align end
      regions[side] = region
    end
  end
  return regions
end

---@param side_slots table<Layout.Side, Layout.Entity.Panel.Slot[]>
---@return nil
local function record_slot_metadata(side_slots)
  for _, side in ipairs(Constants.sides) do
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
  end
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
  local raw = collect_raw_slots(current_wins, presumed)

  local has_slots = vim.iter(Constants.sides):any(function(side)
    return #raw[side] > 0
  end)
  local rail = Panel.rail and Panel.rail:placement_spec() or nil
  if not has_slots and not rail then return false end

  local side_slots = build_side_slots(raw, build_order_maps(registry))
  local regions = build_regions(registry, side_slots)

  ---@type Placement.Spec
  local spec = {
    rail = rail,
    left = regions.left,
    right = regions.right,
    bottom = regions.bottom,
  }

  placement.place(spec)
  record_slot_metadata(side_slots)

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
---@return nil
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
