--- Corrective window placement engine.
---
--- Moves existing windows into a declarative layout without closing windows,
--- changing buffers, or rebuilding the window tree from scratch.

local Shape = require('layout.shared.placement.shape')
local Size = require('layout.shared.size')
local Spec = require('layout.shared.placement.spec')

---@class Placement.Engine
local Engine = {}

---@alias Placement.WindowMap table<string, integer>

---@private
---@param win integer?
---@return boolean
local function valid(win)
  return type(win) == 'number' and vim.api.nvim_win_is_valid(win)
end

---@private
---@param win integer?
---@return boolean
local function normal(win)
  return valid(win) and vim.api.nvim_win_get_config(win).relative == ''
end

---@private
---@param spec Placement.Spec
---@return table<integer, boolean>
local function source_windows(spec)
  local sources = {}
  vim.iter({ 'left', 'right', 'bottom' }):each(function(key)
    vim.iter(Spec.region_slots(spec[key])):each(function(slot)
      if normal(slot.winid) then
        if sources[slot.winid] then
          error(('placement: window %d is assigned to more than one slot'):format(slot.winid))
        end
        sources[slot.winid] = true
      else
        error(('placement: slot %s requires a valid non-floating winid'):format(slot.label or '?'))
      end
    end)
  end)
  return sources
end

---@private
---@param sources table<integer, boolean>
---@return integer
local function find_center(sources)
  local current = vim.api.nvim_get_current_win()
  if normal(current) and not sources[current] then return current end

  local available = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
    return normal(win) and not sources[win]
  end)
  if available then return available end

  local anchor = next(sources)
  if not anchor then return current end
  local buf = vim.api.nvim_create_buf(false, true)
  return vim.api.nvim_open_win(buf, false, { split = 'right', win = anchor })
end

---@private
---@param spec Placement.Spec
---@param center integer
---@return Placement.WindowMap
local function window_map(spec, center)
  local windows = { C = center }
  vim.iter({ 'left', 'right', 'bottom' }):each(function(key)
    vim.iter(Spec.region_slots(spec[key])):each(function(slot)
      windows[slot.label] = slot.winid
    end)
  end)
  return windows
end

---@private
---@param windows Placement.WindowMap
local function tag_windows(windows)
  vim.iter(vim.api.nvim_tabpage_list_wins(0)):each(function(win)
    pcall(vim.api.nvim_win_del_var, win, 'layout_slot')
    pcall(vim.api.nvim_win_del_var, win, 'layout_managed')
  end)
  vim.iter(pairs(windows)):each(function(label, win)
    vim.api.nvim_win_set_var(win, 'layout_slot', label)
    if label ~= 'C' then vim.api.nvim_win_set_var(win, 'layout_managed', true) end
  end)
end

---@private
---@param layout table
---@param labels table<integer, string>
---@return Placement.Shape
---@return boolean contains_source
local function project_layout(layout, labels)
  if layout[1] == 'leaf' then
    local label = labels[layout[2]]
    return { 'leaf', label or 'C' }, label ~= nil
  end

  local state = vim.iter(layout[2]):fold({ children = {}, contains_source = false }, function(acc, child)
    local projected, child_has_source = project_layout(child, labels)
    acc.contains_source = acc.contains_source or child_has_source
    local previous = acc.children[#acc.children]
    local duplicate_center = previous
      and previous[1] == 'leaf'
      and previous[2] == 'C'
      and projected[1] == 'leaf'
      and projected[2] == 'C'
    if not duplicate_center then acc.children[#acc.children + 1] = projected end
    return acc
  end)

  if not state.contains_source then return { 'leaf', 'C' }, false end
  if #state.children == 1 then return state.children[1], true end
  return { layout[1], state.children }, true
end

---@private
---@param spec Placement.Spec
---@param windows Placement.WindowMap
---@return boolean
local function shape_is_correct(spec, windows)
  local matched = Shape.match(vim.fn.winlayout(), Shape.build(spec))
  if matched then
    return vim.iter(pairs(windows)):all(function(label, win)
      return matched[label] == win
    end)
  end

  -- A center can itself contain any number of editor splits. Project every
  -- source-free subtree to the single logical C slot before comparing shapes.
  local labels = vim
    .iter(pairs(windows))
    :filter(function(label)
      return label ~= 'C'
    end)
    :fold({}, function(acc, label, win)
      acc[win] = label
      return acc
    end)
  local projected = project_layout(vim.fn.winlayout(), labels)
  return vim.deep_equal(projected, Shape.build(spec))
end

---@private
---@param win integer
---@param command 'H'|'J'|'L'
local function move_to_edge(win, command)
  vim.api.nvim_win_call(win, function()
    vim.cmd('wincmd ' .. command)
  end)
end

---@private
---@param source integer
---@param target integer
---@param vertical boolean
---@param rightbelow boolean
local function splitmove(source, target, vertical, rightbelow)
  if source == target then return end
  vim.fn.win_splitmove(source, target, {
    vertical = vertical,
    rightbelow = rightbelow,
  })
end

---@private
---@param reg? Placement.Region
---@param vertical boolean
local function stack_region(reg, vertical)
  local slots = Spec.region_slots(reg)
  vim
    .iter(slots)
    :enumerate()
    :filter(function(index)
      return index > 1
    end)
    :each(function(index)
      splitmove(slots[index].winid, slots[index - 1].winid, vertical, true)
    end)
end

---@private
---@param spec Placement.Spec
---@param center integer
local function correct_shape(spec, center)
  local left = Spec.region_slots(spec.left)
  local right = Spec.region_slots(spec.right)
  local bottom = Spec.region_slots(spec.bottom)
  local align = Spec.align_of(spec)

  if align == 'contained' then
    if left[1] then move_to_edge(left[1].winid, 'H') end
    if right[1] then move_to_edge(right[1].winid, 'L') end
    if bottom[1] then splitmove(bottom[1].winid, center, false, true) end
  elseif align == 'left_aligned' then
    if bottom[1] then move_to_edge(bottom[1].winid, 'J') end
    if right[1] then move_to_edge(right[1].winid, 'L') end
    if left[1] then splitmove(left[1].winid, center, true, false) end
  elseif align == 'right_aligned' then
    if bottom[1] then move_to_edge(bottom[1].winid, 'J') end
    if left[1] then move_to_edge(left[1].winid, 'H') end
    if right[1] then splitmove(right[1].winid, center, true, true) end
  elseif align == 'full' then
    if left[1] then move_to_edge(left[1].winid, 'H') end
    if right[1] then move_to_edge(right[1].winid, 'L') end
    if bottom[1] then move_to_edge(bottom[1].winid, 'J') end
  else
    error('placement: unknown align ' .. tostring(align))
  end

  stack_region(spec.left, false)
  stack_region(spec.right, false)
  stack_region(spec.bottom, true)
end

---@private
---@param win integer
---@param width integer?
---@param height integer?
local function resize(win, width, height)
  if width == vim.api.nvim_win_get_width(win) then width = nil end
  if height == vim.api.nvim_win_get_height(win) then height = nil end
  if not width and not height then return end

  if vim.fn.has('nvim-0.13') == 1 and vim.api.nvim_win_resize then
    vim.api.nvim_win_resize(win, width or -1, height or -1, {})
  else
    local config = {}
    if width then config.width = width end
    if height then config.height = height end
    vim.api.nvim_win_set_config(win, config)
  end
end

--- Resolve the stacking-axis size for each slot in a multi-slot region.
---
--- Explicit sizes are resolved and allocated in declaration order. Size-less
--- slots share the remaining space, with any remainder added to the last flex
--- slot. Every slot retains at least one cell when requests exceed the panel.
---@private
---@param slots Placement.Slot[]
---@param get_dim fun(win: integer): integer  current stacking dim (height for L/R, width for bottom)
---@return integer[]  resolved stacking size per slot
local function resolve_stacking_sizes(slots, get_dim)
  local resolved = {}
  local n = #slots
  if n <= 1 then return resolved end

  local raw_total = 0
  for _, s in ipairs(slots) do
    raw_total = raw_total + get_dim(s.winid)
  end

  local flex_count = vim.iter(slots):fold(0, function(count, slot)
    return count + (slot.size == nil and 1 or 0)
  end)
  local remaining = math.max(0, raw_total - n)

  for i, slot in ipairs(slots) do
    if slot.size ~= nil then
      local requested = Size.resolve(slot.size, raw_total)
      local extra = math.min(math.max(0, requested - 1), remaining)
      resolved[i] = 1 + extra
      remaining = remaining - extra
    else
      resolved[i] = 1
    end
  end

  if flex_count > 0 then
    local each = math.floor(remaining / flex_count)
    local extra = remaining - each * flex_count
    local flex_idx = 0
    for i, slot in ipairs(slots) do
      if slot.size == nil then
        flex_idx = flex_idx + 1
        resolved[i] = resolved[i] + each + (flex_idx == flex_count and extra or 0)
      end
    end
  end
  return resolved
end

---@private
---@param spec Placement.Spec
---@param editor_width integer
---@param editor_height integer
local function apply_sizes(spec, editor_width, editor_height)
  vim.iter({ 'left', 'right' }):each(function(key)
    local reg = spec[key]
    if reg then
      local slots = reg.slots
      local multi = #slots > 1
      local sizes = resolve_stacking_sizes(slots, vim.api.nvim_win_get_height)
      for i, slot in ipairs(slots) do
        resize(slot.winid, Size.resolve(reg.size, editor_width), multi and sizes[i] or nil)
        vim.api.nvim_set_option_value('winfixwidth', true, { win = slot.winid })
        vim.api.nvim_set_option_value('winfixheight', multi, { win = slot.winid })
      end
    end
  end)

  local bottom = spec.bottom
  if bottom then
    local slots = bottom.slots
    local multi = #slots > 1
    local sizes = resolve_stacking_sizes(slots, vim.api.nvim_win_get_width)
    for i, slot in ipairs(slots) do
      resize(slot.winid, multi and sizes[i] or nil, Size.resolve(bottom.size, editor_height))
      vim.api.nvim_set_option_value('winfixwidth', multi, { win = slot.winid })
      vim.api.nvim_set_option_value('winfixheight', true, { win = slot.winid })
    end
  end
end

--- Run fn with deterministic window options, then restore them.
---
--- Center (non-panel) windows are temporarily given winfixwidth and
--- winfixheight before equalalways is restored so Neovim's
--- win_equalizeall (triggered by setting equalalways back to true)
--- cannot resize them.  Their original winfix values are then restored.
---@private
---@param fn fun()
---@param windows? Placement.WindowMap  window map for identifying panel windows
local function with_deterministic_options(fn, windows)
  local names = {
    equalalways = false,
    splitright = true,
    splitbelow = true,
    splitkeep = 'screen',
    winminwidth = 0,
    winminheight = 0,
    eventignore = 'all',
  }
  local saved = {}
  vim.iter(pairs(names)):each(function(name, value)
    saved[name] = vim.api.nvim_get_option_value(name, {})
    vim.api.nvim_set_option_value(name, value, {})
  end)

  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    vim.iter(pairs(saved)):each(function(name, value)
      pcall(vim.api.nvim_set_option_value, name, value, {})
    end)
    error(err)
  end

  -- Protect center windows so equalization triggered by restoring 'equalalways'
  -- leaves them untouched.  All windows that are not panel windows (L/R/B)
  -- have winfixwidth and winfixheight set to 'true' before the global option
  -- restoration, then their originals are restored after.
  local panel_wins, center_fix = {}, {}
  if windows then
    vim.iter(pairs(windows)):each(function(label, win)
      if label ~= 'C' then panel_wins[win] = true end
    end)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_is_valid(win) and not panel_wins[win] then
        center_fix[#center_fix + 1] = {
          win = win,
          wfw = vim.api.nvim_get_option_value('winfixwidth', { win = win }),
          wfh = vim.api.nvim_get_option_value('winfixheight', { win = win }),
        }
        vim.api.nvim_set_option_value('winfixwidth', true, { win = win })
        vim.api.nvim_set_option_value('winfixheight', true, { win = win })
      end
    end
  end

  -- Restore 'equalalways' (and others) while center windows are protected.
  vim.iter(pairs(saved)):each(function(name, value)
    pcall(vim.api.nvim_set_option_value, name, value, {})
  end)

  -- Restore center windows' original winfix values.
  for _, c in ipairs(center_fix) do
    if vim.api.nvim_win_is_valid(c.win) then
      pcall(vim.api.nvim_set_option_value, 'winfixwidth', c.wfw, { win = c.win })
      pcall(vim.api.nvim_set_option_value, 'winfixheight', c.wfh, { win = c.win })
    end
  end
end

--- Correct the current tabpage to match a normalized placement spec.
---@public
---@param spec Placement.Spec
function Engine.place(spec)
  local sources = source_windows(spec)
  local center = find_center(sources)
  local windows = window_map(spec, center)
  local editor_width, editor_height = Size.editor_dimensions()

  with_deterministic_options(function()
    if not shape_is_correct(spec, windows) then correct_shape(spec, center) end
    apply_sizes(spec, editor_width, editor_height)
    tag_windows(windows)
  end, windows)
end

return Engine
