--- Live panel size tracking — captures and remembers the current size of
--- managed panel windows so user-initiated resizes persist across
--- arrangement cycles.
---
--- On each stable arrange cycle, `update_live()` scans windows tagged with
--- `layout_slot` and reads their width or height. Window topology changes
--- suspend capture until placement corrects the layout and commits it.
--- When no managed window exists for a side the tracked size is left
--- untouched, preserving the user's preference across panel close/reopen.

---@class Layout.Panel.Model.Size
---@field private sizes table<Layout.Side, integer?> Tracked panel sizes, one per side.
---@field private placed_windows table<integer, boolean>? Window set from the last successful placement cycle.
---@field private topology_dirty boolean Whether a window lifecycle event invalidated live-size capture.
---@field private debounce_timer number? Debounce timer for update_live_debounced.
local Size = {
  sizes = {},
  placed_windows = nil,
  topology_dirty = false,
  debounce_timer = nil,
}

--- Return the current non-floating tabpage window set.
---@private
---@return table<integer, boolean>
local function current_window_set()
  return vim.iter(vim.api.nvim_tabpage_list_wins(0)):fold({}, function(windows, winid)
    if vim.api.nvim_win_get_config(winid).relative == '' then windows[winid] = true end
    return windows
  end)
end

--- Return whether two window sets contain the same ids.
---@private
---@param left table<integer, boolean>
---@param right table<integer, boolean>
---@return boolean
local function same_window_set(left, right)
  for win in pairs(left) do
    if not right[win] then return false end
  end
  for win in pairs(right) do
    if not left[win] then return false end
  end
  return true
end

--- Capture panel dimensions from the supplied windows.
---@private
---@param wins integer[]
function Size:capture_live(wins)
  ---@type table<Layout.Side, boolean>
  local seen = {}
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local ok, slot = pcall(vim.api.nvim_win_get_var, win, 'layout_slot')
      if ok and type(slot) == 'string' then
        ---@type Layout.Side?
        local side = nil
        if slot:match('^L') then
          side = 'left'
        elseif slot:match('^R') then
          side = 'right'
        elseif slot:match('^B') then
          side = 'bottom'
        end
        if side and not seen[side] then
          seen[side] = true
          if side == 'bottom' then
            self.sizes[side] = vim.api.nvim_win_get_height(win)
          else
            self.sizes[side] = vim.api.nvim_win_get_width(win)
          end
        end
      end
    end
  end
end

--- Clear all tracked sizes.
---@private
function Size:clear()
  self.sizes = {}
  self.placed_windows = nil
  self.topology_dirty = false
  if self.debounce_timer then
    vim.fn.timer_stop(self.debounce_timer)
    self.debounce_timer = nil
  end
end

--- Explicitly set the tracked size for a side.
---@package
---@param side Layout.Side
---@param size integer
function Size:set(side, size)
  self.sizes[side] = size
end

--- Return the tracked size for a side, falling back to the provided
--- config value when no size has been set for this side yet.
---@public
---@param side Layout.Side
---@param fallback integer
---@return integer
function Size:get(side, fallback)
  return self.sizes[side] or fallback
end

--- Scan managed panel windows and update tracked sizes when the window
--- topology still matches the last successful placement.
---
--- Panel sizes are read from the first managed window per side
--- (width for L/R, height for bottom).  When a side has no managed
--- windows its tracked size stays as-is, so user resizes survive panel
--- close/reopen cycles.
---@public
function Size:update_live()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local current = current_window_set()
  if self.topology_dirty then return end
  if self.placed_windows and not same_window_set(current, self.placed_windows) then return end
  self:capture_live(wins)
end

--- Capture corrected sizes and establish a new stable window topology.
--- This must only run after a successful placement cycle.
---@public
function Size:commit_live()
  self:capture_live(vim.api.nvim_tabpage_list_wins(0))
  self.placed_windows = current_window_set()
  self.topology_dirty = false
end

--- Establish the current window topology without reading panel dimensions.
--- This is used after every managed panel closes so its remembered size
--- survives while later stable resizes are no longer blocked as collateral.
---@public
function Size:settle_topology()
  self.placed_windows = current_window_set()
  self.topology_dirty = false
end

--- Prevent collateral window-layout changes from being recorded as user resizes.
---@public
function Size:mark_topology_changed()
  self.topology_dirty = true
end

--- Return whether panel sizes are currently invalidated by a topology change.
---@public
---@return boolean
function Size:topology_changed()
  return self.topology_dirty
end

--- Schedule a debounced size capture.
---
--- Restarting the timer within `ms` milliseconds cancels the previous one,
--- so rapid-fire events (e.g. `VimResized` during a drag) only capture
--- sizes once the stream settles.
---@public
---@param ms integer  debounce window in milliseconds
function Size:update_live_debounced(ms)
  if self.debounce_timer then vim.fn.timer_stop(self.debounce_timer) end
  self.debounce_timer = vim.fn.timer_start(ms, function()
    self.debounce_timer = nil
    vim.schedule(function()
      self:update_live()
    end)
  end)
end

return Size
