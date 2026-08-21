---Shared classification for statusline and rail pick-key placement.

---@alias Layout.Shared.PickPose.Kind
---| '"left"'
---| '"right"'
---| '"icon"'

---@class Layout.Shared.PickPose
local PickPose = {}

---Reduce an exact pick-key pose to its visual side.
---@public
---@param pose Layout.Statusline.PickKeyPose
---@return Layout.Shared.PickPose.Kind
function PickPose.kind(pose)
  if pose == 'icon' then return 'icon' end
  if pose == 'right' or pose == 'right_separator' then return 'right' end
  return 'left'
end

return PickPose
