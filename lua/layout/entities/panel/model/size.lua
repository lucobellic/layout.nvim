--- Panel size preferences and placement runtime state.
---
--- Preferred sizes are shared across tabpages. Applied geometry, topology,
--- and placement transaction state are tab-local so events in one tab cannot
--- be mistaken for user resizing in another.

---@class Layout.Panel.Model.Size.Runtime
---@field applied table<Layout.Side, integer?> Dimensions committed by the last successful placement.
---@field applied_slots table<string, integer?> Stacking dimensions committed for managed views.
---@field placed_windows table<integer, boolean>? Normal-window set committed by the last successful placement.
---@field topology_dirty boolean Whether window lifecycle changes require placement.
---@field editor_resized boolean Whether editor dimensions changed before relative sizes were reapplied.
---@field capture_invalid boolean Whether failed placement geometry must not be captured.
---@field placing boolean Whether a placement transaction is active.

---@alias Layout.Panel.Model.Size.Observation
---| '"captured"' # A managed panel changed and its preference was updated.
---| '"expected"' # Managed panel geometry matches the last placement.
---| '"unrelated"' # No managed panel was reported as resized.
---| '"topology"' # Capture is unsafe because normal-window topology changed.
---| '"ignored"' # Capture is locked by placement or editor resizing.

---@class Layout.Panel.Model.Size
---@field private sizes table<Layout.Side, Layout.Size?> Shared tracked panel preferences.
---@field private configured table<Layout.Side, Layout.Size?> Configured fallback used to preserve absolute/relative mode.
---@field private slot_sizes table<string, Layout.Size?> Shared tracked view preferences.
---@field private configured_slots table<string, Layout.Size?> Configured view sizes used to preserve absolute/relative mode.
---@field private runtime table<integer, Layout.Panel.Model.Size.Runtime> Runtime state keyed by tabpage handle.
local Size = {
  sizes = {},
  configured = {},
  slot_sizes = {},
  configured_slots = {},
  runtime = {},
}

local SharedSize = require('layout.shared.size')
local Windows = require('layout.shared.windows')

---@param tabpage? integer
---@return integer
local function tab_id(tabpage)
  return tabpage or vim.api.nvim_get_current_tabpage()
end

---@param tabpage? integer
---@return Layout.Panel.Model.Size.Runtime
local function runtime_for(tabpage)
  local id = tab_id(tabpage)
  if not Size.runtime[id] then
    Size.runtime[id] = {
      applied = {},
      applied_slots = {},
      placed_windows = nil,
      topology_dirty = false,
      editor_resized = false,
      capture_invalid = false,
      placing = false,
    }
  end
  return Size.runtime[id]
end

---@param win integer
---@return string?
local function slot_key_of(win)
  local ok, key = pcall(vim.api.nvim_win_get_var, win, 'layout_view_key')
  if not ok or type(key) ~= 'string' then return nil end
  return key
end

---@param win integer
---@return Layout.Side?
local function side_of(win)
  local ok, slot = pcall(vim.api.nvim_win_get_var, win, 'layout_slot')
  if not ok or type(slot) ~= 'string' then return nil end
  if slot:match('^L') then return 'left' end
  if slot:match('^R') then return 'right' end
  if slot:match('^B') then return 'bottom' end
  return nil
end

---Return managed sides represented by the changed-window list.
---@param wins integer[]
---@param changed? integer[]
---@return table<Layout.Side, boolean>
local function managed_sides(wins, changed)
  local changed_set = nil
  if type(changed) == 'table' and #changed > 0 then
    changed_set = {}
    for _, win in ipairs(changed) do
      local id = tonumber(win)
      if id then changed_set[id] = true end
    end
  end

  ---@type table<Layout.Side, boolean>
  local sides = {}
  for _, win in ipairs(wins) do
    if not changed_set or changed_set[win] then
      local side = side_of(win)
      if side then sides[side] = true end
    end
  end
  return sides
end

---Return the first managed panel dimension for each requested side.
---@param wins integer[]
---@param sides? table<Layout.Side, boolean>
---@return table<Layout.Side, integer>
local function panel_dimensions(wins, sides)
  local dimensions = {}
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local side = side_of(win)
      if side and (not sides or sides[side]) and dimensions[side] == nil then
        dimensions[side] = side == 'bottom' and vim.api.nvim_win_get_height(win) or vim.api.nvim_win_get_width(win)
      end
    end
  end
  return dimensions
end

---Return stacking dimensions and total content size for managed slots.
---@param wins integer[]
---@param changed? integer[]
---@return table<string, integer>
---@return table<Layout.Side, integer>
---@return table<Layout.Side, integer>
---@return table<string, Layout.Side>
local function slot_dimensions(wins, changed)
  local changed_set = nil
  if type(changed) == 'table' and #changed > 0 then
    changed_set = {}
    for _, win in ipairs(changed) do
      local id = tonumber(win)
      if id then changed_set[id] = true end
    end
  end

  local dimensions = {}
  local totals = {}
  local counts = {}
  local sides = {}
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local side = side_of(win)
      local key = side and slot_key_of(win) or nil
      if side and key then
        local actual = side == 'bottom' and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win)
        totals[side] = (totals[side] or 0) + actual
        counts[side] = (counts[side] or 0) + 1
        sides[key] = side
        if not changed_set or changed_set[win] then dimensions[key] = actual end
      end
    end
  end
  return dimensions, totals, counts, sides
end

---Return whether current topology matches the last committed placement.
---@param runtime Layout.Panel.Model.Size.Runtime
---@param tabpage? integer
---@return boolean
local function topology_is_stable(runtime, tabpage)
  if not runtime.placed_windows then return false end
  local stable = Windows.same_set(Windows.normal_set(tab_id(tabpage)), runtime.placed_windows)
  runtime.topology_dirty = not stable
  return stable and not runtime.capture_invalid
end

---Capture selected managed panel dimensions as user preferences.
---@param wins integer[]
---@param runtime Layout.Panel.Model.Size.Runtime
---@param changed? integer[]
---@return boolean changed_preference
---@return boolean observed_managed_side
local function capture_dimensions(wins, runtime, changed)
  local sides = managed_sides(wins, changed)
  local observed = next(sides) ~= nil
  if not observed then return false, false end

  local editor_width, editor_height = SharedSize.editor_dimensions()
  local captured = false
  for side, actual in pairs(panel_dimensions(wins, sides)) do
    local previous = runtime.applied[side]
    if previous and actual ~= previous then
      local preference = Size.sizes[side] or Size.configured[side]
      if preference and SharedSize.is_relative(preference) then
        local container = side == 'bottom' and editor_height or editor_width
        Size.sizes[side] = SharedSize.to_fraction(actual, container)
      else
        Size.sizes[side] = math.max(1, actual)
      end
      runtime.applied[side] = actual
      captured = true
    end
  end

  local slots, totals, counts, slot_sides = slot_dimensions(wins, changed)
  for key, actual in pairs(slots) do
    local side = slot_sides[key]
    local previous = runtime.applied_slots[key]
    if side and counts[side] > 1 and previous and actual ~= previous then
      local preference = Size.slot_sizes[key] or Size.configured_slots[key]
      if preference and SharedSize.is_relative(preference) then
        Size.slot_sizes[key] = SharedSize.to_fraction(actual, totals[side])
      else
        Size.slot_sizes[key] = math.max(1, actual)
      end
      runtime.applied_slots[key] = actual
      captured = true
    end
  end
  return captured, true
end

---Clear all preferences and tab-local runtime state.
---@package
function Size:clear()
  self.sizes = {}
  self.configured = {}
  self.slot_sizes = {}
  self.configured_slots = {}
  self.runtime = {}
end

---Explicitly set the shared tracked size for a side.
---@package
---@param side Layout.Side
---@param size Layout.Size
function Size:set(side, size)
  SharedSize.validate(size)
  self.sizes[side] = size
end

---Return the shared tracked preference or configured fallback.
---@public
---@param side Layout.Side
---@param fallback Layout.Size
---@return Layout.Size
function Size:get(side, fallback)
  self.configured[side] = fallback
  return self.sizes[side] or fallback
end

---Return a tracked view size or its configured fallback.
---@public
---@param key string
---@param fallback? Layout.Size
---@return Layout.Size?
function Size:get_slot(key, fallback)
  self.configured_slots[key] = fallback
  return self.slot_sizes[key] or fallback
end

---Initialize an unseen tabpage without treating its geometry as a resize.
---@public
---@param tabpage? integer
function Size:initialize_tab(tabpage)
  local runtime = runtime_for(tabpage)
  if runtime.placed_windows then return end
  local wins = vim.api.nvim_tabpage_list_wins(tab_id(tabpage))
  runtime.applied = panel_dimensions(wins)
  runtime.applied_slots = slot_dimensions(wins)
  runtime.placed_windows = Windows.normal_set(tab_id(tabpage))
end

---Capture current managed dimensions only when topology is stable.
---@public
---@return boolean captured
function Size:update_live()
  local runtime = runtime_for()
  if runtime.placing or runtime.editor_resized then return false end
  if not topology_is_stable(runtime) then return false end
  local captured = capture_dimensions(vim.api.nvim_tabpage_list_wins(0), runtime)
  return captured
end

---Observe a WinResized event and classify its managed-panel effect.
---@public
---@param changed? integer[] Window ids from `vim.v.event.windows`.
---@param allow_dirty? boolean Capture during known active user resizing even if topology changed.
---@return Layout.Panel.Model.Size.Observation
function Size:observe_resize(changed, allow_dirty)
  local runtime = runtime_for()
  if runtime.placing or runtime.editor_resized then return 'ignored' end
  if runtime.capture_invalid then return 'topology' end
  if not allow_dirty and not topology_is_stable(runtime) then return 'topology' end

  local captured, observed = capture_dimensions(vim.api.nvim_tabpage_list_wins(0), runtime, changed)
  if captured then return 'captured' end
  if observed then return 'expected' end
  return 'unrelated'
end

---Begin a placement transaction after capturing any stable user resize.
---@public
---@return boolean started
function Size:begin_placement()
  local runtime = runtime_for()
  if runtime.placing then return false end
  self:update_live()
  runtime.placing = true
  return true
end

---Commit corrected dimensions and topology after successful placement.
---@public
function Size:commit_live()
  local runtime = runtime_for()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  runtime.applied = panel_dimensions(wins)
  runtime.applied_slots = slot_dimensions(wins)
  runtime.placed_windows = Windows.normal_set()
  runtime.topology_dirty = false
  runtime.editor_resized = false
  runtime.capture_invalid = false
  runtime.placing = false
end

---Commit an empty/unmanaged topology without changing preferences.
---@public
function Size:settle_topology()
  local runtime = runtime_for()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  runtime.applied = panel_dimensions(wins)
  runtime.applied_slots = slot_dimensions(wins)
  runtime.placed_windows = Windows.normal_set()
  runtime.topology_dirty = false
  runtime.editor_resized = false
  runtime.capture_invalid = false
  runtime.placing = false
end

---Release a failed placement transaction while retaining its dirty state.
---@public
function Size:abort_placement()
  local runtime = runtime_for()
  runtime.placing = false
  runtime.topology_dirty = true
  runtime.capture_invalid = true
end

---Mark current tabpage topology as requiring placement.
---@public
function Size:mark_topology_changed()
  runtime_for().topology_dirty = true
end

---Prevent editor resizing in every known tab from being captured as a panel preference.
---@public
function Size:mark_editor_resized()
  runtime_for().editor_resized = true
  for _, runtime in pairs(self.runtime) do
    runtime.editor_resized = true
  end
end

---Return whether current topology differs from the committed topology.
---@public
---@return boolean
function Size:topology_changed()
  local runtime = runtime_for()
  if runtime.placed_windows then
    runtime.topology_dirty = not Windows.same_set(Windows.normal_set(), runtime.placed_windows)
  end
  return runtime.topology_dirty or runtime.capture_invalid
end

---Discard runtime entries for tabpages that no longer exist.
---@public
function Size:prune_tabs()
  for tabpage in pairs(self.runtime) do
    if not vim.api.nvim_tabpage_is_valid(tabpage) then self.runtime[tabpage] = nil end
  end
end

return Size
