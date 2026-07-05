--- Utility functions: cwd-hash, window classification, side math.
---
--- Pure helpers with no business logic.

---@class Layout.Shared.Lib
local Lib = {}

--- Compute a stable hash for a working directory path.
---@public
---@param path string
---@return string
function Lib.cwd_hash(path)
  return vim.fn.sha256(path):sub(1, 12)
end

--- Classify a window as a tool window (belongs to a view) or editor.
--- Returns side name if tool, nil if editor/unmatched.
---@public
---@param winid integer
---@param bufnr? integer
---@return Layout.Side?
function Lib.win_side(winid, bufnr)
  bufnr = bufnr or vim.api.nvim_win_get_buf(winid)
  local ok, side = pcall(require('layout.entities.view').match_by_buf, bufnr)
  if ok and side then
    return side
  end
  return nil
end

return Lib
