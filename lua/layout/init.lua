--- Public entry point for layout.nvim.
---
--- Usage:
---   require('layout').setup({
---     left   = { size = 30, groups = {
---       { name = 'explorer', picker = { icon = '', key = 'e' },
---         views = { { name = 'filesystem', filter = ..., open = ... } } },
---     } },
---     right  = { size = 40, groups = {
---       { name = 'buffers', picker = { icon = '', key = 'b' },
---         views = { { name = 'buffers_view', filter = ..., open = ... } } },
---     } },
---     bottom = { size = 15, groups = {
---       { name = 'git', picker = { icon = '', key = 'g' },
---         views = { { name = 'git_status', filter = ..., open = ... } } },
---     } },
---   })
---
---   -- User keymap:
---   vim.keymap.set('n', '<leader>;', function()
---     require('layout').pick()
---   end, { desc = 'Layout: pick group' })

---@class Layout
---@field config Layout.Config?
---@field registry Layout.Registry?
local M = {
  config = nil,
  registry = nil,
}

--- Merge user opts with defaults, normalize into a registry, register
--- entities, and wire commands and autocmds.
--- Called automatically by lazy.nvim when `opts` is set on the plugin spec.
---@public
---@param opts? table
function M.setup(opts)
  M.registry = require('layout.setup').setup(opts)
  M.config = require('layout.shared.config').merge(opts)
end

--- Show available group keys, wait for a key press, then toggle the
--- matching group with side exclusivity.
---
--- When pick mode is active the statusline icons include their group
--- keys while the user decides.
---
--- Optionally accepts a refresh callback invoked before each redraw,
--- useful for external statusline plugins that need manual refresh.
---@public
---@param refresh? fun()
function M.pick(refresh)
  require('layout.features.pick').prompt(refresh)
end

--- Return a list of statusline-formatted strings for the given side,
--- one per declared group, with optional highlight and click regions.
--- Consume from statusline plugins (lualine, heirline, bufferline, etc.).
---@public
---@param side Layout.Side
---@return string[]
function M.get_statusline(side)
  return require('layout.features.statusline'):get_statusline(side)
end

---Toggle the configured icon rail globally.
---@public
---@return boolean enabled Whether the rail is visible after toggling.
function M.toggle_rail()
  return require('layout.features.rail'):toggle()
end

--- Enable or disable layout management for an already-managed buffer.
--- Disabling takes effect immediately for panel operations.
--- Re-enabling also arranges the buffer into its recorded panel.
---@public
---@param bufnr integer
---@param enabled boolean
---@return boolean updated Whether the buffer had layout metadata to update.
function M.set_buffer_enabled(bufnr, enabled)
  local info = vim.b[bufnr].layout
  if type(info) ~= 'table' then return false end

  info.enabled = enabled
  vim.b[bufnr].layout = info
  if enabled then require('layout.entities.panel'):arrange() end
  return true
end

return M
