--- Group registry — maps (side, name) to group metadata.
---
--- Groups are keyed by name within each side, storing icon, key, and
--- the ordered list of view names they contain.

---@class Layout.Entity.Group.Desc
---@field icon? string
---@field key? string

---@class Layout.Entity.Group
---@field groups table<Layout.Side, table<string, Layout.Entity.Group.Desc>> Group descriptors by side and name.
---@field group_order table<Layout.Side, string[]> Group names by side in declaration order.
---@field registry Layout.Registry? Reference to the registry for views_for queries.
local Group = {
  groups = {},
  group_order = {},
  registry = nil,
}

--- Clear the registry.
---@package
function Group:clear()
  self.groups = {}
  self.group_order = {}
  self.registry = nil
end

--- Register all groups from a normalized registry.
---@public
---@param registry Layout.Registry
function Group:register(registry)
  self:clear()
  self.registry = registry
  vim.iter({ 'left', 'right', 'bottom' }):each(function(side)
    local se = registry[side]
    if se and se.groups and se._order then
      self.group_order[side] = {}
      self.groups[side] = {}
      for _, groupe_name in ipairs(se._order) do
        local ge = se.groups[groupe_name]
        if ge then
          self.group_order[side][#self.group_order[side] + 1] = groupe_name
          self.groups[side][groupe_name] = { icon = ge.icon, key = ge.key }
        end
      end
    end
  end)
end

--- Look up a group by name on a side.
---@public
---@param side Layout.Side
---@param name string
---@return Layout.Entity.Group.Desc?
function Group:get(side, name)
  local sg = self.groups[side]
  return sg and sg[name]
end

--- List group names on a side in declaration order.
---@public
---@param side Layout.Side
---@return string[]
function Group:list(side)
  return self.group_order[side] or {}
end

--- Return the view entries (key → Layout.View.Entry) for a group.
---@public
---@param side Layout.Side
---@param group_name string
---@return table<string, Layout.View.Entry>
function Group:views_for(side, group_name)
  if not self.registry then return {} end
  local se = self.registry[side]
  if not se then return {} end
  local ge = se.groups[group_name]
  if not ge then return {} end
  return ge.views
end

--- Return views in declaration order as an array of {name, entry} pairs.
---@public
---@param side Layout.Side
---@param group_name string
---@return {name:string, view:Layout.View.Entry}[]
function Group:views_ordered(side, group_name)
  if not self.registry then return {} end
  local se = self.registry[side]
  if not se then return {} end
  local ge = se.groups[group_name]
  if not ge then return {} end
  local result = {}
  for _, vname in ipairs(ge._order or {}) do
    if ge.views[vname] then result[#result + 1] = { name = vname, view = ge.views[vname] } end
  end
  return result
end

--- Iterate all groups in declaration order: side, group_name, descriptor.
---@public
---@return fun(): Layout.Side?, string?, Layout.Entity.Group.Desc?
function Group:iter()
  local sides = { 'left', 'right', 'bottom' }
  local si = 0
  local keys = nil
  local ki = 0
  return function()
    while true do
      if not keys then
        si = si + 1
        if si > #sides then return nil end
        keys = self.group_order[sides[si]]
        if keys then ki = 0 end
      else
        ki = ki + 1
        if ki > #keys then
          keys = nil
        else
          local k = keys[ki]
          local sg = self.groups[sides[si]]
          if sg then return sides[si], k, sg[k] end
        end
      end
    end
  end
end

return Group
