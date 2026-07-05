--- View registry and filter-based window classification.
---
--- Stores all views declared in the normalized config and provides
--- `match_by_buf()` to classify a buffer/window against the registry.
---
--- Each view has a `filter` function — the only matching mechanism.
--- A string filter is auto-wrapped into a filetype check.  The `events`
--- field on each view declares which Neovim autocommands trigger a
--- debounced re-evaluation; the events serve as *triggers* while the
--- filter is the *matcher*.  This separation means the timing of buffer
--- option availability (e.g. `filetype` set before `FileType` fires) is
--- the user's concern, expressed through their choice of `events`, not
--- a hardcoded assumption in the plugin.

--- Internal entry: side, group name, view name, view descriptor.
---@class Layout.Entity.View.Entry
---@field side Layout.Side
---@field group string
---@field name string
---@field view Layout.View.Entry

---@class Layout.Entity.View
---@field entries Layout.Entity.View.Entry[]
local View = {
  entries = {},
}

--- Return whether a buffer has opted out of layout management.
---@private
---@param bufnr integer
---@return boolean
local function is_disabled(bufnr)
  local info = vim.b[bufnr].layout
  return type(info) == 'table' and info.enabled == false
end

--- Resolve a user-provided filter value into a callable function.
--- A string is auto-wrapped into a filetype filter.
---@package
---@param filter string|fun(buf: integer, win: integer): boolean
---@return fun(buf: integer, win: integer): boolean
local function resolve_filter(filter)
  if type(filter) == 'string' then
    return function(buf)
      return vim.bo[buf].filetype == filter
    end
  end
  return filter
end

--- Clear the registry.
---@package
function View:clear()
  self.entries = {}
end

--- Register all views from a normalized registry.
---@public
---@param registry Layout.Registry
function View:register(registry)
  self:clear()
  vim.iter({ 'left', 'right', 'bottom' }):each(function(side)
    local se = registry[side]
    if se and se.groups and se._order then
      for _, gname in ipairs(se._order) do
        local ge = se.groups[gname]
        if ge and ge._order then
          for _, vname in ipairs(ge._order) do
            local ve = ge.views[vname]
            if ve then
              table.insert(self.entries, {
                side = side,
                group = gname,
                name = vname,
                view = ve,
              })
            end
          end
        end
      end
    end
  end)
end

--- Match a buffer/window against all registered views.
--- Returns the first match as `side, group_name, view_name, view_entry`,
--- or `nil` if no view accepts the buffer.
---@public
---@param bufnr integer
---@param winid? integer
---@return Layout.Side?, string?, string?, Layout.View.Entry?
function View:match_by_buf(bufnr, winid)
  if is_disabled(bufnr) then return nil end
  local entry = vim.iter(self.entries):find(function(e)
    local fn = resolve_filter(e.view.filter)
    local ok, result = pcall(fn, bufnr, winid)
    return ok and result
  end)
  if not entry then return nil end
  return entry.side, entry.group, entry.name, entry.view
end

--- Iterate all registered entries.
---@public
---@return fun(): Layout.Side?, string?, string?, Layout.View.Entry?
function View:iter()
  local i = 0
  return function()
    i = i + 1
    local e = self.entries[i]
    if e then return e.side, e.group, e.name, e.view end
  end
end

return View
