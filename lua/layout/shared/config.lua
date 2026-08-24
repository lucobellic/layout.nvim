--- Default configuration and schema for layout.nvim.
---
--- Defines the LuaLS types for the user-facing config and the default
--- values merged into user opts at setup time.

---@alias Layout.Side
---| '"left"'   # Left panel column
---| '"right"'  # Right panel column
---| '"bottom"' # Bottom panel row

--- A shared panel/view size. Values between 0 and 1 are relative to the
--- containing editor or panel axis; positive integers are absolute cells.
---@alias Layout.Size number

--- Buffer-local metadata exposed as `vim.b[bufnr].layout` for buffers managed
--- by layout.nvim. Set `enabled` to `false` to exclude a buffer from future
--- layout evaluation.
---@class Layout.Buffer.Info
---@field side Layout.Side Panel containing the buffer.
---@field group string Configured group containing the view.
---@field view string Configured view that matched the buffer.
---@field enabled boolean Whether layout.nvim manages this buffer.

--- Picker configuration for a group — controls how the group appears in the
--- statusline and how it is selected via the picker.
---@class Layout.Picker
---@field icon? string Nerd Font glyph for the group.
---@field key? string Single char; pressing this key after calling pick() toggles the group.

--- Group config — position in the groups array is declaration order.
---
--- During normalization, the `picker` sub-table is flattened into direct
---`icon` and `key` fields for efficient consumer access.
---@class Layout.Group.Entry
---@field name string Group identifier (used in Layout toggle, restore, picker).
---@field picker? Layout.Picker Picker display and selection configuration.
---@field icon? string Nerd Font glyph for the group (extracted from picker during normalization).
---@field key? string Single-char toggle key (extracted from picker during normalization).
---@field views table<string, Layout.View.Entry> View entries keyed by name.
---@field _order? string[] View names in declaration order.

--- Statusline pick-key placement position.
---@alias Layout.Statusline.PickKeyPose
---| '"left"' # Pick key at the left of the icon, before the left separator
---| '"right"' # Pick key at the right of the icon, after the right separator
---| '"left_separator"' # Replace the left separator with the pick key
---| '"right_separator"' # Replace the right separator with the pick key
---| '"icon"' # Replace the group icon with the pick key

--- Highlight color configuration for statusline icons.
---@class Layout.Statusline.Colors
---@field active string Link target for LayoutActive highlight group
---@field inactive string Link target for LayoutInactive highlight group
---@field hover string Link target for LayoutHover highlight group
---@field pick_active string Link target for LayoutPickActive highlight group
---@field pick_inactive string Link target for LayoutPickInactive highlight group
---@field separator_active string Link target for LayoutSeparatorActive highlight group
---@field separator_inactive string Link target for LayoutSeparatorInactive highlight group

---@alias Layout.Statusline.Rail.Position
---| '"left"' # Occupy the far-left editor column
---| '"right"' # Occupy the far-right editor column

---@alias Layout.Statusline.Rail.Mode
---| '"float"' # Overlay the editor without changing the split layout
---| '"buffer"' # Reserve a fixed-width normal window at the editor edge

---@class Layout.Statusline.Rail.Opts
---@field enabled boolean Show all configured group icons in a fixed-width window.
---@field hover boolean Highlight rail icons under the mouse pointer.
---@field mode Layout.Statusline.Rail.Mode Rail window implementation.
---@field position Layout.Statusline.Rail.Position Editor edge occupied by the rail.
---@field width integer Fixed rail width in columns.
---@field padding integer Spaces inserted before each icon within the configured width.
---@field groups Layout.Statusline.Rail.Groups Panel side displayed in each vertical section.

---@class Layout.Statusline.Rail.Groups
---@field top? Layout.Side Panel groups anchored at the top.
---@field middle? Layout.Side Panel groups centered vertically.
---@field bottom? Layout.Side Panel groups anchored at the bottom.

--- Statusline rendering options for group icons.
---@class Layout.Statusline.Opts
---@field separators { [1]: string, [2]: string } Left and right separators around each icon
---@field clickable boolean Enable toggle on click via v:lua callback regions
---@field colored boolean Enable highlight support (%#LayoutActive...#)
---@field pick_key_pose Layout.Statusline.PickKeyPose Position of the pick key relative to the icon
---@field colors Layout.Statusline.Colors Highlight color mappings
---@field rail Layout.Statusline.Rail.Opts Fixed-width icon rail options.

---@class Layout.Workspaces
---@field auto_save boolean Write layout on view changes.
---@field auto_restore boolean Replay layout when entering a cwd.
---@field dir string Directory for persisted layout files.

--- Top-level user configuration passed to `require("layout").setup(opts)`.
---@class Layout.Config
---@field left? Layout.Side.Config Left panel configuration.
---@field right? Layout.Side.Config Right panel configuration.
---@field bottom? Layout.Side.Config Bottom panel configuration.
---@field live_resize_debounce? integer Quiet period in ms before automatic placement resumes after panel/editor resizing.
---@field workspaces? Layout.Workspaces
---@field statusline? Layout.Statusline.Opts Statusline rendering options for group icons.
---@field events? string[] Autocommand events that trigger re-evaluation of all views.  See `:help autocmd-events`.

--- Normalized view entry built from user config.
---@class Layout.View.Entry
---@field name string View identifier used in commands, restoration, and display title.
---@field filter string|fun(buf: integer, win: integer): boolean
---@field open? string|fun()
---@field size? Layout.Size Stacking height for left/right views or width for bottom views.
---@field bo? table<string, any>
---@field wo? table<string, any>

--- Normalized side entry built from user config.
--- Bottom panel alignment mode.
---@alias Layout.Align
---| '"contained"'     # bottom under center only; L/R keep full height
---| '"left_aligned"'  # bottom spans L+C; R keeps full height
---| '"right_aligned"' # bottom spans C+R; L keeps full height
---| '"full"'          # bottom spans L+C+R full width

---@class Layout.Side.Entry
---@field size Layout.Size Width for left/right panels or height for the bottom panel.
---@field align? Layout.Align Bottom-only alignment (defaults to "full")
---@field groups? table<string, Layout.Group.Entry>
---@field _order? string[] Group names in declaration order

---@class Layout.Group.Config
---@field name string
---@field picker? Layout.Picker
---@field views? Layout.View.Entry[]

---@class Layout.Side.Config
---@field size? Layout.Size Width for left/right panels or height for the bottom panel.
---@field align? Layout.Align Bottom-only alignment.
---@field groups? Layout.Group.Config[] Groups in display and placement order.
---@field [integer]? Layout.Group.Config Groups may alternatively be placed directly on the side table.

--- Normalized layout registry produced by `normalize()`.
--- The registry is a programmatic representation of the user config,
--- with groups and views keyed by name instead of nested inline.
---@class Layout.Registry
---@field left? Layout.Side.Entry
---@field right? Layout.Side.Entry
---@field bottom? Layout.Side.Entry

---@type Layout.Config
local defaults = {
  left = { size = 30 },
  right = { size = 40 },
  bottom = { size = 15, align = 'full' },
  events = { 'FileType', 'WinEnter', 'BufWinEnter' },
  live_resize_debounce = 250,
  workspaces = {
    auto_save = true,
    auto_restore = true,
    dir = vim.fn.stdpath('data') .. '/layout',
  },
  statusline = {
    separators = { ' ', ' ' },
    clickable = true,
    colored = true,
    pick_key_pose = 'right_separator',
    rail = {
      enabled = false,
      hover = false,
      mode = 'float',
      position = 'left',
      width = 1,
      padding = 0,
      groups = {
        top = 'left',
        middle = 'bottom',
        bottom = 'right',
      },
    },
    colors = {
      active = 'Normal',
      inactive = 'Comment',
      hover = 'PmenuSel',
      pick_active = 'PmenuSel',
      pick_inactive = 'PmenuSel',
      separator_active = 'Normal',
      separator_inactive = 'Comment',
    },
  },
}

---@class Layout.Config.Module
local Config = {
  defaults = defaults,
}

local Constants = require('layout.shared.constants')
local Size = require('layout.shared.size')

---@type table<string, boolean>
local VALID_ALIGNMENTS = { contained = true, left_aligned = true, right_aligned = true, full = true }

---@type table<string, boolean>
local VALID_PICK_POSES = { left = true, right = true, left_separator = true, right_separator = true, icon = true }

--- Merge user opts with defaults and return a resolved `Layout.Config`.
---@public
---@param opts? table
---@return Layout.Config
function Config.merge(opts)
  local merged = vim.tbl_deep_extend('force', defaults, opts or {})
  if type(merged.events) ~= 'table' then error('events must be a list of autocommand event names') end
  local events = {}
  local seen_events = {}
  for index, event in ipairs(merged.events) do
    if type(event) ~= 'string' or event == '' then error(('events[%d] must be a non-empty string'):format(index)) end
    if not seen_events[event] then
      events[#events + 1] = event
      seen_events[event] = true
    end
  end
  merged.events = events
  if merged.bottom and merged.bottom.align and not VALID_ALIGNMENTS[merged.bottom.align] then
    error('bottom.align must be "contained", "left_aligned", "right_aligned", or "full"')
  end
  if merged.statusline and not VALID_PICK_POSES[merged.statusline.pick_key_pose] then
    error('statusline.pick_key_pose must be "left", "right", "left_separator", "right_separator", or "icon"')
  end
  local rail = merged.statusline and merged.statusline.rail
  if rail and rail.position ~= 'left' and rail.position ~= 'right' then
    error('statusline.rail.position must be "left" or "right"')
  end
  if rail and rail.mode ~= 'float' and rail.mode ~= 'buffer' then
    error('statusline.rail.mode must be "float" or "buffer"')
  end
  if rail and type(rail.hover) ~= 'boolean' then error('statusline.rail.hover must be a boolean') end
  if rail and (type(rail.width) ~= 'number' or rail.width < 1 or math.floor(rail.width) ~= rail.width) then
    error('statusline.rail.width must be a positive integer')
  end
  if
    rail
    and (
      type(rail.padding) ~= 'number'
      or rail.padding < 0
      or math.floor(rail.padding) ~= rail.padding
      or rail.padding >= rail.width
    )
  then
    error('statusline.rail.padding must be a non-negative integer smaller than statusline.rail.width')
  end
  local groups = rail and rail.groups or {}
  for section, side in pairs(groups) do
    if section ~= 'top' and section ~= 'middle' and section ~= 'bottom' then
      error(('statusline.rail.groups contains unknown section %q'):format(section))
    end
    if side ~= 'left' and side ~= 'right' and side ~= 'bottom' then
      error(('statusline.rail.groups.%s must be "left", "right", or "bottom"'):format(section))
    end
  end
  return merged
end

--- Register valid configured views in declaration order on a normalized group.
---@param side Layout.Side
---@param group Layout.Group.Config
---@param group_entry Layout.Group.Entry
local function normalize_group_views(side, group, group_entry)
  if not group.views or type(group.views) ~= 'table' or group.views[1] == nil then return end
  for _, view in ipairs(group.views) do
    if view.name and view.filter ~= nil then
      if group_entry.views[view.name] then
        error(('%s.%s contains duplicate view name %q'):format(side, group.name, view.name))
      end
      if view.size ~= nil then Size.validate(view.size, side .. '.' .. group.name .. '.' .. view.name .. '.size') end
      group_entry.views[view.name] = view
      group_entry._order[#group_entry._order + 1] = view.name
    end
  end
end

--- Normalize a merged config into a structured registry.
---
--- Groups are declared in the `groups` array and views in each group's
---`views` array.  Array position determines declaration order.
---
--- Groups may also be placed directly on the side table as indexed entries
--- alongside `size` (e.g. `left = { size = 40, { name = 'explorer', ... } }`).
---
---@public
---@param config Layout.Config The merged config (values + defaults)
---@return Layout.Registry
function Config.normalize(config)
  ---@param sc table
  ---@return table[]
  local function groups_from(sc)
    if sc.groups and type(sc.groups) == 'table' and sc.groups[1] ~= nil then return sc.groups end
    if sc[1] ~= nil then
      local arr = {}
      for _, v in ipairs(sc) do
        arr[#arr + 1] = v
      end
      return arr
    end
    return {}
  end

  return vim.iter(Constants.sides):fold({}, function(reg, side)
    local sc = config[side]
    if not sc then return reg end

    ---@type Layout.Size
    local size = assert(sc.size or defaults[side].size)
    Size.validate(size, side .. '.size')

    ---@type Layout.Side.Entry
    local side_entry = { size = size, groups = {}, _order = {}, align = sc.align }

    for _, g in ipairs(groups_from(sc)) do
      if g.name then
        if side_entry.groups[g.name] then error(('%s contains duplicate group name %q'):format(side, g.name)) end
        local pk = g.picker or {}
        ---@type Layout.Group.Entry
        local group_entry = {
          name = g.name,
          icon = pk.icon,
          key = pk.key,
          picker = g.picker,
          views = {},
          _order = {},
        }

        normalize_group_views(side, g, group_entry)

        side_entry.groups[g.name] = group_entry
        side_entry._order[#side_entry._order + 1] = g.name
      end
    end

    reg[side] = side_entry
    return reg
  end)
end

return Config
