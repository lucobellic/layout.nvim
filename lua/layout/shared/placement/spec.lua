--- Declarative placement spec model and normalization.
---
--- Defines Placement.Spec, Placement.Region, Placement.Slot and the
--- normalization pipeline that fills defaults, assigns slot labels
--- (L1, R2, B1, C), and resolves bottom alignment.

---@alias Placement.Align "contained"|"left_aligned"|"right_aligned"|"full"
---| '"contained"'     # bottom under center only; L/R keep full height
---| '"left_aligned"'  # bottom spans L+C; R keeps full height
---| '"right_aligned"' # bottom spans C+R; L keeps full height
---| '"full"'          # bottom spans L+C+R full width

---@alias Placement.RegionKey "left"|"right"|"bottom"

---@alias Placement.Rail.Position "left"|"right"

---@class Placement.Rail
---@field position Placement.Rail.Position
---@field size Layout.Size
---@field slot Placement.Slot

--- A single source/binding descriptor inside a region's `slots`.
---@class Placement.Slot
---@field winid? integer Source window id (bufnr resolved from it if omitted)
---@field bufnr? integer Buffer to display in this slot
---@field size? Layout.Size Stacking size (height for L/R, width for B)
---@field wo? table<string, any> Window-local options to apply
---@field bo? table<string, any> Buffer-local options to apply
---@field label? string Assigned by `normalize_spec` (e.g. "L1", "B2")

--- A panel region (left, right, or bottom).
---@class Placement.Region
---@field size Layout.Size Region width (L/R) or height (B), excluding separators
---@field align? Placement.Align Bottom-only alignment (defaults to "contained")
---@field slots Placement.Slot[] Ordered slots (top->bottom for sides, left->right for bottom)

--- Declarative placement spec accepted by the placement engine.
---@class Placement.Spec
---@field left? Placement.Region
---@field right? Placement.Region
---@field bottom? Placement.Region
---@field rail? Placement.Rail Full-height outer edge slot.
---@field center? boolean Keep a center/editor slot (default `true`)

local Spec = {
  SIDES = { left = 'L', right = 'R', bottom = 'B' },
}

--- Assign labels to a region's slots in place.
---@private
---@param reg? Placement.Region
---@param letter string
local function label_region(reg, letter)
  if not reg or not reg.slots then return end
  vim.iter(reg.slots):enumerate():each(function(index, slot)
    slot.label = letter .. index
  end)
end

---@public
---@param reg? Placement.Region
---@return Placement.Slot[]
function Spec.region_slots(reg)
  return (reg and reg.slots) and reg.slots or {}
end

--- Normalize a raw user spec: defaults + labels.
---@public
---@param spec? Placement.Spec
---@return Placement.Spec
function Spec.normalize_spec(spec)
  spec = spec or {}
  spec.left = spec.left or nil
  spec.right = spec.right or nil
  spec.bottom = spec.bottom or nil
  if spec.bottom and spec.bottom.align == nil then spec.bottom.align = 'contained' end
  if spec.center == nil then spec.center = true end
  label_region(spec.left, 'L')
  label_region(spec.right, 'R')
  label_region(spec.bottom, 'B')
  if spec.rail then spec.rail.slot.label = 'Q' end
  return spec
end

---@public
---@param spec Placement.Spec
---@return Placement.Align
function Spec.align_of(spec)
  return (spec.bottom and spec.bottom.align) or 'contained'
end

return Spec
