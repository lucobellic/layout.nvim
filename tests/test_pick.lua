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

  it('clears pick mode when reading input fails', function()
    -- Given: the input provider raises while pick mode is active
    U.setup_config(child, U.test_config({
      left = { groups = { explorer = { picker = { key = 'e' } } } },
    }))
    child.lua([[vim.fn.getcharstr = function() error('input interrupted') end]])

    -- When: the picker attempts to read input
    child.lua([[_G._prompt_ok = pcall(require('layout.features.pick').prompt)]])

    -- Then: the error propagates but transient UI state is cleaned up
    expect.equality(child.lua_get([[_G._prompt_ok]]), false)
    expect.equality(child.lua_get([[require('layout.features.statusline').pick_mode]]), false)
  end)

  describe('Shared picker keys', function()
    it('opens every group sharing a key', function()
      -- Given: closed groups in every panel share the key "d".
      U.setup_config(child, U.test_config({
        left = {
          groups = {
            debug = {
              picker = { key = 'd' },
              views = {
                left_tool = {
                  filter = 'dev66_left',
                  open = "let g:dev66_left_opened = get(g:, 'dev66_left_opened', 0) + 1 | belowright split | enew | setfiletype dev66_left",
                },
              },
            },
          },
        },
        right = {
          groups = {
            debug = {
              picker = { key = 'd' },
              views = {
                right_tool = { filter = 'dev66_right' },
              },
            },
          },
        },
        bottom = {
          groups = {
            debug = {
              picker = { key = 'd' },
              views = {
                bottom_tool = {
                  filter = 'dev66_bottom',
                  open = "let g:dev66_bottom_opened = get(g:, 'dev66_bottom_opened', 0) + 1 | belowright split | enew | setfiletype dev66_bottom",
                },
              },
            },
          },
        },
      }))
      child.lua([[vim.fn.getcharstr = function() return 'd' end]])

      -- When: the picker receives the shared key.
      child.lua([[require('layout.features.pick').prompt()]])
      child.lua([[vim.wait(100, function() return false end)]])

      -- Then: every matching group opens and each configured command runs.
      expect.equality(child.lua_get([[vim.g.dev66_left_opened]]), 1)
      expect.equality(child.lua_get([[vim.g.dev66_bottom_opened]]), 1)
      expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('left', 'debug')]]), true)
      expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('right', 'debug')]]), true)
      expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('bottom', 'debug')]]), true)
    end)

    it('closes every group sharing a key', function()
      -- Given: the shared groups are open, including one without an open command.
      U.setup_config(child, U.test_config({
        left = {
          groups = {
            debug = {
              picker = { key = 'd' },
              views = {
                left_tool = {
                  filter = 'dev66_left',
                  open = 'belowright split | enew | setfiletype dev66_left',
                },
              },
            },
          },
        },
        right = {
          groups = {
            debug = {
              picker = { key = 'd' },
              views = {
                right_tool = { filter = 'dev66_right' },
              },
            },
          },
        },
        bottom = {
          groups = {
            debug = {
              picker = { key = 'd' },
              views = {
                bottom_tool = {
                  filter = 'dev66_bottom',
                  open = 'belowright split | enew | setfiletype dev66_bottom',
                },
              },
            },
          },
        },
      }))
      child.lua([[vim.fn.getcharstr = function() return 'd' end]])
      child.lua([[require('layout.features.pick').prompt()]])
      child.lua([[vim.wait(100, function() return false end)]])

      -- When: the same key is pressed again.
      child.lua([[require('layout.features.pick').prompt()]])

      -- Then: all groups close, including the group with no open command.
      expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('left', 'debug')]]), false)
      expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('right', 'debug')]]), false)
      expect.equality(child.lua_get([[require('layout.entities.workspace'):is_open('bottom', 'debug')]]), false)
      expect.equality(child.lua_get([[
        vim.iter(vim.api.nvim_tabpage_list_wins(0)):any(function(winid)
          local ft = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
          return ft == 'dev66_left' or ft == 'dev66_bottom'
        end)
      ]]), false)
    end)
  end)
end)
