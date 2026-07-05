-- tests/util.lua
-- Helper functions for panel alignment tests.
-- Provides window layout construction and geometry inspection
-- using native Neovim split commands and API (no plugin logic).

local U = {}

-- The grid is sized to leave room for Neovim's split separators
-- (1 column per vertical boundary, 1 row per horizontal boundary).
-- All four layouts need 2 vertical + 1 horizontal separator, so:
--   columns = 30 + 60 + 30 + 2 = 122
--   lines   = 25 + 15 + 1      = 41
-- Sizes are then honored exactly by nvim_win_set_{width,height}.
local COLUMNS = 122
local LINES = 41
local LEFT_W = 30
local CENTER_W = 60
local RIGHT_W = 30
local TOP_H = 25
local BOTTOM_H = 15

--- Tag a window with a readable label for debugging and mapping.
local function tag(child, winid, name)
  child.api.nvim_win_set_var(winid, 'tag', name)
end

--- Prepare a clean, deterministic environment in the child Neovim process.
--- Resets to a single window with fixed screen dimensions and
--- optimizations disabled:
---  - splitright, splitbelow for predictable split direction
---  - noequalalways so manual sizes stick
---  - winwidth=0, winminwidth=0, winminheight=0 so no minimums interfere
---  - laststatus=0, cmdheight=0 so no screen lines are consumed by chrome
---@param child table minitest child process
function U.prepare(child)
  child.cmd('tabnew')
  child.cmd('only')
  child.o.columns = COLUMNS
  child.o.lines = LINES
  child.o.hidden = true
  child.cmd(
    'set splitright splitbelow noequalalways winminwidth=0 winminheight=0 laststatus=0 cmdheight=0 showtabline=0'
  )
end

--------------------------------------------------------------------------------
-- Layout constructors
--
-- Each function returns {tag = winid, ...} for the windows it creates.
-- The tag is set via nvim_win_set_var("tag", name) so assertions can
-- map leaves back to semantic roles.
--------------------------------------------------------------------------------

--- Build the base [L | C | R] row (three vsplits).
---@param child table
---@return table { L=winid, C=winid, R=winid }
function U.make_base(child)
  U.prepare(child)

  local L = child.api.nvim_get_current_win()
  tag(child, L, 'L')

  child.cmd('rightbelow vsplit')
  local C = child.api.nvim_get_current_win()
  tag(child, C, 'C')

  child.cmd('rightbelow vsplit')
  local R = child.api.nvim_get_current_win()
  tag(child, R, 'R')

  child.api.nvim_win_set_width(L, LEFT_W)
  child.api.nvim_win_set_width(C, CENTER_W)
  child.api.nvim_win_set_width(R, RIGHT_W)

  return { L = L, C = C, R = R }
end

--- Derive the contained layout from the base:
--- split center window below → bottom sits under center only;
--- left and right keep full height.
---
---  row[ leaf(L), col[ leaf(C_top), leaf(bottom) ], leaf(R) ]
---
---@param child table
---@param base  table {L, C, R} from make_base
---@return table { L=winid, C_top=winid, bottom=winid, R=winid }
function U.apply_contained(child, base)
  child.api.nvim_set_current_win(base.C)
  child.cmd('belowright split')

  local bottom = child.api.nvim_get_current_win()
  tag(child, bottom, 'bottom')
  tag(child, base.C, 'C_top')

  child.api.nvim_win_set_height(bottom, BOTTOM_H)
  child.api.nvim_win_set_height(base.C, TOP_H)

  return {
    L = base.L,
    C_top = base.C,
    bottom = bottom,
    R = base.R,
  }
end

--- Build the left_aligned layout from scratch.
--- Bottom spans left + center columns; right column takes full height.
---
---  row[ col[ row[ leaf(L), leaf(C) ], leaf(bottom) ], leaf(R) ]
---
---@param child table
---@return table { L=winid, C=winid, bottom=winid, R=winid }
function U.make_left_aligned(child)
  U.prepare(child)

  local A = child.api.nvim_get_current_win() -- left-region container

  child.cmd('rightbelow vsplit')
  local R = child.api.nvim_get_current_win()
  tag(child, R, 'R')

  -- A hosts the L/C split internally; its width must include the
  -- vertical separator that will appear between L and C.
  child.api.nvim_win_set_width(A, LEFT_W + CENTER_W + 1)
  child.api.nvim_win_set_width(R, RIGHT_W)

  -- split A horizontally → bottom below A_top
  child.api.nvim_set_current_win(A)
  child.cmd('belowright split')
  local bottom = child.api.nvim_get_current_win()
  tag(child, bottom, 'bottom')

  child.api.nvim_win_set_height(bottom, BOTTOM_H)
  child.api.nvim_win_set_height(A, TOP_H) -- A handle now = A_top

  -- split A_top vertically → L and C
  child.api.nvim_set_current_win(A)
  child.cmd('rightbelow vsplit')
  local C = child.api.nvim_get_current_win()
  tag(child, C, 'C')
  tag(child, A, 'L') -- original A handle is leftmost leaf

  child.api.nvim_win_set_width(A, LEFT_W)
  child.api.nvim_win_set_width(C, CENTER_W)

  return { L = A, C = C, bottom = bottom, R = R }
end

--- Build the right_aligned layout from scratch.
--- Bottom spans center + right columns; left column takes full height.
---
---  row[ leaf(L), col[ row[ leaf(C), leaf(R) ], leaf(bottom) ] ]
---
---@param child table
---@return table { L=winid, C=winid, bottom=winid, R=winid }
function U.make_right_aligned(child)
  U.prepare(child)

  local L = child.api.nvim_get_current_win()
  tag(child, L, 'L')

  child.cmd('rightbelow vsplit')
  local B = child.api.nvim_get_current_win() -- right-region container

  child.api.nvim_win_set_width(L, LEFT_W)
  -- B hosts the C/R split internally; its width must include the
  -- vertical separator that will appear between C and R.
  child.api.nvim_win_set_width(B, CENTER_W + RIGHT_W + 1)

  -- split B horizontally → bottom below B_top
  child.api.nvim_set_current_win(B)
  child.cmd('belowright split')
  local bottom = child.api.nvim_get_current_win()
  tag(child, bottom, 'bottom')

  child.api.nvim_win_set_height(bottom, BOTTOM_H)
  child.api.nvim_win_set_height(B, TOP_H) -- B handle now = B_top

  -- split B_top vertically → C and R
  child.api.nvim_set_current_win(B)
  child.cmd('rightbelow vsplit')
  local R = child.api.nvim_get_current_win()
  tag(child, B, 'C') -- original B_top handle is left leaf
  tag(child, R, 'R')

  child.api.nvim_win_set_width(B, CENTER_W)
  child.api.nvim_win_set_width(R, RIGHT_W)

  return { L = L, C = B, bottom = bottom, R = R }
end

--- Build the full layout from scratch.
--- Bottom spans left + center + right columns (full width).
---
---  col[ row[ leaf(L), leaf(C), leaf(R) ], leaf(bottom) ]
---
---@param child table
---@return table { L=winid, C=winid, bottom=winid, R=winid }
function U.make_full(child)
  U.prepare(child)

  local A_top = child.api.nvim_get_current_win()

  child.cmd('belowright split')
  local bottom = child.api.nvim_get_current_win()
  tag(child, bottom, 'bottom')

  child.api.nvim_win_set_height(bottom, BOTTOM_H)
  child.api.nvim_win_set_height(A_top, TOP_H)

  -- split A_top vertically three ways → L, C, R
  child.api.nvim_set_current_win(A_top)
  child.cmd('rightbelow vsplit')
  local C = child.api.nvim_get_current_win()
  tag(child, C, 'C')

  child.cmd('rightbelow vsplit')
  local R = child.api.nvim_get_current_win()
  tag(child, A_top, 'L')
  tag(child, R, 'R')

  child.api.nvim_win_set_width(A_top, LEFT_W)
  child.api.nvim_win_set_width(C, CENTER_W)
  child.api.nvim_win_set_width(R, RIGHT_W)

  return { L = A_top, C = C, bottom = bottom, R = R }
end

--------------------------------------------------------------------------------
-- Inspection helpers
--------------------------------------------------------------------------------

--- Get geometry {row, col, width, height} for a window in the child process.
---@param child table
---@param winid number
---@return table
function U.geometry(child, winid)
  local pos = child.api.nvim_win_get_position(winid)
  return {
    row = pos[1],
    col = pos[2],
    width = child.api.nvim_win_get_width(winid),
    height = child.api.nvim_win_get_height(winid),
  }
end

--- Return the raw winlayout tree from the child's current tabpage.
function U.tree(child)
  return child.lua_get('vim.fn.winlayout()')
end

--- Normalize a winlayout tree: replace leaf winids with {"leaf"} so
--- structural comparisons work decoupled from concrete handles.
---
--- winlayout shape: {"row"|"col", {child1, child2, ...}} | {"leaf", winid}
--- normalized shape: {"row"|"col", {norm_child1, ...}} | {"leaf"}
function U.normalize_tree(layout)
  local kind = layout[1]
  if kind == 'leaf' then return { 'leaf' } end
  local children = {}
  for i, child in ipairs(layout[2]) do
    children[i] = U.normalize_tree(child)
  end
  return { kind, children }
end

--- Build a geometry map keyed by window tag.
---@param child table
---@param wins  table {tag = winid}
---@return table
function U.geometry_by_tag(child, wins)
  local out = {}
  for tagname, winid in pairs(wins) do
    out[tagname] = U.geometry(child, winid)
  end
  return out
end

--------------------------------------------------------------------------------
-- Helpers for placement-API tests
--------------------------------------------------------------------------------

--- Tag a window with a readable label (public wrapper around the local tag()).
---@param child table
---@param winid number
---@param name string
function U.tag_window(child, winid, name)
  tag(child, winid, name)
end

--- Create (or reuse) a scratch buffer carrying a human-readable name.
--- The name is stored as a window var so tests can map slots back to buffers.
---@param child table
---@param name string
---@return number bufnr
function U.named_buf(child, name)
  local buf = child.api.nvim_create_buf(false, true)
  child.api.nvim_buf_set_name(buf, name)
  child.api.nvim_buf_set_var(buf, 'tag', name)
  child.api.nvim_set_option_value('buflisted', false, { buf = buf })
  child.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
  return buf
end

--- Build a flat row of N named windows, each showing its own scratch buffer.
--- Used as the "no associated panel" starting state for placement tests.
---@param child table
---@param names string[]   ordered left -> right
---@return table { [name] = winid }, table { [name] = bufnr }
function U.make_scattered(child, names)
  U.prepare(child)
  local wins, bufs = {}, {}
  local first = child.api.nvim_get_current_win()
  local first_buf = U.named_buf(child, names[1])
  child.api.nvim_win_set_buf(first, first_buf)
  U.tag_window(child, first, names[1])
  wins[names[1]] = first
  bufs[names[1]] = first_buf
  for i = 2, #names do
    child.cmd('rightbelow vsplit')
    local w = child.api.nvim_get_current_win()
    local b = U.named_buf(child, names[i])
    child.api.nvim_win_set_buf(w, b)
    U.tag_window(child, w, names[i])
    wins[names[i]] = w
    bufs[names[i]] = b
  end
  return wins, bufs
end

--- Map each current window's `layout_slot` var (set by the placement engine)
--- to its winid. Returns {} if no window is tagged.
---@param child table
---@return table { [slot_label] = winid }
function U.slots_by_tag(child)
  local out = {}
  for _, w in ipairs(child.api.nvim_tabpage_list_wins(0)) do
    local ok, label = pcall(child.api.nvim_win_get_var, w, 'layout_slot')
    if ok and label ~= nil then out[label] = w end
  end
  return out
end

--- Return the bufnr shown in the window whose `layout_slot` var == label.
---@param child table
---@param label string
---@return number?
function U.slot_buf(child, label)
  local slots = U.slots_by_tag(child)
  local w = slots[label]
  if not w then return nil end
  return child.api.nvim_win_get_buf(w)
end

--------------------------------------------------------------------------------
-- Expected values — kept here so the test file stays declarative
--------------------------------------------------------------------------------

U.EXPECTED = {
  contained = {
    tree = {
      'row',
      {
        { 'leaf' },
        { 'col', { { 'leaf' }, { 'leaf' } } },
        { 'leaf' },
      },
    },
    geometry = {
      L = { row = 0, col = 0, width = 30, height = 41 },
      C_top = { row = 0, col = 31, width = 60, height = 25 },
      bottom = { row = 26, col = 31, width = 60, height = 15 },
      R = { row = 0, col = 92, width = 30, height = 41 },
    },
  },
  left_aligned = {
    tree = {
      'row',
      {
        { 'col', { { 'row', { { 'leaf' }, { 'leaf' } } }, { 'leaf' } } },
        { 'leaf' },
      },
    },
    geometry = {
      L = { row = 0, col = 0, width = 30, height = 25 },
      C = { row = 0, col = 31, width = 60, height = 25 },
      bottom = { row = 26, col = 0, width = 91, height = 15 },
      R = { row = 0, col = 92, width = 30, height = 41 },
    },
  },
  right_aligned = {
    tree = {
      'row',
      {
        { 'leaf' },
        { 'col', { { 'row', { { 'leaf' }, { 'leaf' } } }, { 'leaf' } } },
      },
    },
    geometry = {
      L = { row = 0, col = 0, width = 30, height = 41 },
      C = { row = 0, col = 31, width = 60, height = 25 },
      bottom = { row = 26, col = 31, width = 91, height = 15 },
      R = { row = 0, col = 92, width = 30, height = 25 },
    },
  },
  full = {
    tree = {
      'col',
      {
        { 'row', { { 'leaf' }, { 'leaf' }, { 'leaf' } } },
        { 'leaf' },
      },
    },
    geometry = {
      L = { row = 0, col = 0, width = 30, height = 25 },
      C = { row = 0, col = 31, width = 60, height = 25 },
      bottom = { row = 26, col = 0, width = 122, height = 15 },
      R = { row = 0, col = 92, width = 30, height = 25 },
    },
  },
}

--------------------------------------------------------------------------------
-- Entity / feature test helpers
--------------------------------------------------------------------------------

--- Build a minimal layout config for testing registries.
--- Each side takes { size, groups = { [name] = { picker?, views = { [vname] = view_entry } } } }.
--- The helper converts the name-keyed input into the array form expected by normalize().
---@param sides? table<string, table>
---@return table
function U.test_config(sides)
  sides = sides or {}
  local cfg = {}
  for _, side in ipairs({ 'left', 'right', 'bottom' }) do
    local sc = sides[side]
    if sc then
      cfg[side] = { size = sc.size or 30, align = sc.align }
      if sc.groups then
        local ordered = vim.tbl_keys(sc.groups)
        table.sort(ordered)
        cfg[side].groups = {}
        for _, gname in ipairs(ordered) do
          local gdata = sc.groups[gname]
          ---@type Layout.Group.Entry
          local group_entry = { name = gname }
          if gdata.picker then group_entry.picker = vim.deepcopy(gdata.picker) end
          if gdata.views then
            group_entry.views = {}
            local vnames = {}
            for vname, _ in pairs(gdata.views) do
              vnames[#vnames + 1] = vname
            end
            table.sort(vnames)
            for _, vname in ipairs(vnames) do
              local view_entry = vim.deepcopy(gdata.views[vname])
              view_entry.name = vname
              group_entry.views[#group_entry.views + 1] = view_entry
            end
          end
          cfg[side].groups[#cfg[side].groups + 1] = group_entry
        end
      end
    end
  end
  cfg.workspaces = { auto_save = true, auto_restore = true, dir = vim.fn.stdpath('data') .. '/layout-test' }
  return cfg
end

--- Check if a table recursively contains any function values.
---@param t table
---@return boolean
local function has_function(t)
  for _, v in pairs(t) do
    if type(v) == 'function' then return true end
    if type(v) == 'table' and has_function(v) then return true end
  end
  return false
end

--- Write a table value as Lua source, serializing functions inline.
---@param v any
---@return string
local function serialize_lua(v)
  local t = type(v)
  if t == 'string' then
    return string.format('%q', v)
  elseif t == 'number' or t == 'boolean' or v == nil then
    return tostring(v)
  elseif t == 'function' then
    return string.format('loadstring(%q)', string.dump(v))
  elseif t == 'table' then
    local parts = {}
    for k, val in pairs(v) do
      local key
      if type(k) == 'string' and k:match('^[a-zA-Z_][a-zA-Z0-9_]*$') then
        key = k
      else
        key = '[' .. serialize_lua(k) .. ']'
      end
      parts[#parts + 1] = key .. ' = ' .. serialize_lua(val)
    end
    return '{ ' .. table.concat(parts, ', ') .. ' }'
  end
  return 'nil'
end

--- Normalize and register a config inside a child process so that
--- view/group entities are populated.
---@param child table minitest child process
---@param cfg table a layout config table (to be merged + normalized)
---@return table registry (retrieved from child)
function U.setup_config(child, cfg)
  local cfg_str
  if has_function(cfg) then
    cfg_str = serialize_lua(cfg)
  else
    cfg_str = vim.inspect(cfg)
  end
  child.lua('_G._c = ' .. cfg_str)
  child.lua("_G._reg = require('layout.shared.config').normalize(require('layout.shared.config').merge(_G._c))")
  child.lua("require('layout.entities.view'):register(_G._reg)")
  child.lua("require('layout.entities.group'):register(_G._reg)")
  child.lua("require('layout.entities.panel'):set_registry(_G._reg)")
  -- Match the global side effects of require('layout').setup():
  -- allow windows to shrink to zero so user-initiated center splits
  -- and closes do not push panel windows out of their declared size.
  child.o.winminheight = 0
  child.o.winminwidth = 0
  -- lua_get cannot marshal tables containing functions, so only
  -- retrieve the registry when it has no function values.
  if not has_function(cfg) then
    _G._last_reg = child.lua_get('_G._reg')
  else
    _G._last_reg = nil
  end
  return _G._last_reg
end

--- Create a scratch buffer with a given filetype and optional buffer vars,
--- display it in a new window, and return the (winid, bufnr).
---@param child table minitest child process
---@param filetype string
---@param buf_vars? table<string, any>  optional buffer-local variables
---@return number winid
---@return number bufnr
function U.make_tool_win(child, filetype, buf_vars)
  local winid = child.api.nvim_get_current_win()
  local bufnr = child.api.nvim_create_buf(false, true)
  child.api.nvim_win_set_buf(winid, bufnr)
  child.api.nvim_set_option_value('filetype', filetype, { buf = bufnr })
  child.api.nvim_set_option_value('buflisted', false, { buf = bufnr })
  if buf_vars then
    for k, v in pairs(buf_vars) do
      child.api.nvim_buf_set_var(bufnr, k, v)
    end
  end
  return winid, bufnr
end

return U
