--- User command definitions (Layout command with subcommands).
---
--- Registered during setup via vim.api.nvim_create_user_command.

local Group = require('layout.entities.group')
local Pick = require('layout.features.pick')
local Restore = require('layout.features.restore')
local Save = require('layout.features.save')
local Store = require('layout.shared.store')
local Toggle = require('layout.features.toggle')
local Constants = require('layout.shared.constants')

---@class Layout.Commands
---@field private config Layout.Config?
local Commands = {
  config = nil
}

---@type string[]
local SUBCOMMANDS = { 'toggle', 'close', 'pick', 'save', 'restore', 'forget' }

---@type table<string, string[]>
local SUBCOMPLETION = {
  close = Constants.sides,
}

--- Resolve a unique group name to its side.
---@private
---@param group_name string
---@return Layout.Side?
---@return boolean ambiguous
local function resolve_group_side(group_name)
  local found = nil
  for _, candidate in ipairs(Constants.sides) do
    if Group:get(candidate, group_name) ~= nil then
      if found then return nil, true end
      found = candidate
    end
  end
  return found, false
end

--- Collect all known group names.
---@private
---@return string[]
local function all_group_names()
  local names = {}
  for _, gname in Group:iter() do
    names[#names + 1] = gname
  end
  return names
end

--- Register all Layout commands.
---@public
---@param config Layout.Config
function Commands:setup(config)
  self.config = config

  vim.api.nvim_create_user_command('Layout', function(args)
    local fargs = args.fargs
    local sub = fargs[1]

    if sub == 'toggle' then
      local requested_side = fargs[3] and fargs[2] or nil
      local group_name = fargs[3] or fargs[2]
      if not group_name then
        vim.notify('[layout.nvim] Usage: Layout toggle [side] <group>', vim.log.levels.WARN)
        return
      end
      local side, ambiguous
      if requested_side then
        side = Group:get(requested_side, group_name) and requested_side or nil
      else
        side, ambiguous = resolve_group_side(group_name)
      end
      if side then
        Toggle.toggle_group(side, group_name)
        return
      end
      if ambiguous then
        vim.notify('[layout.nvim] Group exists on multiple sides; use: Layout toggle <side> ' .. group_name, vim.log.levels.WARN)
        return
      end
      vim.notify('[layout.nvim] Group not found: ' .. group_name, vim.log.levels.WARN)
    elseif sub == 'close' then
      local side = fargs[2]
      if not side or not Constants.side_set[side] then
        vim.notify('[layout.nvim] Usage: Layout close <left|right|bottom>', vim.log.levels.WARN)
        return
      end
      Toggle.close_panel(side)
    elseif sub == 'pick' then
      Pick.prompt()
    elseif sub == 'save' then
      if not self.config then return end
      Save.save(self.config)
      vim.notify('[layout.nvim] Workspace saved', vim.log.levels.INFO)
    elseif sub == 'restore' then
      if not self.config then return end
      Restore.restore(self.config)
      vim.notify('[layout.nvim] Workspace restored', vim.log.levels.INFO)
    elseif sub == 'forget' then
      if not self.config then return end
      Store.forget(self.config)
      vim.notify('[layout.nvim] Workspace forgotten', vim.log.levels.INFO)
    else
      vim.notify(
        '[layout.nvim] Usage: Layout {toggle|close|pick|save|restore|forget} [...]',
        vim.log.levels.WARN
      )
    end
  end, {
    nargs = '*',
    force = true,
    complete = function(arg_lead, cmdline)
      local words = vim
        .iter(vim.split(cmdline, '%s+'))
        :filter(function(w)
          return w ~= ''
        end)
        :totable()
      local word_count = #words
      local trailing_space = cmdline:sub(#cmdline) == ' '

      if word_count <= 1 or (word_count == 2 and not trailing_space) then
        -- Completing the subcommand
        return vim
          .iter(SUBCOMMANDS)
          :filter(function(cmd)
            return vim.startswith(cmd, arg_lead)
          end)
          :totable()
      end

      local sub = words[2]
      local static = SUBCOMPLETION[sub]
      if static then
        return vim
          .iter(static)
          :filter(function(c)
            return vim.startswith(c, arg_lead)
          end)
          :totable()
      end

      if sub == 'toggle' then
        if (word_count == 2 and trailing_space) or (word_count == 3 and not trailing_space) then
          local candidates = vim.list_extend(vim.deepcopy(Constants.sides), all_group_names())
          return vim.iter(candidates):filter(function(n) return vim.startswith(n, arg_lead) end):totable()
        end
        local side = words[3]
        if Constants.side_set[side] then
          return vim.iter(Group:list(side)):filter(function(n) return vim.startswith(n, arg_lead) end):totable()
        end
        return vim
          .iter(all_group_names())
          :filter(function(n)
            return vim.startswith(n, arg_lead)
          end)
          :totable()
      end

      return {}
    end,
  })
end

return Commands
