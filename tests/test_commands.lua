--- BDD tests for user-command group resolution.

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

describe('Layout command', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  it('requires a side when a group name exists on multiple sides', function()
    -- Given: two groups share a name but have distinct open commands
    local cfg = U.test_config({
      left = {
        groups = { debug = { views = { left = { filter = 'left-tool', open = 'let g:left_opened = 1' } } } },
      },
      right = {
        groups = { debug = { views = { right = { filter = 'right-tool', open = 'let g:right_opened = 1' } } } },
      },
    })
    child.lua('_G._command_cfg = ' .. vim.inspect(cfg))
    child.lua([[require('layout').setup(_G._command_cfg)]])
    child.lua([[vim.notify = function(message) _G._command_notice = message end]])

    -- When: the ambiguous shorthand is used, followed by an explicit side
    child.cmd('Layout toggle debug')
    child.cmd('Layout toggle right debug')

    -- Then: ambiguity is reported and only the requested side is opened
    expect.equality(child.lua_get([[_G._command_notice:match('multiple sides') ~= nil]]), true)
    expect.equality(child.lua_get([[vim.g.left_opened]]), vim.NIL)
    expect.equality(child.lua_get([[vim.g.right_opened]]), 1)
  end)
end)
