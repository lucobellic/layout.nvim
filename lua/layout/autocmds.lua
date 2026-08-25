--- Autocommand wiring and resize/placement coordination.
---
--- Managed panel resizes are captured immediately. Automatic placement is
--- deferred until the resize stream has been quiet for the configured delay,
--- preventing placement from restoring stale geometry while the user drags.

local Panel = require('layout.entities.panel')
local Restore = require('layout.features.restore')
local Save = require('layout.features.save')
local Size = require('layout.entities.panel.model.size')
local View = require('layout.entities.view')

---@class Layout.Autocmds.Session
---@field arrange_timer uv.uv_timer_t?
---@field arrange_generation integer
---@field resize_timer uv.uv_timer_t?
---@field resize_generation integer
---@field resize_active boolean
---@field pending_arrange boolean
---@field pending_save boolean
---@field insufficient_room boolean

---@class Layout.Autocmds
---@field private registry Layout.Registry?
---@field private config Layout.Config?
---@field private augroup integer?
---@field private sessions table<integer, Layout.Autocmds.Session> Sessions keyed by tabpage handle.
local Autocmds = {
  registry = nil,
  config = nil,
  augroup = nil,
  sessions = {},
}

---@param tabpage? integer
---@return integer
local function tab_id(tabpage)
  return tabpage or vim.api.nvim_get_current_tabpage()
end

---@param tabpage? integer
---@return Layout.Autocmds.Session
local function session_for(tabpage)
  local id = tab_id(tabpage)
  if not Autocmds.sessions[id] then
    Autocmds.sessions[id] = {
      arrange_timer = nil,
      arrange_generation = 0,
      resize_timer = nil,
      resize_generation = 0,
      resize_active = false,
      pending_arrange = false,
      pending_save = false,
      insufficient_room = false,
    }
  end
  return Autocmds.sessions[id]
end

---@param timer uv.uv_timer_t?
local function stop_timer(timer)
  if not timer or timer:is_closing() then return end
  timer:stop()
  timer:close()
end

---@return integer
local function resize_delay()
  return (Autocmds.config and Autocmds.config.live_resize_debounce) or 250
end

---@return integer[]?
local function resized_windows()
  local event = vim.v.event
  if type(event) ~= 'table' or type(event.windows) ~= 'table' then return nil end
  return event.windows
end

---@param err any
---@return boolean
local function is_not_enough_room(err)
  return tostring(err):find('E36: Not enough room', 1, true) ~= nil
end

--- Run one pending arrangement if its tabpage is current and not resizing.
---@param tabpage integer
local function run_pending_arrange(tabpage)
  local session = session_for(tabpage)
  if not session.pending_arrange or session.resize_active then return end
  if not vim.api.nvim_tabpage_is_valid(tabpage) or vim.api.nvim_get_current_tabpage() ~= tabpage then return end

  stop_timer(session.arrange_timer)
  session.arrange_timer = nil
  session.pending_arrange = false
  local ok, err = pcall(Panel.arrange, Panel, Autocmds.registry)
  if not ok then
    if is_not_enough_room(err) then
      session.insufficient_room = true
      vim.notify(
        'layout.nvim: not enough room to arrange panels; will retry after resize or window close',
        vim.log.levels.WARN
      )
      return
    end
    session.pending_arrange = true
    error(err)
  end
  if
    session.pending_save
    and Autocmds.config
    and Autocmds.config.workspaces
    and Autocmds.config.workspaces.auto_save
  then
    Save.save(Autocmds.config)
    session.pending_save = false
  end
end

--- Return the configured event triggers, falling back to FileType.
---@private
---@return string[]
function Autocmds:events_from_config()
  if self.config and self.config.events and #self.config.events > 0 then return self.config.events end
  return { 'FileType' }
end

--- Request automatic placement, coalescing requests per tabpage.
---
--- Synchronous requests run immediately unless a resize stream is active. All
--- requests made during resizing remain pending and run once after quiet time.
---@private
---@param delay? integer
---@param synchronous? boolean
function Autocmds:schedule_arrange(delay, synchronous)
  if not self.registry then return end
  local tabpage = tab_id()
  local session = session_for(tabpage)
  if session.insufficient_room then return end
  session.pending_arrange = true
  session.arrange_generation = session.arrange_generation + 1
  stop_timer(session.arrange_timer)
  session.arrange_timer = nil

  if session.resize_active then return end
  if synchronous then
    run_pending_arrange(tabpage)
    return
  end

  local generation = session.arrange_generation
  session.arrange_timer = vim.defer_fn(function()
    session.arrange_timer = nil
    if session.arrange_generation ~= generation then return end
    run_pending_arrange(tabpage)
  end, delay ~= nil and delay or 50)
end

--- Mark a user resize stream active and restart its quiet-period timer.
---@param tabpage integer
local function continue_resize(tabpage)
  local session = session_for(tabpage)
  session.resize_active = true
  session.resize_generation = session.resize_generation + 1
  session.arrange_generation = session.arrange_generation + 1
  stop_timer(session.arrange_timer)
  stop_timer(session.resize_timer)
  session.arrange_timer = nil

  local generation = session.resize_generation
  session.resize_timer = vim.defer_fn(function()
    session.resize_timer = nil
    if session.resize_generation ~= generation then return end
    session.resize_active = false
    run_pending_arrange(tabpage)
  end, resize_delay())
end

--- Stop timers for a tab while preserving whether arrangement is pending.
---@param tabpage integer
local function suspend_tab(tabpage)
  local session = session_for(tabpage)
  stop_timer(session.arrange_timer)
  stop_timer(session.resize_timer)
  session.arrange_timer = nil
  session.resize_timer = nil
  session.arrange_generation = session.arrange_generation + 1
  session.resize_generation = session.resize_generation + 1
  session.resize_active = false
end

--- Remove timer state belonging to closed tabpages.
local function prune_tabs()
  for tabpage, session in pairs(Autocmds.sessions) do
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      stop_timer(session.arrange_timer)
      stop_timer(session.resize_timer)
      Autocmds.sessions[tabpage] = nil
    end
  end
  Size:prune_tabs()
end

--- Initialize and wire autocommands.
---@public
---@param registry Layout.Registry
---@param config Layout.Config
function Autocmds:setup(registry, config)
  for tabpage in pairs(self.sessions) do
    suspend_tab(tabpage)
  end
  self.sessions = {}
  self.registry = registry
  self.config = config
  Size:initialize_tab()
  self:wire()
end

--- Create the plugin autocommand group.
---@package
function Autocmds:wire()
  if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup) end
  self.augroup = vim.api.nvim_create_augroup('Layout', { clear = true })

  for _, event in ipairs(self:events_from_config()) do
    vim.api.nvim_create_autocmd(event, {
      group = self.augroup,
      callback = function(ev)
        if View:match_by_buf(ev.buf, vim.api.nvim_get_current_win()) then session_for().pending_save = true end
        self:schedule_arrange()
      end,
    })
  end

  -- Keep the immediate no-flicker path unless a resize stream owns geometry.
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = self.augroup,
    callback = function(ev)
      if not self.registry then return end
      local side = View:match_by_buf(ev.buf, vim.api.nvim_get_current_win())
      if side then
        session_for().pending_save = true
        self:schedule_arrange(0, true)
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = self.augroup,
    callback = function()
      local session = session_for()
      session.pending_save = true
      session.insufficient_room = false
      Size:mark_topology_changed()
      self:schedule_arrange(0)
    end,
  })

  vim.api.nvim_create_autocmd('WinNew', {
    group = self.augroup,
    callback = function()
      session_for().pending_save = true
      Size:mark_topology_changed()
      self:schedule_arrange(0)
    end,
  })

  vim.api.nvim_create_autocmd('DirChangedPre', {
    group = self.augroup,
    callback = function()
      if self.config and self.config.workspaces and self.config.workspaces.auto_save then Save.save(self.config) end
    end,
  })

  vim.api.nvim_create_autocmd('DirChanged', {
    group = self.augroup,
    callback = function()
      if self.config and self.config.workspaces and self.config.workspaces.auto_restore then
        Restore.restore(self.config, true)
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = self.augroup,
    callback = function()
      if self.config and self.config.workspaces and self.config.workspaces.auto_save then Save.save(self.config) end
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = self.augroup,
    callback = function()
      session_for().insufficient_room = false
      Size:mark_editor_resized()
      self:schedule_arrange(resize_delay())
    end,
  })

  vim.api.nvim_create_autocmd('WinResized', {
    group = self.augroup,
    callback = function()
      local tabpage = tab_id()
      local session = session_for(tabpage)
      local observation = Size:observe_resize(resized_windows(), session.resize_active)
      if observation == 'captured' then continue_resize(tabpage) end

      if Size:topology_changed() then
        Size:mark_topology_changed()
        self:schedule_arrange(0, true)
      end
    end,
  })

  vim.api.nvim_create_autocmd('TabLeave', {
    group = self.augroup,
    callback = function()
      suspend_tab(tab_id())
    end,
  })

  vim.api.nvim_create_autocmd('TabEnter', {
    group = self.augroup,
    callback = function()
      Size:initialize_tab()
      self:schedule_arrange(0)
    end,
  })

  vim.api.nvim_create_autocmd('TabClosed', {
    group = self.augroup,
    callback = function()
      prune_tabs()
    end,
  })
end

return Autocmds
