local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

describe('insufficient room', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
    child.lua([[
      _G._notifications = {}
      ---@param message string
      vim.notify = function(message)
        table.insert(_G._notifications, message)
      end
    ]])
  end)

  after_each(function()
    child.stop()
  end)

  ---@param with_openers? boolean
  ---@return table
  local function config(with_openers)
    local views = {}
    for _, name in ipairs({ 'first', 'second', 'third' }) do
      views[name] = {
        filter = 'room_' .. name,
        open = with_openers and (
          'vsplit | enew | lua local buffer = vim.api.nvim_get_current_buf(); '
          .. 'vim.schedule(function() vim.bo[buffer].filetype = "room_%s" end)'
        ):format(name) or nil,
      }
    end
    return U.test_config({
      left = { size = 30, groups = { tools = { picker = { key = 't' }, views = views } } },
    })
  end

  ---@return table<string, integer> windows
  ---@return table<string, integer> buffers
  local function prepare_views()
    local windows, buffers = U.make_scattered(child, { 'editor', 'first', 'second', 'third' })
    U.setup_config(child, config())
    for _, name in ipairs({ 'first', 'second', 'third' }) do
      child.api.nvim_set_option_value('filetype', 'room_' .. name, { buf = buffers[name] })
    end
    return windows, buffers
  end

  local function expect_silence()
    expect.equality(child.lua_get([[_G._notifications]]), {})
    expect.equality(child.api.nvim_exec2('messages', { output = true }).output, '')
  end

  it('silently aborts a real split move failure and retries after the editor grows', function()
    -- Given: three panel views cannot stack inside a three row editor
    local windows, buffers = prepare_views()
    child.o.lines = 3
    child.o.equalalways = true
    child.o.splitright = false
    child.o.splitbelow = false
    child.o.splitkeep = 'cursor'
    child.o.eventignore = 'BufEnter'
    child.api.nvim_set_option_value('winfixwidth', true, { win = windows.first })
    child.api.nvim_set_option_value('winfixheight', true, { win = windows.second })
    child.lua([[
      _G._saved_options = {}
      for _, name in ipairs({ 'equalalways', 'splitright', 'splitbelow', 'splitkeep',
        'winminwidth', 'winminheight', 'eventignore' }) do
        _G._saved_options[name] = vim.api.nvim_get_option_value(name, {})
      end
    ]])
    local saved_options = child.lua_get([[_G._saved_options]])
    child.cmd('messages clear')

    -- When: Neovim rejects a native win_splitmove during arrangement
    child.lua([[_G._completed = require('layout.entities.panel'):arrange(_G._reg)]])

    -- Then: failure is silent and temporary options and windows survive
    expect.equality(child.lua_get([[_G._completed]]), false)
    expect.equality(child.lua_get([[require('layout.entities.panel.model.size'):topology_changed()]]), true)
    expect_silence()
    for name, value in pairs(saved_options) do
      expect.equality(child.api.nvim_get_option_value(name, {}), value)
    end
    for name, window in pairs(windows) do
      expect.equality(child.api.nvim_win_is_valid(window), true)
      expect.equality(child.api.nvim_win_get_buf(window), buffers[name])
      expect.equality(child.api.nvim_get_option_value('winfixwidth', { win = window }), name == 'first')
      expect.equality(child.api.nvim_get_option_value('winfixheight', { win = window }), name == 'second')
    end

    -- When: the editor has room again
    child.o.lines = 41
    child.lua([[_G._completed = require('layout.entities.panel'):arrange(_G._reg)]])

    -- Then: the transaction was released and the configured layout can settle
    expect.equality(child.lua_get([[_G._completed]]), true)
    expect.equality(child.lua_get([[require('layout.entities.panel.model.size'):topology_changed()]]), false)
    expect.equality(child.api.nvim_win_get_width(windows.first), 30)
    expect.equality(U.slots_by_tag(child).L3, windows.third)
    expect_silence()
  end)

  it('keeps both immediate and scheduled picker placement failures silent', function()
    -- Given: view filters appear later and the editor cannot stack all views
    U.prepare(child)
    U.setup_config(child, config(true))
    child.o.lines = 3
    child.lua([[
      ---@return string
      vim.fn.getcharstr = function() return 't' end
      local Panel = require('layout.entities.panel')
      local arrange = Panel.arrange
      _G._arrange_attempts = 0
      ---@param self Layout.Entity.Panel
      ---@param ... any
      ---@return boolean?
      Panel.arrange = function(self, ...)
        _G._arrange_attempts = _G._arrange_attempts + 1
        return arrange(self, ...)
      end
    ]])
    child.cmd('messages clear')

    -- When: the picker opens the group and deferred filters trigger another pass
    child.lua([[require('layout.features.pick').prompt(); vim.wait(100)]])

    -- Then: neither pass emits an error and the open windows remain available
    expect.equality(child.lua_get([[_G._arrange_attempts >= 2]]), true)
    expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('left', 'tools')]]), true)
    expect.equality(#child.api.nvim_tabpage_list_wins(0), 4)
    expect_silence()
  end)

  for _, operation in ipairs({ 'center creation', 'resizing' }) do
    it('silently handles insufficient room during ' .. operation, function()
      -- Given: another placement operation can also report E36
      if operation == 'center creation' then
        U.prepare(child)
        U.setup_config(child, config())
        U.make_tool_win(child, 'room_first')
      else
        prepare_views()
      end
      child.lua(
        [[
        local operation = ...
        local name = operation == 'center creation' and 'nvim_open_win'
          or (vim.api.nvim_win_resize and 'nvim_win_resize' or 'nvim_win_set_config')
        vim.api[name] = function() error('Vim:E36: Not enough room') end
      ]],
        { operation }
      )
      child.cmd('messages clear')

      -- When: placement reaches that operation
      child.lua([[_G._completed = require('layout.entities.panel'):arrange(_G._reg)]])

      -- Then: the failure is silent and the transaction remains retryable
      expect.equality(child.lua_get([[_G._completed]]), false)
      expect.equality(child.lua_get([[require('layout.entities.panel.model.size'):topology_changed()]]), true)
      expect_silence()
    end)
  end

  for _, opener in ipairs({ 'command', 'function' }) do
    it('silently handles insufficient room in a view open ' .. opener, function()
      -- Given: the view opener cannot create its native split
      U.prepare(child)
      U.setup_config(
        child,
        U.test_config({
          left = {
            groups = {
              tools = {
                picker = { key = 't' },
                views = {
                  first = { filter = 'room_first', open = 'split' },
                },
              },
            },
          },
        })
      )
      child.o.lines = 3
      child.o.winheight = 2
      child.o.winminheight = 2
      child.lua(
        [[
        if ... == 'function' then
          require('layout.entities.group'):views_for('left', 'tools').first.open = function()
            vim.cmd('split')
          end
        end
        ---@return string
        vim.fn.getcharstr = function() return 't' end
      ]],
        { opener }
      )
      child.cmd('messages clear')

      -- When: the picker runs the opener
      child.lua([[require('layout.features.pick').prompt(); vim.wait(50)]])

      -- Then: there is no notification or error from the failed open
      expect.equality(#child.api.nvim_tabpage_list_wins(0), 1)
      expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('left', 'tools')]]), false)
      expect_silence()
    end)
  end

  it('still propagates unrelated placement errors', function()
    -- Given: a split move fails for a reason other than E36
    prepare_views()
    child.lua([[
      vim.fn.win_splitmove = function() error('unrelated E360: Not enough room') end
    ]])

    -- When: the panel is arranged
    child.lua([[
      _G._completed, _G._error = pcall(function()
        require('layout.entities.panel'):arrange(_G._reg)
      end)
    ]])

    -- Then: the error is still available to the caller
    expect.equality(child.lua_get([[_G._completed]]), false)
    expect.equality(child.lua_get([[_G._error:find('unrelated E360:', 1, true) ~= nil]]), true)
  end)
end)
