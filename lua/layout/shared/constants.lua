---@class Layout.Shared.Constants
---@field sides Layout.Side[] Canonical panel order.
---@field side_set table<Layout.Side, boolean> Valid panel sides.
local Constants = {
  sides = { 'left', 'right', 'bottom' },
  side_set = { left = true, right = true, bottom = true },
}

return Constants
