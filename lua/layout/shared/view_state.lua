--- Stable editor view tracking across window topology changes.

---@class Layout.Shared.ViewState.View
---@field bufnr integer
---@field view table

---@class Layout.Shared.ViewState.Session
---@field windows table<integer, boolean>
---@field views table<integer, Layout.Shared.ViewState.View>

---@class Layout.Shared.ViewState
---@field private sessions table<integer, Layout.Shared.ViewState.Session>
---@field private augroup integer?
local ViewState = {
  sessions = {},
  augroup = nil,
}

---@private
---@param tabpage integer
---@return table<integer, boolean>
local function normal_windows(tabpage)
  local windows = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_get_config(winid).relative == '' then windows[winid] = true end
  end
  return windows
end

---@private
---@param left table<integer, boolean>
---@param right table<integer, boolean>
---@return boolean
local function same_windows(left, right)
  for winid in pairs(left) do
    if not right[winid] then return false end
  end
  for winid in pairs(right) do
    if not left[winid] then return false end
  end
  return true
end

---@private
---@param winid integer
---@return boolean
local function is_editor_window(winid)
  if not vim.api.nvim_win_is_valid(winid) then return false end
  if vim.api.nvim_win_get_config(winid).relative ~= '' then return false end
  local has_managed, managed = pcall(vim.api.nvim_win_get_var, winid, 'layout_managed')
  if has_managed and managed then return false end
  return vim.bo[vim.api.nvim_win_get_buf(winid)].buftype ~= 'terminal'
end

---@private
---@param winid integer
---@return Layout.Shared.ViewState.View?
local function capture_view(winid)
  if not is_editor_window(winid) then return nil end
  local ok, view = pcall(vim.api.nvim_win_call, winid, vim.fn.winsaveview)
  if not ok then return nil end
  return { bufnr = vim.api.nvim_win_get_buf(winid), view = view }
end

---@private
---@param tabpage integer
---@return table<integer, Layout.Shared.ViewState.View>
local function capture_views(tabpage)
  local views = {}
  for winid in pairs(normal_windows(tabpage)) do
    local view = capture_view(winid)
    if view then views[winid] = view end
  end
  return views
end

---@private
---@param tabpage integer
---@return Layout.Shared.ViewState.Session
function ViewState:initialize(tabpage)
  local session = {
    windows = normal_windows(tabpage),
    views = capture_views(tabpage),
  }
  self.sessions[tabpage] = session
  return session
end

--- Return the last stable editor views, refreshing them only while the normal
--- window set is unchanged. A new split therefore freezes the pre-split view.
---@public
---@param tabpage? integer
---@return table<integer, Layout.Shared.ViewState.View>
function ViewState:save(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local session = self.sessions[tabpage]
  local windows = normal_windows(tabpage)
  if not session then
    session = self:initialize(tabpage)
  elseif same_windows(session.windows, windows) then
    session.windows = windows
    session.views = capture_views(tabpage)
  end
  return vim.deepcopy(session.views)
end

--- Restore a stable snapshot to surviving editor windows, then accept the new
--- topology as the baseline for subsequent cursor and scroll updates.
---@public
---@param views table<integer, Layout.Shared.ViewState.View>
---@param tabpage? integer
function ViewState:restore(views, tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(tabpage) then return end
  for winid, state in pairs(views) do
    if
      is_editor_window(winid)
      and vim.api.nvim_win_get_tabpage(winid) == tabpage
      and vim.api.nvim_win_get_buf(winid) == state.bufnr
    then
      pcall(vim.api.nvim_win_call, winid, function()
        vim.fn.winrestview(state.view)
      end)
    end
  end
  self:initialize(tabpage)
end

--- Refresh one editor view only when its tabpage topology is still stable.
---@public
---@param winid? integer
function ViewState:update(winid)
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then return end
  local tabpage = vim.api.nvim_win_get_tabpage(winid)
  local session = self.sessions[tabpage]
  if not session then
    self:initialize(tabpage)
    return
  end
  if not same_windows(session.windows, normal_windows(tabpage)) then return end
  local view = capture_view(winid)
  if view then
    session.views[winid] = view
  else
    session.views[winid] = nil
  end
end

--- Start lightweight tracking of user-driven cursor and viewport changes.
---@public
function ViewState:setup()
  self.sessions = {}
  self:initialize(vim.api.nvim_get_current_tabpage())
  if self.augroup then pcall(vim.api.nvim_del_augroup_by_id, self.augroup) end
  self.augroup = vim.api.nvim_create_augroup('LayoutViewState', { clear = true })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = self.augroup,
    callback = function()
      self:update()
    end,
  })
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = self.augroup,
    callback = function()
      self:save()
    end,
  })
end

return ViewState
