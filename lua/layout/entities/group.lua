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

local Constants = require('layout.shared.constants')

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
  vim.iter(Constants.sides):each(function(side)
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
  ---@type { side: Layout.Side, name: string, descriptor: Layout.Entity.Group.Desc }[]
  local entries = vim
    .iter(Constants.sides)
    :map(
      ---@param side Layout.Side
      ---@return table[]
      function(side)
        local descriptors = self.groups[side] or {}
        return vim
          .iter(self.group_order[side] or {})
          :map(
            ---@param group_name string
            ---@return { name: string, descriptor: Layout.Entity.Group.Desc? }
            function(group_name)
              return { name = group_name, descriptor = descriptors[group_name] }
            end
          )
          :filter(
            ---@param entry { name: string, descriptor: Layout.Entity.Group.Desc? }
            ---@return boolean
            function(entry)
              return entry.descriptor ~= nil
            end
          )
          :map(
            ---@param entry { name: string, descriptor: Layout.Entity.Group.Desc? }
            ---@return { side: Layout.Side, name: string, descriptor: Layout.Entity.Group.Desc }
            function(entry)
              assert(entry.descriptor)
              return { side = side, name = entry.name, descriptor = entry.descriptor }
            end
          )
          :totable()
      end
    )
    :flatten()
    :totable()

  local index = 0
  return function()
    index = index + 1
    local entry = entries[index]
    if not entry then return nil end
    return entry.side, entry.name, entry.descriptor
  end
end

return Group
