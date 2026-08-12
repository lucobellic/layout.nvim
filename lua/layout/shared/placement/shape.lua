--- Target shape tree and structural matching against `vim.fn.winlayout`.
---
--- A shape tree is a normalized representation of the target window
--- arrangement: "leaf" nodes carry slot labels, "row"/"col" inner nodes
--- describe the split structure. It is used to recognize an already-correct
--- winlayout so the corrective engine can skip structural moves.

local Spec = require('layout.shared.placement.spec')

local Shape = {}

--- A shape-tree node: `{"leaf", label}` | `{"row"|"col", children}`.
---@class Placement.Shape
---@field [1] "leaf"|"row"|"col"
---@field [2] string|Placement.Shape[]

--- Label->winid map returned by match_shape.
---@alias Placement.Match table<string, integer>

---@private
---@param reg? Placement.Region
---@param stack_axis "row"|"col"
---@return Placement.Shape?
local function region_node(reg, stack_axis)
  local slots = Spec.region_slots(reg)
  if #slots == 0 then return nil end
  if #slots == 1 then return { 'leaf', slots[1].label } end
  local kids = vim
    .iter(slots)
    :map(function(slot)
      return { 'leaf', slot.label }
    end)
    :totable()
  return { stack_axis, kids }
end

---@private
---@param node? Placement.Shape
---@return Placement.Shape?
local function collapse(node)
  if node == nil then return nil end
  if node[1] == 'leaf' then return node end
  local kind, kids = node[1], node[2]
  local filtered = vim.iter(kids):map(collapse):totable()
  if #filtered == 0 then return nil end
  if #filtered == 1 then return filtered[1] end
  return { kind, filtered }
end

--- Build a children list, dropping nils (handles absent regions without
--- leaving holes that would break `#`/`ipairs` traversal).
---@private
---@param ... Placement.Shape?
---@return Placement.Shape[]
local function kids(...)
  local t = {}
  local n = select('#', ...)
  for i = 1, n do
    local c = select(i, ...)
    if c ~= nil then t[#t + 1] = c end
  end
  return t
end

---@public
---@param spec Placement.Spec
---@return Placement.Shape
function Shape.build(spec)
  local L = region_node(spec.left, 'col')
  local R = region_node(spec.right, 'col')
  local B = region_node(spec.bottom, 'row')
  local C = { 'leaf', 'C' }
  local root
  if Spec.align_of(spec) == 'contained' then
    root = { 'row', kids(L, { 'col', kids(C, B) }, R) }
  elseif Spec.align_of(spec) == 'left_aligned' then
    root = { 'row', kids({ 'col', kids({ 'row', kids(L, C) }, B) }, R) }
  elseif Spec.align_of(spec) == 'right_aligned' then
    root = { 'row', kids(L, { 'col', kids({ 'row', kids(C, R) }, B) }) }
  elseif Spec.align_of(spec) == 'full' then
    root = { 'col', kids({ 'row', kids(L, C, R) }, B) }
  else
    error('placement: unknown align ' .. tostring(Spec.align_of(spec)))
  end
  root = collapse(root)
  if spec.rail then
    local rail = { 'leaf', spec.rail.slot.label }
    if spec.rail.position == 'left' then
      root = { 'row', { rail, root } }
    else
      root = { 'row', { root, rail } }
    end
  end
  return root
end

--- Match a raw winlayout tree against a target shape.
--- Returns label->winid map on success, nil on shape mismatch.
---@public
---@param layout table  raw `vim.fn.winlayout()` tree
---@param shape Placement.Shape
---@return Placement.Match?
function Shape.match(layout, shape)
  if shape[1] == 'leaf' then
    if layout[1] ~= 'leaf' then return nil end
    return { [shape[2]] = layout[2] }
  end
  if layout[1] ~= shape[1] then return nil end
  if #layout[2] ~= #shape[2] then return nil end
  local acc = {}
  local matches = vim.iter(shape[2]):enumerate():all(function(index, child)
    local matched = Shape.match(layout[2][index], child)
    if matched == nil then return false end
    vim.iter(pairs(matched)):each(function(k, v)
      acc[k] = v
    end)
    return true
  end)
  if not matches then return nil end
  return acc
end

return Shape
