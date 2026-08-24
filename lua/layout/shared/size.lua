--- Shared size validation and resolution for panels and views.

---@class Layout.Shared.Size
local Size = {}

--- Return whether a size is relative to its container.
---@public
---@param size Layout.Size
---@return boolean
function Size.is_relative(size)
  return type(size) == 'number' and size > 0 and size < 1
end

--- Validate a panel or view size.
---@public
---@param size Layout.Size
---@param context? string
---@return Layout.Size
function Size.validate(size, context)
  local valid_number = type(size) == 'number' and size == size and size ~= math.huge and size ~= -math.huge
  local valid_fraction = valid_number and size > 0 and size < 1
  local valid_absolute = valid_number and size >= 1 and math.floor(size) == size
  if not valid_fraction and not valid_absolute then
    error(
      ('%s must be a fraction between 0 and 1 or a positive integer (got %s)'):format(
        context or 'size',
        vim.inspect(size)
      )
    )
  end
  return size
end

--- Resolve a size against its container dimension.
---@public
---@param size Layout.Size
---@param container integer
---@return integer
function Size.resolve(size, container)
  Size.validate(size)
  if not Size.is_relative(size) then return size end
  return math.max(1, math.floor(size * container))
end

--- Convert an observed dimension into a valid fraction of its container.
--- Transient zero and oversized dimensions are clamped to representable values.
---@public
---@param dimension integer
---@param container integer
---@return number
function Size.to_fraction(dimension, container)
  container = math.max(1, container)
  if container == 1 then return 0.5 end
  return math.min(math.max(1, dimension), container - 1) / container
end

--- Return the dimensions occupied by the current normal-window editor grid.
---@public
---@return integer width
---@return integer height
function Size.editor_dimensions()
  local height = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      local row = vim.api.nvim_win_get_position(win)[1]
      height = math.max(height, row + vim.api.nvim_win_get_height(win))
    end
  end
  return vim.o.columns, math.max(1, height)
end

return Size
