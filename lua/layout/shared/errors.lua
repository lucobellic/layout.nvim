---@class Layout.Shared.Errors
local Errors = {}

--- Identify Neovim's insufficient room error, including wrapped tracebacks.
---@public
---@param err any
---@return boolean
function Errors.is_not_enough_room(err)
  return tostring(err):find('E36:', 1, true) ~= nil
end

return Errors
