--- JSON read/write of workspace state files.
---
--- Files are stored as <config.workspaces.dir>/<cwd-hash>.json.

local lib = require('layout.shared.lib')

---@class Layout.Shared.Store
local Store = {}

--- Resolve the file path for a given cwd and config.
---@private
---@param config Layout.Config
---@param cwd? string
---@return string
local function filepath(config, cwd)
  cwd = cwd or vim.fn.getcwd()
  local dir = config.workspaces and config.workspaces.dir or vim.fn.stdpath('data') .. '/layout'
  return dir .. '/' .. lib.cwd_hash(cwd) .. '.json'
end

--- Write workspace state to disk.
---@public
---@param config Layout.Config
---@param state table
---@param cwd? string
function Store.save(config, state, cwd)
  cwd = cwd or vim.fn.getcwd()
  local path = filepath(config, cwd)
  local dir = vim.fn.fnamemodify(path, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  state.cwd = cwd
  local encoded = vim.json.encode(state)
  if encoded then
    vim.fn.writefile(vim.split(encoded, '\n'), path)
  end
end

--- Load workspace state from disk.
---@public
---@param config Layout.Config
---@param cwd? string
---@return table?
function Store.load(config, cwd)
  cwd = cwd or vim.fn.getcwd()
  local path = filepath(config, cwd)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return nil
  end
  local ok, state = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok then
    return nil
  end
  return state
end

--- Delete the saved workspace for the current cwd.
---@public
---@param config Layout.Config
---@param cwd? string
function Store.forget(config, cwd)
  cwd = cwd or vim.fn.getcwd()
  local path = filepath(config, cwd)
  if vim.fn.filereadable(path) == 1 then
    os.remove(path)
  end
end

return Store
