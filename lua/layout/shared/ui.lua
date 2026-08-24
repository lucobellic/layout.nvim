--- Highlight group management.
---
--- Creates and manages statusline highlight groups (LayoutActive,
--- LayoutInactive, etc.) in a 3-level hierarchy: base → position →
--- position+index.  Groups are re-created on ColorScheme to survive
--- colorscheme reloads.

---@class Layout.Shared.UI
---@field private augroup number?
local UI = {
  augroup = nil,
}

local CATEGORIES =
  { 'Active', 'Inactive', 'Hover', 'PickActive', 'PickInactive', 'SeparatorActive', 'SeparatorInactive' }
local SIDES = { 'Left', 'Right', 'Bottom' }

--- Convert PascalCase to snake_case.
---@private
---@param str string
---@return string
local function to_snake_case(str)
  return str
    :gsub('(%u)', function(s)
      return '_' .. s:lower()
    end)
    :gsub('^_', '')
end

--- Decapitalize the first letter.
---@private
---@param str string
---@return string
local function decapitalize(str)
  return str:sub(1, 1):lower() .. str:sub(2)
end

--- Check whether a highlight group already exists (defined by colorscheme or user).
---@private
---@param group_name string
---@return boolean
local function highlight_exists(group_name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group_name, link = false })
  return ok and next(hl) ~= nil
end

--- Create a highlight link if the target group does not already exist.
---@private
---@param from_group string
---@param to_group string
local function create_highlight_link(from_group, to_group)
  if not highlight_exists(from_group) then vim.api.nvim_set_hl(0, from_group, { link = to_group }) end
end

--- Build a highlight group name: Layout{Category}{Side?}{Index?}.
---@private
---@param kind string Active, Inactive, PickActive, etc.
---@param position? string Left, Right, Bottom
---@param level? number 1-based index
---@return string
local function hl_group_name(kind, position, level)
  return 'Layout' .. kind .. (position or '') .. (level or '')
end

--- Create the full 3-level highlight group hierarchy: base → position → position+index.
--- Respects groups already defined by colorschemes.
---@private
---@param counts table<Layout.Side, integer>
---@param colors Layout.Statusline.Colors
function UI.setup_statusline_highlights(counts, colors)
  vim.iter(CATEGORIES):each(function(category)
    local base = hl_group_name(category)
    create_highlight_link(base, colors[to_snake_case(category)] or 'Normal')

    vim.iter(SIDES):each(function(position)
      local nb = counts[decapitalize(position)] or 0
      local pos_name = hl_group_name(category, position)
      create_highlight_link(pos_name, base)

      for i = 1, nb do
        create_highlight_link(hl_group_name(category, position, i), pos_name)
      end
    end)
  end)
end

--- Register a ColorScheme autocommand that re-creates highlight links.
---@public
---@param counts table<Layout.Side, integer>
---@param colors Layout.Statusline.Colors
function UI:setup(counts, colors)
  UI.setup_statusline_highlights(counts, colors)

  if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup) end
  self.augroup = vim.api.nvim_create_augroup('LayoutUI', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = self.augroup,
    callback = function()
      vim.schedule(function()
        UI.setup_statusline_highlights(counts, colors)
      end)
    end,
  })
end

return UI
