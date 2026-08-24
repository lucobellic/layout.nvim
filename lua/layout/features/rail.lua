---Fixed-width floating or buffer rail for layout group icons.

local PickPose = require('layout.shared.pick_pose')
local SharedSize = require('layout.shared.size')
local Statusline = require('layout.features.statusline')

local HIGHLIGHT_NS = vim.api.nvim_create_namespace('LayoutRailHighlights')

---@class Layout.Feature.Rail.State
---@field bufnr integer
---@field winid integer
---@field entries table<integer, Layout.Statusline.Entry> Entries keyed by rendered buffer line.

---@class Layout.Feature.Rail
---@field opts Layout.Statusline.Rail.Opts?
---@field pick_key_pose Layout.Statusline.PickKeyPose
---@field clickable boolean
---@field augroup integer?
---@field setup_generation integer
---@field state table<integer, Layout.Feature.Rail.State> Rail state keyed by tabpage.
---@field last_win table<integer, integer> Last non-rail window keyed by tabpage.
---@field mouse_mapping boolean Whether the global mouse interceptor is installed.
---@field saved_mouse_mappings table<string, table> User mappings replaced by the interceptor.
---@field mousemove_ns integer? Namespace used to observe mouse movement.
---@field mousemove_original boolean? Option value to restore when hover handling stops.
---@field hover_line table<integer, integer> Hovered entry line keyed by tabpage.
local Rail = {
  opts = nil,
  pick_key_pose = 'icon',
  clickable = true,
  augroup = nil,
  setup_generation = 0,
  state = {},
  last_win = {},
  mouse_mapping = false,
  saved_mouse_mappings = {},
  mousemove_ns = nil,
  mousemove_original = nil,
  hover_line = {},
}

---@param entry Layout.Statusline.Entry
---@param hovered? boolean
---@return string?
local function highlight(entry, hovered)
  if hovered then return Statusline:hover_highlight(entry.side, entry.index) end
  return Statusline:highlight_group('', entry.active, entry.side, entry.index)
end

---@param bufnr integer
---@param line integer
---@param group string?
---@param start_col integer
---@param end_col integer
---@return nil
local function add_highlight(bufnr, line, group, start_col, end_col)
  if not group then return end
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''
  if start_col >= #text then return end
  if end_col >= 0 then end_col = math.min(end_col, #text) end
  vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NS, line - 1, start_col, {
    end_col = end_col >= 0 and end_col or nil,
    hl_eol = end_col < 0,
    hl_group = group,
  })
end

---@param text string
---@param width integer
---@return string
local function fit_display_width(text, width)
  local result = ''
  for index = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, index, 1)
    if vim.fn.strdisplaywidth(result .. char) > width then break end
    result = result .. char
  end
  return result
end

---@param bufnr integer
---@param line integer
---@param entry Layout.Statusline.Entry
---@return nil
local function add_entry_highlights(bufnr, line, entry)
  local padding = Rail.opts and Rail.opts.padding or 0
  local icon_group = highlight(entry)
  if not Statusline.pick_mode then
    add_highlight(bufnr, line, icon_group, padding, padding + #entry.icon)
    return
  end

  local pick_group = Statusline:highlight_group('Pick', entry.active, entry.side, entry.index)
  local pose = PickPose.kind(Rail.pick_key_pose)
  if pose == 'icon' then
    add_highlight(bufnr, line, pick_group, padding, padding + #entry.key)
  elseif pose == 'left' then
    add_highlight(bufnr, line, pick_group, padding, padding + #entry.key)
    add_highlight(bufnr, line, icon_group, padding + #entry.key, padding + #entry.key + #entry.icon)
  else
    add_highlight(bufnr, line, icon_group, padding, padding + #entry.icon)
    add_highlight(bufnr, line, pick_group, padding + #entry.icon, padding + #entry.icon + #entry.key)
  end
end

---@param entry Layout.Statusline.Entry
---@return string
local function entry_text(entry)
  local padding = Rail.opts and Rail.opts.padding or 0
  local text = entry.icon
  if Statusline.pick_mode then
    local pose = PickPose.kind(Rail.pick_key_pose)
    if pose == 'icon' then
      text = entry.key
    elseif pose == 'left' then
      text = entry.key .. entry.icon
    else
      text = entry.icon .. entry.key
    end
  end
  local width = Rail.opts and Rail.opts.width or 1
  return fit_display_width(string.rep(' ', padding) .. text, width)
end

---@param tabpage integer
---@return nil
local function close_state(tabpage)
  local state = Rail.state[tabpage]
  if not state then return end
  if vim.api.nvim_win_is_valid(state.winid) then pcall(vim.api.nvim_win_close, state.winid, true) end
  if vim.api.nvim_buf_is_valid(state.bufnr) then pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true }) end
  Rail.state[tabpage] = nil
  Rail.hover_line[tabpage] = nil
end

---@return nil
local function reject_buffer_rail_focus()
  if not Rail.opts or Rail.opts.mode ~= 'buffer' then return end
  local tabpage = vim.api.nvim_get_current_tabpage()
  local winid = vim.api.nvim_get_current_win()
  local state = Rail.state[tabpage]
  if not state or state.winid ~= winid then return end

  local target = Rail.last_win[tabpage]
  if not target or not vim.api.nvim_win_is_valid(target) or target == winid then
    target = vim.iter(vim.api.nvim_tabpage_list_wins(tabpage)):find(function(candidate)
      return candidate ~= winid and vim.api.nvim_win_get_config(candidate).relative == ''
    end)
  end
  if not target then return end
  vim.api.nvim_set_current_win(target)
  vim.api.nvim_win_set_config(winid, { width = Rail.opts.width })
end

---@return string keys Keys passed back to Neovim's mapping engine.
local function handle_left_mouse()
  if not Rail.clickable or not Rail.opts or not Rail.opts.enabled then return '<LeftMouse>' end

  local mouse = vim.fn.getmousepos()
  local state = Rail.state[vim.api.nvim_get_current_tabpage()]
  if not state or mouse.winid ~= state.winid then return '<LeftMouse>' end

  local line = mouse.line
  vim.schedule(function()
    Rail:on_click(line)
  end)
  return '<Ignore>'
end

---@return nil
local function ensure_mouse_mapping()
  if Rail.mouse_mapping then return end
  Rail.mouse_mapping = true
  Rail.saved_mouse_mappings = {}
  for _, mode in ipairs({ 'n', 'x', 'o', 'i' }) do
    local mapping = vim.fn.maparg('<LeftMouse>', mode, false, true)
    if type(mapping) == 'table' and next(mapping) then Rail.saved_mouse_mappings[mode] = mapping end
  end
  vim.keymap.set({ 'n', 'x', 'o', 'i' }, '<LeftMouse>', handle_left_mouse, {
    expr = true,
    silent = true,
    replace_keycodes = true,
    desc = 'Dispatch clicks on the layout rail',
  })
end

---@return nil
local function remove_mouse_mapping()
  if not Rail.mouse_mapping then return end
  for _, mode in ipairs({ 'n', 'x', 'o', 'i' }) do
    pcall(vim.keymap.del, mode, '<LeftMouse>')
    local mapping = Rail.saved_mouse_mappings[mode]
    if mapping then pcall(vim.fn.mapset, mode, false, mapping) end
  end
  Rail.saved_mouse_mappings = {}
  Rail.mouse_mapping = false
end

---@return nil
local function ensure_mousemove_listener()
  if Rail.mousemove_ns then return end
  Rail.mousemove_ns = vim.api.nvim_create_namespace('LayoutRailMouseMove')
  vim.on_key(function(key)
    if key ~= vim.keycode('<MouseMove>') then return end
    vim.schedule(function()
      Rail:update_hover(vim.fn.getmousepos())
    end)
  end, Rail.mousemove_ns)
end

---@return nil
local function disable_mousemove_listener()
  if Rail.mousemove_ns then vim.on_key(nil, Rail.mousemove_ns) end
  Rail.mousemove_ns = nil
  if Rail.mousemove_original ~= nil then vim.o.mousemoveevent = Rail.mousemove_original end
  Rail.mousemove_original = nil
end

---@return nil
local function enable_interactions()
  if Rail.clickable then ensure_mouse_mapping() end
  if Rail.opts and Rail.opts.hover then
    Rail.mousemove_original = vim.o.mousemoveevent
    vim.o.mousemoveevent = true
    ensure_mousemove_listener()
  end
end

---@return nil
local function disable_interactions()
  remove_mouse_mapping()
  disable_mousemove_listener()
end

---@return vim.api.keyset.win_config
local function float_window_config()
  local _, height = SharedSize.editor_dimensions()
  local width = Rail.opts and Rail.opts.width or 1
  return {
    relative = 'editor',
    row = 0,
    col = Rail.opts and Rail.opts.position == 'right' and vim.o.columns - width or 0,
    width = width,
    height = height,
    anchor = 'NW',
    style = 'minimal',
    focusable = false,
    mouse = Rail.clickable,
    noautocmd = true,
    zindex = 50,
  }
end

---@param tabpage integer
---@return vim.api.keyset.win_config
local function buffer_window_config(tabpage)
  local target = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(target).relative ~= '' then
    target = vim.iter(vim.api.nvim_tabpage_list_wins(tabpage)):find(function(winid)
      return vim.api.nvim_win_get_config(winid).relative == ''
    end)
  end
  if not target then error('layout rail: no normal window available for split creation') end
  return {
    split = Rail.opts and Rail.opts.position or 'left',
    win = target,
    style = 'minimal',
    noautocmd = true,
  }
end

---Create the scratch buffer used to render one rail.
---@return integer bufnr
local function create_rail_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  return bufnr
end

---Apply minimal window options and fixed sizing to a rail window.
---@param winid integer
---@return nil
local function configure_rail_window(winid)
  vim.wo[winid].winhl = 'Normal:Normal'
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = false
  vim.wo[winid].statuscolumn = ''
  vim.wo[winid].signcolumn = 'no'
  vim.wo[winid].foldcolumn = '0'
  if Rail.opts and Rail.opts.mode == 'buffer' then
    vim.api.nvim_win_set_config(winid, { width = Rail.opts.width })
    vim.wo[winid].winfixwidth = true
  end
end

---@param tabpage integer
---@return Layout.Feature.Rail.State
local function ensure_state(tabpage)
  local state = Rail.state[tabpage]
  if state and vim.api.nvim_win_is_valid(state.winid) and vim.api.nvim_buf_is_valid(state.bufnr) then return state end

  local bufnr = create_rail_buffer()
  local config = Rail.opts and Rail.opts.mode == 'buffer' and buffer_window_config(tabpage) or float_window_config()
  local winid = vim.api.nvim_open_win(bufnr, false, config)
  configure_rail_window(winid)

  state = { bufnr = bufnr, winid = winid, entries = {} }
  Rail.state[tabpage] = state
  return state
end

---Group statusline entries into configured top, middle, and bottom sections.
---@param entries Layout.Statusline.Entry[]
---@return table<string, Layout.Statusline.Entry[]>
local function collect_sections(entries)
  local sections = { top = {}, middle = {}, bottom = {} }
  for section, side in pairs(Rail.opts and Rail.opts.groups or {}) do
    for _, entry in ipairs(entries) do
      if entry.side == side then sections[section][#sections[section] + 1] = entry end
    end
  end
  return sections
end

---Calculate each section's ideal starting line.
---@param sections table<string, Layout.Statusline.Entry[]>
---@param height integer
---@return table<string, integer>
local function section_starts(sections, height)
  return {
    top = 1,
    middle = math.floor((height - #sections.middle) / 2) + 1,
    bottom = height - #sections.bottom + 1,
  }
end

---Return whether ideal section ranges cannot fit without intersecting.
---@param sections table<string, Layout.Statusline.Entry[]>
---@param starts table<string, integer>
---@param height integer
---@return boolean
local function sections_overlap(sections, starts, height)
  if #sections.top + #sections.middle + #sections.bottom > height then return true end
  local previous_end = 0
  for _, name in ipairs({ 'top', 'middle', 'bottom' }) do
    if #sections[name] > 0 then
      local section_end = starts[name] + #sections[name] - 1
      if starts[name] < 1 or starts[name] <= previous_end or section_end > height then return true end
      previous_end = section_end
    end
  end
  return false
end

---Pack all sections contiguously when their ideal ranges overlap.
---@param sections table<string, Layout.Statusline.Entry[]>
---@return string[] lines
---@return table<integer, Layout.Statusline.Entry> entries_by_line
local function pack_sections(sections)
  local lines = {}
  local entries_by_line = {}
  for _, name in ipairs({ 'top', 'middle', 'bottom' }) do
    for _, entry in ipairs(sections[name]) do
      lines[#lines + 1] = entry_text(entry)
      entries_by_line[#lines] = entry
    end
  end
  return lines, entries_by_line
end

---Place sections at their top, middle, and bottom anchors.
---@param sections table<string, Layout.Statusline.Entry[]>
---@param starts table<string, integer>
---@param height integer
---@return string[] lines
---@return table<integer, Layout.Statusline.Entry> entries_by_line
local function anchor_sections(sections, starts, height)
  local lines = {}
  local entries_by_line = {}
  for _ = 1, height do
    lines[#lines + 1] = ''
  end
  for _, name in ipairs({ 'top', 'middle', 'bottom' }) do
    for index, entry in ipairs(sections[name]) do
      local line = starts[name] + index - 1
      lines[line] = entry_text(entry)
      entries_by_line[line] = entry
    end
  end
  return lines, entries_by_line
end

---Place selected panel entries into top, middle, and bottom rail sections.
---When ideal section ranges overlap, all entries are packed from the top.
---Return whether any entry belongs to a side selected by the rail.
---@param entries Layout.Statusline.Entry[]
---@param height integer
---@return string[] lines
---@return table<integer, Layout.Statusline.Entry> entries_by_line
local function layout_entries(entries, height)
  local sections = collect_sections(entries)
  local starts = section_starts(sections, height)
  if sections_overlap(sections, starts, height) then return pack_sections(sections) end
  return anchor_sections(sections, starts, height)
end

---@param entries Layout.Statusline.Entry[]
---@param groups Layout.Statusline.Rail.Groups
---@return boolean
local function has_selected_entries(entries, groups)
  local selected_sides = {}
  for _, side in pairs(groups) do
    selected_sides[side] = true
  end
  return vim.iter(entries):any(function(entry)
    return selected_sides[entry.side] == true
  end)
end

---Replace rail buffer contents and apply entry highlights.
---@param state Layout.Feature.Rail.State
---@param lines string[]
---@param tabpage integer
---Close every rail window and buffer across tabpages.
---@return nil
local function write_state(state, lines, tabpage)
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.bufnr, HIGHLIGHT_NS, 0, -1)
  for index, entry in pairs(state.entries) do
    if Rail.hover_line[tabpage] == index then
      add_highlight(state.bufnr, index, highlight(entry, true), 0, -1)
    else
      add_entry_highlights(state.bufnr, index, entry)
    end
  end
end

---Render current group state into the active tabpage rail.
---@public
---@return nil
function Rail:render()
  if not self.opts or not self.opts.enabled then return end
  local tabpage = vim.api.nvim_get_current_tabpage()
  local entries = Statusline:get_entries()
  if not has_selected_entries(entries, self.opts.groups) and self.opts.mode == 'float' then
    close_state(tabpage)
    return
  end

  local state = ensure_state(tabpage)
  local lines
  lines, state.entries = layout_entries(entries, vim.api.nvim_win_get_height(state.winid))
  write_state(state, lines, tabpage)
end

---Update the highlighted rail entry from a mouse position.
---@public
---@param mouse { winid: integer, line: integer }
---@return nil
function Rail:update_hover(mouse)
  if not self.opts or not self.opts.enabled or not self.opts.hover then return end
  local tabpage = vim.api.nvim_get_current_tabpage()
  local state = self.state[tabpage]
  local line = state and mouse.winid == state.winid and state.entries[mouse.line] and mouse.line or nil
  if self.hover_line[tabpage] == line then return end
  self.hover_line[tabpage] = line
  if state and vim.api.nvim_win_is_valid(state.winid) then self:render() end
end

---Reposition and redraw the active tabpage rail.
---@public
---@return nil
function Rail:refresh()
  if not self.opts or not self.opts.enabled then return end
  local tabpage = vim.api.nvim_get_current_tabpage()
  local state = self.state[tabpage]
  if state and vim.api.nvim_win_is_valid(state.winid) and self.opts.mode == 'float' then
    vim.api.nvim_win_set_config(state.winid, float_window_config())
  end
  self:render()
  if self.opts.mode == 'buffer' then require('layout.entities.panel'):arrange() end
end

---Toggle runtime rail visibility globally.
---@public
---@return boolean enabled Whether the rail is visible after toggling.
function Rail:toggle()
  if not self.opts then return false end
  self.opts.enabled = not self.opts.enabled
  if not self.opts.enabled then
    disable_interactions()
    for _, tabpage in ipairs(vim.tbl_keys(self.state)) do
      close_state(tabpage)
    end
    return false
  end

  enable_interactions()
  self:refresh()
  return true
end

---Return the active buffer rail as an outer placement slot.
---@public
---@return Placement.Rail?
function Rail:placement_spec()
  if not self.opts or not self.opts.enabled or self.opts.mode ~= 'buffer' then return nil end
  local state = self.state[vim.api.nvim_get_current_tabpage()]
  if not state or not vim.api.nvim_win_is_valid(state.winid) then return nil end
  return {
    position = self.opts.position,
    size = self.opts.width,
    slot = { winid = state.winid, bufnr = state.bufnr },
  }
end

---Dispatch a rail row through the statusline's existing click map.
---@public
---@param line integer
---@return nil
function Rail:on_click(line)
  if not self.clickable then return end
  local state = self.state[vim.api.nvim_get_current_tabpage()]
  local entry = state and state.entries[line] or nil
  if not entry then return end
  Statusline.on_click(entry.minwid, 1, 'l', '')
  vim.schedule(function()
    self:render()
  end)
end

---@return nil
local function close_all_states()
  for _, tabpage in ipairs(vim.tbl_keys(Rail.state)) do
    close_state(tabpage)
  end
end

---Recreate rail state after setup unless a newer setup supersedes it.
---@param generation integer
---Schedule a render or full refresh after window lifecycle events.
---@return nil
local function schedule_state_reset(generation)
  vim.schedule(function()
    if Rail.setup_generation ~= generation then return end
    close_all_states()
    if Rail.opts and Rail.opts.enabled then Rail:refresh() end
  end)
end

---Track the latest editor window and reject focus entering buffer rails.
---@return nil
local function schedule_content_refresh()
  vim.schedule(function()
    if Rail.opts and Rail.opts.mode == 'buffer' then
      Rail:refresh()
    else
      Rail:render()
    end
  end)
end

---Discard state associated with closed tabpages.
---@return nil
local function track_entered_window()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local winid = vim.api.nvim_get_current_win()
  local state = Rail.state[tabpage]
  if state and state.winid == winid then
    reject_buffer_rail_focus()
  elseif vim.api.nvim_win_get_config(winid).relative == '' then
    Rail.last_win[tabpage] = winid
  end
end

---@return nil
local function prune_closed_tabs()
  for tabpage in pairs(Rail.state) do
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      close_state(tabpage)
      Rail.last_win[tabpage] = nil
    end
  end
end

---Register rail rendering, focus, resize, and tab lifecycle hooks.
---@param augroup integer
---@return nil
local function wire_lifecycle_autocmds(augroup)
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinClosed' }, {
    group = augroup,
    callback = schedule_content_refresh,
  })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = augroup,
    callback = track_entered_window,
  })
  vim.api.nvim_create_autocmd({ 'VimResized', 'TabEnter' }, {
    group = augroup,
    callback = function()
      vim.schedule(function()
        Rail:refresh()
      end)
    end,
  })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = augroup,
    callback = prune_closed_tabs,
  })
end

---Initialize rail options and lifecycle autocommands.
---@public
---@param opts Layout.Statusline.Rail.Opts
---@param clickable boolean
---@param pick_key_pose Layout.Statusline.PickKeyPose
---@return nil
function Rail:setup(opts, clickable, pick_key_pose)
  disable_interactions()
  self.opts = vim.deepcopy(opts)
  self.clickable = clickable
  self.pick_key_pose = pick_key_pose
  self.setup_generation = self.setup_generation + 1
  self.last_win = {}
  if opts.enabled then enable_interactions() end
  local generation = self.setup_generation

  if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup) end
  self.augroup = vim.api.nvim_create_augroup('LayoutRail', { clear = true })
  schedule_state_reset(generation)
  if not opts.enabled then return end
  wire_lifecycle_autocmds(self.augroup)
end

return Rail
