--- Window placement engine public API.
---
--- Normalizes a declarative region spec and corrects the current window tree
--- by moving existing windows into place.
---
---@class Placement
local Placement = {}

local Spec = require('layout.shared.placement.spec')
local Engine = require('layout.shared.placement.engine')

--- Move existing windows to match a declarative placement spec.
---@public
---@param spec Placement.Spec
function Placement.place(spec)
  Engine.place(Spec.normalize_spec(spec))
end

return Placement
