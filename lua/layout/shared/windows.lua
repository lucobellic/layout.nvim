---Shared normal-window topology helpers.

---@class Layout.Shared.Windows
local Windows = {}

---Return the non-floating window set for a tabpage.
---@public
---@param tabpage? integer
---@return table<integer, boolean>
function Windows.normal_set(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local windows = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_get_config(winid).relative == '' then windows[winid] = true end
  end
  return windows
end

---Return whether two window sets contain the same handles.
---@public
---@param left table<integer, boolean>
---@param right table<integer, boolean>
---@return boolean
function Windows.same_set(left, right)
  for winid in pairs(left) do
    if not right[winid] then return false end
  end
  for winid in pairs(right) do
    if not left[winid] then return false end
  end
  return true
end

return Windows
