--- tests/test_pick.lua
--- BDD tests for the group picker input handling.

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

describe('features.pick', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  it('cancels picker silently when Escape is pressed', function()
    -- Given: pick mode is active and Escape is returned by getcharstr()
    U.setup_config(child, U.test_config({
      left = {
        groups = {
          explorer = { picker = { key = 'e' } },
        },
      },
    }))
    child.lua([[vim.fn.getcharstr = function() return '\27' end]])
    child.lua([[vim.notify = function(message) _G._notification = message end]])

    -- When: the picker waits for input
    child.lua([[require('layout.features.pick').prompt()]])

    -- Then: pick mode is disabled without toggling or warning
    expect.equality(child.lua_get([[require('layout.features.statusline').pick_mode]]), false)
    expect.equality(child.lua_get([[_G._notification]]), vim.NIL)
    expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('left', 'explorer')]]), false)
  end)

  it('still toggles the group mapped to a pressed key', function()
    -- Given: a group is registered with the key "e"
    U.setup_config(child, U.test_config({
      left = {
        groups = {
          explorer = { picker = { key = 'e' } },
        },
      },
    }))
    child.lua([[vim.fn.getcharstr = function() return 'e' end]])
    child.lua([[
      local Pick = require('layout.features.pick')
      Pick.pick = function(side, name) _G._picked = { side = side, name = name } end
    ]])

    -- When: the picker receives the mapped key
    child.lua([[require('layout.features.pick').prompt()]])

    -- Then: the matching group is dispatched
    expect.equality(child.lua_get([[_G._picked]]), { side = 'left', name = 'explorer' })
  end)
end)
