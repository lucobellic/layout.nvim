--- Health diagnostics for the layout health command.

local Config = require('layout.shared.config')
local Constants = require('layout.shared.constants')
local Group = require('layout.entities.group')
local View = require('layout.entities.view')

---@class Layout.Health
local Health = {}

---@param major integer
---@param minor integer
---@return boolean
local function version_at_least(major, minor)
  local version = vim.version()
  return version.major > major or (version.major == major and version.minor >= minor)
end

---@param registry Layout.Registry
---@return integer groups
---@return integer views
local function registry_counts(registry)
  local groups = 0
  local views = 0
  for _, side in ipairs(Constants.sides) do
    local side_entry = registry[side]
    if side_entry then
      groups = groups + #(side_entry._order or {})
      for _, group_name in ipairs(side_entry._order or {}) do
        local group = side_entry.groups and side_entry.groups[group_name]
        if group then views = views + #(group._order or {}) end
      end
    end
  end
  return groups, views
end

---@param path string
---@return string?
local function existing_parent(path)
  local current = vim.fn.fnamemodify(path, ':p:h')
  while current ~= '' and vim.fn.isdirectory(current) == 0 do
    local parent = vim.fn.fnamemodify(current, ':h')
    if parent == current then return nil end
    current = parent
  end
  return current ~= '' and current or nil
end

---@return Layout.Config? config
local function check_setup()
  vim.health.start('Configuration')
  local Layout = require('layout')
  local config = Layout.config
  local registry = Layout.registry
  if type(config) ~= 'table' or type(registry) ~= 'table' then
    vim.health.error(
      'setup() has not been called',
      'Call require("layout").setup({...}) from your plugin configuration.'
    )
    return nil
  end
  ---@cast config Layout.Config
  ---@cast registry Layout.Registry

  local merged_ok, merged = pcall(Config.merge, config)
  local normalized_ok = false
  ---@type Layout.Registry?
  local normalized = nil
  if merged_ok then
    normalized_ok, normalized = pcall(Config.normalize, merged)
  end
  if not merged_ok or not normalized_ok then
    vim.health.error('The active configuration is invalid', tostring(merged_ok and normalized or merged))
    return nil
  end
  ---@cast normalized Layout.Registry

  local expected_groups, expected_views = registry_counts(normalized)
  local groups, views = registry_counts(registry)
  if groups == 0 then
    vim.health.warn('No layout groups are configured')
  else
    vim.health.ok(('%d group(s) and %d view(s) are configured'):format(groups, views))
  end

  local registered_groups = 0
  for _ in Group:iter() do
    registered_groups = registered_groups + 1
  end
  if
    groups == expected_groups
    and views == expected_views
    and registered_groups == groups
    and #View.entries == views
  then
    vim.health.ok('The group and view registries are synchronized with the active configuration')
  else
    vim.health.error(
      ('The runtime registries are out of sync: expected %d group(s)/%d view(s), found %d/%d configured and %d/%d registered'):format(
        expected_groups,
        expected_views,
        groups,
        views,
        registered_groups,
        #View.entries
      ),
      'Rerun require("layout").setup({...}) after changing the configuration.'
    )
  end
  return config
end

---@param config Layout.Config
local function check_storage(config)
  vim.health.start('Workspace persistence')
  local workspaces = config.workspaces
  if type(workspaces) ~= 'table' or type(workspaces.dir) ~= 'string' or workspaces.dir == '' then
    vim.health.error('Workspace storage directory is not configured')
    return
  end

  if not workspaces.auto_save and not workspaces.auto_restore then
    vim.health.info('Automatic workspace saving and restoration are disabled')
  end

  local path_type = vim.fn.getftype(workspaces.dir)
  if path_type ~= '' and path_type ~= 'dir' then
    vim.health.error(('Workspace path is not a directory: %s'):format(workspaces.dir))
    return
  end

  if path_type == 'dir' then
    if vim.fn.filewritable(workspaces.dir) == 2 then
      vim.health.ok(('Workspace directory is writable: %s'):format(workspaces.dir))
    else
      vim.health.error(('Workspace directory is not writable: %s'):format(workspaces.dir))
    end
    return
  end

  local parent = existing_parent(workspaces.dir)
  if parent and vim.fn.filewritable(parent) == 2 then
    vim.health.ok(('Workspace directory will be created under writable path: %s'):format(parent))
  else
    vim.health.error(
      ('Workspace directory cannot be created: %s'):format(workspaces.dir),
      'Configure workspaces.dir beneath an existing writable directory.'
    )
  end
end

local function check_windows()
  vim.health.start('Current tabpage')
  local matched = {}
  local problems = {}
  local count = 0

  for match in View:iter_matches(nil, true) do
    matched[match.winid] = true
    count = count + 1
    local info = vim.b[match.bufnr].layout
    local has_managed, managed = pcall(vim.api.nvim_win_get_var, match.winid, 'layout_managed')
    local has_slot, slot = pcall(vim.api.nvim_win_get_var, match.winid, 'layout_slot')
    local prefix = ({ left = 'L', right = 'R', bottom = 'B' })[match.side]
    local metadata_ok = type(info) == 'table'
      and info.enabled == true
      and info.side == match.side
      and info.group == match.group
      and info.view == match.name
    local slot_ok = has_slot and type(slot) == 'string' and slot:match('^' .. prefix .. '%d+$') ~= nil
    if not metadata_ok or not has_managed or managed ~= true or not slot_ok then
      problems[#problems + 1] = ('window %d (%s/%s/%s)'):format(match.winid, match.side, match.group, match.name)
    end
  end

  for winid in pairs(require('layout.shared.windows').normal_set()) do
    local has_managed, managed = pcall(vim.api.nvim_win_get_var, winid, 'layout_managed')
    local has_slot, slot = pcall(vim.api.nvim_win_get_var, winid, 'layout_slot')
    if has_managed and managed == true and has_slot and slot ~= 'Q' and not matched[winid] then
      problems[#problems + 1] = ('window %d is tagged as managed but matches no configured view'):format(winid)
    end
  end

  if #problems > 0 then
    vim.health.warn(
      ('%d window(s) have inconsistent layout metadata: %s'):format(#problems, table.concat(problems, '; ')),
      'Reopen the affected views or rerun require("layout").setup({...}).'
    )
  elseif count == 0 then
    vim.health.info('No configured views are open in the current tabpage')
  else
    vim.health.ok(('%d managed window(s) have consistent metadata'):format(count))
  end
end

--- Run all layout.nvim health checks.
---@public
function Health.check()
  vim.health.start('Environment')
  local version = vim.version()
  if version_at_least(0, 10) then
    vim.health.ok(('Neovim %d.%d.%d is supported'):format(version.major, version.minor, version.patch))
  else
    vim.health.error(
      ('Neovim %d.%d.%d is unsupported; layout.nvim requires Neovim 0.10 or newer'):format(
        version.major,
        version.minor,
        version.patch
      )
    )
  end

  local config = check_setup()
  if not config then return end
  check_storage(config)
  check_windows()
end

return Health
