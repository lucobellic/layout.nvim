--- Statusline rendering for group icons with optional highlight and click support.
---
--- Provides get_statusline(side) which returns a list of statusline strings
--- (one per group) that can be consumed by lualine, heirline, bufferline, etc.
--- A pick mode flag injects group keys when the user calls :Layout pick.
---
--- on_click(minwid) serves as the v:lua click handler for clickable regions.

local Group = require('layout.entities.group')
local Toggle = require('layout.features.toggle')
local View = require('layout.entities.view')

---@class Layout.Statusline.Cache.Line
---@field name string Group name (used for active-group lookup)
---@field icon string Group icon glyph
---@field key string Group key (for pick mode injection; empty when unset)
---@field minwid integer Sequential id for the %@v:lua click region

---@class Layout.Feature.Statusline
---@field public pick_mode boolean Whether pick mode is currently active (shows group keys next to icons)
---@field private cache table<Layout.Side, Layout.Statusline.Cache.Line[]> Cached per-side group lines
---@field private click_map table<integer, { side: Layout.Side, name: string }> Map of minwid to (side, group) for click dispatch
---@field private opts Layout.Statusline.Opts Statusline rendering options
---@field private pick_lines table<Layout.Statusline.PickKeyPose, fun(pick: string, sep_hl: string, icon_hl: string, line: Layout.Statusline.Cache.Line): string> In-pick-mode rendering variants keyed by pick_key_pose.
local Statusline = {
  pick_mode = false,
  cache = {},
  click_map = {},
  opts = {},
  pick_lines = {},
}

---@private
---@param str string
---@return string
local function capitalize(str)
  return str:sub(1, 1):upper() .. str:sub(2)
end

--- Build a statusline highlight marker: %#Layout{Category}{Side}{Index}#.
---@private
---@param category string Active, Inactive, PickActive, PickInactive, SeparatorActive, SeparatorInactive
---@param side Layout.Side
---@param index integer 1-based index within the side
---@return string
local function stl_highlight(category, side, index)
  return '%#Layout' .. category .. capitalize(side) .. index .. '#'
end

--- Scan all tabpage windows and classify them to build an active-map
---{ [side] = { [group_name] = true } }.
---@private
---@return table<Layout.Side, table<string, boolean>>
local function compute_active()
  local active = { left = {}, right = {}, bottom = {} }
  local wins = vim.api.nvim_tabpage_list_wins(0)
  vim.iter(wins):each(function(winid)
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local side, gname = View:match_by_buf(bufnr, winid)
      if side and gname and active[side] then active[side][gname] = true end
    end
  end)
  return active
end

--- Build the cache of per-side group display lines.
--- Assigns a global sequential minwid for click dispatch.
--- Groups missing either icon or key are excluded.
---@private
function Statusline:build_cache()
  self.cache = {}
  self.click_map = {}
  local minwid = 0
  for _, side in ipairs({ 'left', 'right', 'bottom' }) do
    self.cache[side] = vim.iter(Group:list(side)):fold({}, function(lines, gname)
      local gdesc = Group:get(side, gname)
      if not gdesc then return lines end
      if not gdesc.icon or gdesc.icon == '' or not gdesc.key or gdesc.key == '' then return lines end
      minwid = minwid + 1
      self.click_map[minwid] = { side = side, name = gname }
      lines[#lines + 1] = {
        name = gname,
        icon = gdesc.icon,
        key = gdesc.key,
        minwid = minwid,
      }
      return lines
    end)
  end
end

--- Initialize the statusline module with the normalized registry and user options.
---@public
---@param registry Layout.Registry
---@param opts Layout.Statusline.Opts
function Statusline:setup(registry, opts)
  self.opts = vim.deepcopy(opts)
  self:build_cache()
  self:build_pick_lines()
end

function Statusline:build_pick_lines()
  self.pick_lines = {
    left = function(pick, sep_hl, icon_hl, line)
      return pick .. sep_hl .. self.opts.separators[1] .. icon_hl .. line.icon .. sep_hl .. self.opts.separators[2]
    end,
    right = function(pick, sep_hl, icon_hl, line)
      return sep_hl .. self.opts.separators[1] .. icon_hl .. line.icon .. sep_hl .. self.opts.separators[2] .. pick
    end,
    left_separator = function(pick, sep_hl, icon_hl, line)
      return pick .. icon_hl .. line.icon .. sep_hl .. self.opts.separators[2]
    end,
    right_separator = function(pick, sep_hl, icon_hl, line)
      return sep_hl .. self.opts.separators[1] .. icon_hl .. line.icon .. pick
    end,
    icon = function(pick, sep_hl, icon_hl, _)
      return sep_hl .. self.opts.separators[1] .. pick .. icon_hl .. sep_hl .. self.opts.separators[2]
    end,
  }
end

--- Build the highlight string for an icon in a given state.
--- Returns the `%#...#` marker when colored is enabled, empty string otherwise.
---@private
---@param category string 'Active'|'Inactive'|'PickActive'|'PickInactive'|'SeparatorActive'|'SeparatorInactive'
---@param is_active boolean
---@param side Layout.Side
---@param index integer
---@return string
function Statusline:icon_highlight(category, is_active, side, index)
  if not self.opts.colored then return '' end
  local state = is_active and 'Active' or 'Inactive'
  return stl_highlight(category .. state, side, index)
end

--- Build the pick-key segment: highlight + character (only when pick_mode is on).
---@public
---@param is_active boolean
---@param side Layout.Side
---@param index integer
---@param key string
---@return string
function Statusline:pick_text(is_active, side, index, key)
  if not self.pick_mode or key == '' then return '' end
  return self:icon_highlight('Pick', is_active, side, index) .. key
end

--- Build a single group's statusline string (icon, separators, highlights, pick key, click).
---@private
---@param side Layout.Side
---@param index integer 1-based position within the side
---@param line Layout.Statusline.Cache.Line
---@param active table<Layout.Side, table<string, boolean>>
---@return string
function Statusline:build_line(side, index, line, active)
  local is_active = active[side] and active[side][line.name] or false

  local click_prefix = ''
  local click_suffix = ''
  if self.opts.clickable then
    click_prefix = '%' .. line.minwid .. "@v:lua.require'layout.features.statusline'.on_click@"
    click_suffix = '%T'
  end

  local sep_hl = self:icon_highlight('Separator', is_active, side, index)
  local icon_hl = self:icon_highlight('', is_active, side, index)
  local pick = self:pick_text(is_active, side, index, line.key)

  if not self.pick_mode then
    return click_prefix
      .. sep_hl
      .. self.opts.separators[1]
      .. icon_hl
      .. line.icon
      .. sep_hl
      .. self.opts.separators[2]
      .. click_suffix
  end

  local build = self.pick_lines[self.opts.pick_key_pose] or self.pick_lines['left']
  return build(pick, sep_hl, icon_hl, line)
end

--- Return a list of statusline strings for the given side, one per group.
--- Each string may contain highlight markers and click regions depending on
--- statusline options and current pick mode state.
---@public
---@param side Layout.Side
---@return string[]
function Statusline:get_statusline(side)
  local lines = self.cache[side] or {}
  if #lines == 0 then return {} end

  local active = compute_active()
  return vim.iter(ipairs(lines)):fold({}, function(result, index, line)
    result[#result + 1] = self:build_line(side, index, line, active)
    return result
  end)
end

--- v:lua click handler invoked by Neovim's statusline %@ click regions.
--- Toggles the group identified by the encoded minwid.
---@public
---@param minwid integer Encoded (side, group) id from the click_map
---@param clicks integer
---@param button string
---@param mods string
---@diagnostic disable-next-line: unused-local
function Statusline:on_click(minwid, clicks, button, mods)
  local entry = self.click_map[minwid]
  if not entry then return end
  Toggle.toggle_group(entry.side, entry.name)
  vim.cmd.redrawstatus()
end

return Statusline
