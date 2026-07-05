--- Autocommand wiring — detects tool buffers and triggers panel arrangement.
---
--- The events that trigger re-evaluation are declared globally in the
--- top-level `events` config key
--- Each event serves as a *trigger*:
--- when it fires, layout.nvim debounces and then re-scans all windows,
--- running each view's `filter(buf, win)` to classify ownership.
---
--- This two-phase design (event → trigger, filter → matcher)
--- means the timing of buffer option availability is the user's concern,
--- expressed through their choice of `events`, not a hardcoded assumption in the plugin.
---
--- On WinClosed: auto-save workspace state.
--- On DirChanged / VimEnter: auto-restore workspace.
--- On VimResized: debounced size capture.

local Panel = require('layout.entities.panel')
local Restore = require('layout.features.restore')
local Save = require('layout.features.save')
local Size = require('layout.entities.panel.model.size')
local View = require('layout.entities.view')

---@class Layout.Autocmds
---@field private registry Layout.Registry?
---@field private config Layout.Config?
---@field private augroup number?
---@field private debounce_timer number?
---@field private seen_wins table<integer, boolean> Snapshot of the last non-floating window set used to detect topology changes that produced no WinNew/WinClosed autocmds.
local Autocmds = {
  registry = nil,
  config = nil,
  augroup = nil,
  debounce_timer = nil,
  seen_wins = {},
}

--- Snapshot the current non-floating window set.
---@private
---@return table<integer, boolean>
local function current_win_set()
  local wins = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(winid).relative == '' then wins[winid] = true end
  end
  return wins
end

--- Return whether the window topology changed since the last call, and
--- refresh the snapshot.
---
--- Plugins commonly create their windows under `eventignore=all`
--- (e.g. trouble.nvim mounts its split inside a noautocmd wrapper),
--- so WinNew/WinClosed never fire for them.
---
--- Diffing the window set on WinResized, which is triggered
--- from the main loop after eventignore is restored, before the next redraw,
--- is the only reliable detection point.
---@private
---@return boolean
function Autocmds.wins_topology_changed()
  local current = current_win_set()
  local changed = false
  for winid in pairs(current) do
    if not Autocmds.seen_wins[winid] then
      changed = true
      break
    end
  end
  if not changed then
    for winid in pairs(Autocmds.seen_wins) do
      if not current[winid] then
        changed = true
        break
      end
    end
  end
  Autocmds.seen_wins = current
  return changed
end

--- Return the global events list from the config, falling back to `{"FileType"}`.
---@private
---@return string[]
function Autocmds:events_from_config()
  if self.config and self.config.events and #self.config.events > 0 then return self.config.events end
  return { 'FileType' }
end

--- Schedule a panel arrangement, coalescing triggers within the delay.
--- View-detection events use the default debounce; window lifecycle events
--- use a zero delay so geometry is corrected before a visible redraw.
---@private
---@param delay? integer
function Autocmds:schedule_arrange(delay)
  if not self.registry then return end
  if self.debounce_timer then vim.fn.timer_stop(self.debounce_timer) end
  self.debounce_timer = vim.fn.timer_start(delay or 50, function()
    self.debounce_timer = nil
    vim.schedule(function()
      Panel:arrange(self.registry)
    end)
  end)
end

---@public
---@param registry Layout.Registry
---@param config Layout.Config
function Autocmds:setup(registry, config)
  self.registry = registry
  self.config = config
  self.seen_wins = current_win_set()
  Autocmds:wire()
end

--- Create autocommand groups.
---@package
function Autocmds:wire()
  if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup) end
  self.augroup = vim.api.nvim_create_augroup('Layout', { clear = true })

  -- View-detection events: declared globally in the `events` config key.
  local events = self:events_from_config()
  vim.iter(events):each(function(event)
    vim.api.nvim_create_autocmd(event, {
      group = self.augroup,
      callback = function()
        self:schedule_arrange()
      end,
    })
  end)

  -- Synchronous placement for already-classifiable buffers.
  --
  -- Autocmd callbacks run before the next redraw,
  -- so arranging here moves a freshly shown tool window into its panel
  -- without a visible intermediate frame.
  --
  -- Buffers the filters cannot classify yet (e.g. deferred filetype)
  -- fall back to the debounced detection events above.
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = self.augroup,
    callback = function(ev)
      if not self.registry then return end
      local side = View:match_by_buf(ev.buf, vim.api.nvim_get_current_win())
      if not side then return end
      if self.debounce_timer then
        vim.fn.timer_stop(self.debounce_timer)
        self.debounce_timer = nil
      end
      Panel:arrange(self.registry)
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = self.augroup,
    callback = function()
      Size:mark_topology_changed()
      self:schedule_arrange(0)
      if self.config then Save.save(self.config) end
    end,
  })

  vim.api.nvim_create_autocmd('WinNew', {
    group = self.augroup,
    callback = function()
      Size:mark_topology_changed()
      self:schedule_arrange(0)
    end,
  })

  vim.api.nvim_create_autocmd('DirChanged', {
    group = self.augroup,
    callback = function()
      if self.config and self.config.workspaces then
        if self.config.workspaces.auto_restore then Restore.restore(self.config) end
        if self.config.workspaces.auto_save then Save.save(self.config) end
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = self.augroup,
    callback = function()
      Size:update_live_debounced(self.config and self.config.live_resize_debounce or 250)
    end,
  })

  vim.api.nvim_create_autocmd('WinResized', {
    group = self.augroup,
    callback = function()
      -- Always diff the window set so the snapshot stays fresh, even
      -- when the WinNew/WinClosed flag already marked the topology dirty.
      local wins_changed = Autocmds.wins_topology_changed()
      if self.registry and wins_changed then
        Size:mark_topology_changed()
        if Autocmds.debounce_timer then
          vim.fn.timer_stop(Autocmds.debounce_timer)
          Autocmds.debounce_timer = nil
        end
        Panel:arrange(self.registry)
      else
        -- A prior lifecycle event may have set the dirty flag even though its
        -- topology has since been observed. This resize has no new topology,
        -- so it is safe to resume live-size capture without reading collateral
        -- dimensions from that earlier event.
        if Size:topology_changed() then Size:settle_topology() end
        Size:update_live_debounced(self.config and self.config.live_resize_debounce or 250)
      end
    end,
  })
end

return Autocmds
