--- tests/test_statusline.lua
--- Unit tests for features/statusline and shared/ui modules.
---
--- Statusline rendering tests run in a child Neovim process (need windows).
--- Highlight group tests run in the main process.

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

local function nwins(child)
  return #child.api.nvim_tabpage_list_wins(0)
end

--------------------------------------------------------------------------------
-- shared/ui.lua  (main process)
--------------------------------------------------------------------------------
describe('shared.ui', function()
  local ui = require('layout.shared.ui')

  after_each(function()
    -- clean up highlight groups so they don't leak into other tests
    for _, cat in ipairs({ 'Active', 'Inactive', 'PickActive', 'PickInactive', 'SeparatorActive', 'SeparatorInactive' }) do
      pcall(vim.api.nvim_set_hl, 0, 'Layout' .. cat, {})
      for _, pos in ipairs({ 'Left', 'Right', 'Bottom' }) do
        pcall(vim.api.nvim_set_hl, 0, 'Layout' .. cat .. pos, {})
        for i = 1, 3 do
          pcall(vim.api.nvim_set_hl, 0, 'Layout' .. cat .. pos .. i, {})
        end
      end
    end
  end)

  it('creates base LayoutActive and LayoutInactive groups linked to configured colors', function()
    local colors = {
      active = 'PmenuSel',
      inactive = 'Comment',
      pick_active = 'PmenuSel',
      pick_inactive = 'Comment',
      separator_active = 'NonText',
      separator_inactive = 'NonText',
    }
    ui.setup_statusline_highlights({ left = 0, right = 0, bottom = 0 }, colors)

    local active_hl = vim.api.nvim_get_hl(0, { name = 'LayoutActive', link = true })
    expect.equality(active_hl.link, 'PmenuSel')
    local inactive_hl = vim.api.nvim_get_hl(0, { name = 'LayoutInactive', link = true })
    expect.equality(inactive_hl.link, 'Comment')
  end)

  it('creates position-specific groups LayoutActiveLeft linked to base', function()
    local colors = {
      active = 'Pmenu',
      inactive = 'Pmenu',
      pick_active = 'Pmenu',
      pick_inactive = 'Pmenu',
      separator_active = 'Pmenu',
      separator_inactive = 'Pmenu',
    }
    ui.setup_statusline_highlights({ left = 1, right = 0, bottom = 0 }, colors)

    local hl = vim.api.nvim_get_hl(0, { name = 'LayoutActiveLeft', link = true })
    expect.equality(hl.link, 'LayoutActive')
  end)

  it('creates position+index groups LayoutActiveLeft1 linked to position', function()
    local colors = {
      active = 'Pmenu',
      inactive = 'Pmenu',
      pick_active = 'Pmenu',
      pick_inactive = 'Pmenu',
      separator_active = 'Pmenu',
      separator_inactive = 'Pmenu',
    }
    ui.setup_statusline_highlights({ left = 2, right = 0, bottom = 0 }, colors)

    local hl1 = vim.api.nvim_get_hl(0, { name = 'LayoutActiveLeft1', link = true })
    expect.equality(hl1.link, 'LayoutActiveLeft')
    local hl2 = vim.api.nvim_get_hl(0, { name = 'LayoutActiveLeft2', link = true })
    expect.equality(hl2.link, 'LayoutActiveLeft')
  end)

  it('creates groups for multiple sides', function()
    local colors = {
      active = 'Pmenu',
      inactive = 'Pmenu',
      pick_active = 'Pmenu',
      pick_inactive = 'Pmenu',
      separator_active = 'Pmenu',
      separator_inactive = 'Pmenu',
    }
    ui.setup_statusline_highlights({ left = 1, right = 2, bottom = 1 }, colors)

    local left_hl = vim.api.nvim_get_hl(0, { name = 'LayoutActiveLeft1', link = true })
    expect.equality(left_hl.link, 'LayoutActiveLeft')
    local right_hl = vim.api.nvim_get_hl(0, { name = 'LayoutInactiveRight2', link = true })
    expect.equality(right_hl.link, 'LayoutInactiveRight')
    local bottom_hl = vim.api.nvim_get_hl(0, { name = 'LayoutPickActiveBottom1', link = true })
    expect.equality(bottom_hl.link, 'LayoutPickActiveBottom')
  end)

  it('creates all six category base groups', function()
    local colors = {
      active = 'Pmenu',
      inactive = 'Pmenu',
      pick_active = 'Pmenu',
      pick_inactive = 'Pmenu',
      separator_active = 'Pmenu',
      separator_inactive = 'Pmenu',
    }
    ui.setup_statusline_highlights({ left = 0, right = 0, bottom = 0 }, colors)

    for _, cat in ipairs({ 'Active', 'Inactive', 'PickActive', 'PickInactive', 'SeparatorActive', 'SeparatorInactive' }) do
      local hl = vim.api.nvim_get_hl(0, { name = 'Layout' .. cat, link = true })
      expect.equality(hl.link, 'Pmenu')
    end
  end)
end)

--------------------------------------------------------------------------------
-- features/statusline.lua  (child process)
--------------------------------------------------------------------------------
describe('features.statusline', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  describe('get_statusline', function()
    it('returns one string per declared group on a side', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'left1', open = 'echo' },
              },
            },
            terminal = {
              picker = { icon = 'T', key = 't' },
              views = {
                term1 = { filter = 'left2', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local reg = _G._reg
        local opts = require('layout.shared.config').merge(_G._c)
        require('layout.features.statusline'):setup(reg, opts.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(#stl, 2)
    end)

    it('returns an empty table for a side with no groups', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'left1', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        require('layout.features.statusline'):setup(_G._reg, require('layout.shared.config').merge(_G._c).statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('bottom')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(#stl, 0)
    end)

    it('wraps icons in click regions when clickable is true', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'left1', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        resolved.statusline.clickable = true
        resolved.statusline.colored = false
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(#stl, 1)
      local s = stl[1]
      expect.equality(s:match("%d+@v:lua.require'layout%.features%.statusline'%.on_click@") ~= nil, true)
      expect.equality(s:sub(-2), '%T')
    end)

    it('omits click regions when clickable is false', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'left1', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        resolved.statusline.clickable = false
        resolved.statusline.colored = false
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      local s = stl[1]
      expect.equality(s:match('@v:lua'), nil)
    end)

    it('omits highlight markers when colored is false', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'left1', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        resolved.statusline.colored = false
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      local s = stl[1]
      expect.equality(s:match('%#Layout'), nil)
    end)

    it('includes the group icon in the statusline string', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'left1', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        resolved.statusline.colored = false
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(stl[1]:match('E') ~= nil, true)
    end)

    it('uses configured separators around icons', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'left1', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        resolved.statusline.separators = { '[', ']' }
        resolved.statusline.colored = false
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      local s = stl[1]
      expect.equality(s:match('%[E%]') ~= nil, true)
    end)
  end)

  describe('highlight (colored)', function()
    it('applies LayoutActive highlight to a group with an open window', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'leftft', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        resolved.statusline.colored = true
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
      ]]))

      U.make_tool_win(child, 'leftft')

      child.lua([[
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]])
      local stl = child.lua_get('_G._stl')
      expect.equality(stl[1]:match('%#LayoutActive') ~= nil, true)
    end)

    it('applies LayoutInactive highlight to a group with no open windows', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'leftft', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        resolved.statusline.colored = true
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(stl[1]:match('%#LayoutInactive') ~= nil, true)
    end)
  end)

  describe('pick mode', function()
    it('injects the group key when pick mode is on', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = { filter = 'leftft', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        require('layout.features.statusline').pick_mode = true
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(stl[1]:match('e') ~= nil, true)
    end)

    it('filters out groups without both icon and key', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            nokeygroup = {
              picker = { icon = 'N' },
              views = {
                filesystem = { filter = 'leftft', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        require('layout.features.statusline').pick_mode = true
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(#stl, 0)
    end)

    it('shows no pick keys when pick mode is off', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'z' },
              views = {
                filesystem = { filter = 'leftft', open = 'echo' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
        _G._stl = require('layout.features.statusline'):get_statusline('left')
      ]]))
      local stl = child.lua_get('_G._stl')
      expect.equality(stl[1]:match('z'), nil)
    end)
  end)

  describe('on_click', function()
    it('toggles the group matching the minwid', function()
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              picker = { icon = 'E', key = 'e' },
              views = {
                filesystem = {
                  filter = 'leftft',
                  open = 'belowright split',
                },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      child.lua(string.format([[
        local resolved = require('layout.shared.config').merge(_G._c)
        require('layout.entities.workspace'):clear()
        require('layout.features.statusline'):setup(_G._reg, resolved.statusline)
      ]]))

      local before = nwins(child)

      -- Minwid 1 maps to the first group registered (left/explorer)
      child.lua([[require('layout.features.statusline'):on_click(1, 1, 'l', '')]])
      vim.wait(300, function()
        return true
      end)
      local after = nwins(child)
      expect.equality(after, before + 1)
    end)
  end)
end)
