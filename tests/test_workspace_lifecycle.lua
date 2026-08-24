---BDD tests for automatic workspace persistence lifecycle.

local MiniTest = require('mini.test')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

describe('workspace lifecycle', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
    child.lua([[
      _G._workspace_dir = vim.fn.tempname() .. '-layout-workspaces'
      vim.fn.mkdir(_G._workspace_dir, 'p')
    ]])
  end)

  after_each(function()
    child.lua([[pcall(vim.fn.delete, _G._workspace_dir, 'rf')]])
    child.stop()
  end)

  it('automatically saves a group after its window is arranged', function()
    -- Given: automatic saving and a group that opens a matching split
    child.lua([[
      _G._workspace_cfg = {
        left = {
          groups = {
            { name = 'explorer', views = {
              { name = 'filesystem', filter = 'toolL', open = 'belowright split | enew | setfiletype toolL' },
            } },
          },
        },
        workspaces = { auto_save = true, auto_restore = false, dir = _G._workspace_dir },
      }
      require('layout').setup(_G._workspace_cfg)
    ]])

    -- When: the group is opened and automatic arrangement settles
    child.cmd('Layout toggle explorer')
    child.lua([[vim.wait(500, function()
      local state = require('layout.shared.store').load(require('layout').config)
      return state and state.sides.left.explorer ~= nil
    end)]])

    -- Then: its configured view identity is persisted without another close event
    expect.equality(
      child.lua_get([[
      require('layout.shared.store').load(require('layout').config).sides.left.explorer.filesystem
    ]]),
      true
    )
  end)

  it('saves the old directory before restoring the new directory', function()
    -- Given: separate old and new working directories and an open old-workspace view
    child.lua([[
      _G._old_cwd = vim.fn.tempname() .. '-old'
      _G._new_cwd = vim.fn.tempname() .. '-new'
      vim.fn.mkdir(_G._old_cwd, 'p')
      vim.fn.mkdir(_G._new_cwd, 'p')
      vim.cmd.cd(_G._old_cwd)
      _G._workspace_cfg = {
        left = { groups = { { name = 'explorer', views = {
          { name = 'filesystem', filter = 'toolL', open = 'belowright split | enew | setfiletype toolL' },
        } } } },
        workspaces = { auto_save = true, auto_restore = true, dir = _G._workspace_dir },
      }
      require('layout').setup(_G._workspace_cfg)
      require('layout.features.toggle').open_group('left', 'explorer')
    ]])

    -- When: the working directory changes
    child.lua([[vim.cmd.cd(_G._new_cwd)]])

    -- Then: the old workspace was written under the old directory key
    expect.equality(
      child.lua_get([[
      require('layout.shared.store').load(require('layout').config, _G._old_cwd).sides.left.explorer.filesystem
    ]]),
      true
    )
    expect.equality(child.lua_get([[vim.iter(require('layout.entities.view'):iter_matches()):count()]]), 0)
  end)
end)
