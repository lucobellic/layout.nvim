---Fixed-width floating or buffer rail for layout group icons.

local SharedSize = require('layout.shared.size')
local Statusline = require('layout.features.statusline')

---@class Layout.Feature.Rail.State
---@field bufnr integer
---@field winid integer
---@field entries table<integer, Layout.Statusline.Entry> Entries keyed by rendered buffer line.

---@class Layout.Feature.Rail
---@field opts Layout.Statusline.Rail.Opts?
---@field clickable boolean
---@field augroup integer?
---@field setup_generation integer
---@field state table<integer, Layout.Feature.Rail.State> Rail state keyed by tabpage.
---@field last_win table<integer, integer> Last non-rail window keyed by tabpage.
---@field mouse_mapping boolean Whether the global mouse interceptor is installed.
local Rail = {
  opts = nil,
  clickable = true,
  augroup = nil,
  setup_generation = 0,
  state = {},
  last_win = {},
  mouse_mapping = false,
}

---@param entry Layout.Statusline.Entry
---@return string?
local function highlight(entry)
  local category = Statusline.pick_mode and 'Pick' or ''
  return Statusline:highlight_group(category, entry.active, entry.side, entry.index)
end

---@param entry Layout.Statusline.Entry
---@return string
local function entry_text(entry)
  local padding = Rail.opts and Rail.opts.padding or 0
  return string.rep(' ', padding) .. (Statusline.pick_mode and entry.key or entry.icon)
end

---@param tabpage integer
---@return nil
local function close_state(tabpage)
  local state = Rail.state[tabpage]
  if not state then return end
  if vim.api.nvim_win_is_valid(state.winid) then pcall(vim.api.nvim_win_close, state.winid, true) end
  if vim.api.nvim_buf_is_valid(state.bufnr) then pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true }) end
  Rail.state[tabpage] = nil
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
  vim.api.nvim_win_set_width(winid, Rail.opts.width)
end

---@return string keys Keys passed back to Neovim's mapping engine.
local function handle_left_mouse()
  if not Rail.clickable or not Rail.opts or not Rail.opts.enabled then
    return '<LeftMouse>'
  end

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
  vim.keymap.set({ 'n', 'x', 'o', 'i' }, '<LeftMouse>', handle_left_mouse, {
    expr = true,
    silent = true,
    replace_keycodes = true,
    desc = 'Dispatch clicks on the layout rail',
  })
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

---@return vim.api.keyset.win_config
local function buffer_window_config()
  return {
    split = Rail.opts and Rail.opts.position or 'left',
    win = vim.api.nvim_get_current_win(),
    style = 'minimal',
    noautocmd = true,
  }
end

---@param tabpage integer
---@return Layout.Feature.Rail.State
local function ensure_state(tabpage)
  local state = Rail.state[tabpage]
  if state and vim.api.nvim_win_is_valid(state.winid) and vim.api.nvim_buf_is_valid(state.bufnr) then return state end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false

  local config = Rail.opts and Rail.opts.mode == 'buffer' and buffer_window_config() or float_window_config()
  local winid = vim.api.nvim_open_win(bufnr, false, config)
  vim.wo[winid].winhl = 'Normal:Normal'
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = false
  vim.wo[winid].statuscolumn = ''
  vim.wo[winid].signcolumn = 'no'
  vim.wo[winid].foldcolumn = '0'
  if Rail.opts and Rail.opts.mode == 'buffer' then
    vim.api.nvim_win_set_width(winid, Rail.opts.width)
    vim.wo[winid].winfixwidth = true
  end

  state = { bufnr = bufnr, winid = winid, entries = {} }
  Rail.state[tabpage] = state
  return state
end

---Place selected panel entries into top, middle, and bottom rail sections.
---When ideal section ranges overlap, all entries are packed from the top.
---@param entries Layout.Statusline.Entry[]
---@param height integer
---@return string[] lines
---@return table<integer, Layout.Statusline.Entry> entries_by_line
local function layout_entries(entries, height)
  ---@type table<string, Layout.Statusline.Entry[]>
  local sections = { top = {}, middle = {}, bottom = {} }
  for section, side in pairs(Rail.opts and Rail.opts.groups or {}) do
    for _, entry in ipairs(entries) do
      if entry.side == side then sections[section][#sections[section] + 1] = entry end
    end
  end

  local starts = {
    top = 1,
    middle = math.floor((height - #sections.middle) / 2) + 1,
    bottom = height - #sections.bottom + 1,
  }
  local ordered = { 'top', 'middle', 'bottom' }
  local previous_end = 0
  local overlap = #sections.top + #sections.middle + #sections.bottom > height
  for _, name in ipairs(ordered) do
    if #sections[name] > 0 then
      local section_end = starts[name] + #sections[name] - 1
      if starts[name] < 1 or starts[name] <= previous_end or section_end > height then overlap = true end
      previous_end = section_end
    end
  end

  local lines = {}
  local entries_by_line = {}
  if overlap then
    for _, name in ipairs(ordered) do
      for _, entry in ipairs(sections[name]) do
        lines[#lines + 1] = entry_text(entry)
        entries_by_line[#lines] = entry
      end
    end
    return lines, entries_by_line
  end

  for _ = 1, height do
    lines[#lines + 1] = ''
  end
  for _, name in ipairs(ordered) do
    for index, entry in ipairs(sections[name]) do
      local line = starts[name] + index - 1
      lines[line] = entry_text(entry)
      entries_by_line[line] = entry
    end
  end
  return lines, entries_by_line
end

---Render current group state into the active tabpage rail.
---@public
---@return nil
function Rail:render()
  if not self.opts or not self.opts.enabled then return end
  local tabpage = vim.api.nvim_get_current_tabpage()
  local entries = Statusline:get_entries()
  local selected_sides = {}
  for _, side in pairs(self.opts.groups) do
    selected_sides[side] = true
  end
  local has_entries = vim.iter(entries):any(function(entry)
    return selected_sides[entry.side] == true
  end)
  if not has_entries and self.opts.mode == 'float' then
    close_state(tabpage)
    return
  end

  local state = ensure_state(tabpage)
  local lines
  lines, state.entries = layout_entries(entries, vim.api.nvim_win_get_height(state.winid))

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.bufnr, -1, 0, -1)
  for index, entry in pairs(state.entries) do
    local group = highlight(entry)
    if group then vim.api.nvim_buf_add_highlight(state.bufnr, -1, group, index - 1, 0, -1) end
  end
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
    for _, tabpage in ipairs(vim.tbl_keys(self.state)) do
      close_state(tabpage)
    end
    return false
  end

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

---Initialize rail options and lifecycle autocommands.
---@public
---@param opts Layout.Statusline.Rail.Opts
---@param clickable boolean
---@return nil
function Rail:setup(opts, clickable)
  self.opts = vim.deepcopy(opts)
  self.clickable = clickable
  self.setup_generation = self.setup_generation + 1
  self.last_win = {}
  ensure_mouse_mapping()
  local generation = self.setup_generation

  if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup) end
  self.augroup = vim.api.nvim_create_augroup('LayoutRail', { clear = true })
  vim.schedule(function()
    if self.setup_generation ~= generation then return end
    for _, tabpage in ipairs(vim.tbl_keys(self.state)) do
      close_state(tabpage)
    end
    if self.opts and self.opts.enabled then self:refresh() end
  end)
  if not opts.enabled then return end

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinClosed' }, {
    group = self.augroup,
    callback = function()
      vim.schedule(function()
        if self.opts and self.opts.mode == 'buffer' then
          self:refresh()
        else
          self:render()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = self.augroup,
    callback = function()
      local tabpage = vim.api.nvim_get_current_tabpage()
      local winid = vim.api.nvim_get_current_win()
      local state = self.state[tabpage]
      if state and state.winid == winid then
        reject_buffer_rail_focus()
      elseif vim.api.nvim_win_get_config(winid).relative == '' then
        self.last_win[tabpage] = winid
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'VimResized', 'TabEnter' }, {
    group = self.augroup,
    callback = function()
      vim.schedule(function()
        self:refresh()
      end)
    end,
  })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = self.augroup,
    callback = function()
      for tabpage in pairs(self.state) do
        if not vim.api.nvim_tabpage_is_valid(tabpage) then
          close_state(tabpage)
          self.last_win[tabpage] = nil
        end
      end
    end,
  })
end

return Rail
