--- tests/test_entities.lua
--- Unit tests for entity modules: view, group, workspace, panel.
---
--- view and panel tests use a child Neovim process (need windows/buffers).
--- group and workspace tests are pure table operations.

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

local config = require('layout.shared.config')
local group_entity = require('layout.entities.group')
local workspace_entity = require('layout.entities.workspace')

--------------------------------------------------------------------------------
-- entities/view.lua  (child process)
--------------------------------------------------------------------------------
describe('entities.view', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  --- Run match_by_buf in the child and return { side, group, vname }.
  local function match_in_child(bufnr, winid)
    child.lua(string.format('_G._match_buf = %d; _G._match_win = %d', bufnr, winid))
    child.lua([[
      local side, group, vname = require("layout.entities.view"):match_by_buf(_G._match_buf, _G._match_win)
      _G._match_side = side
      _G._match_group = group
      _G._match_vname = vname
    ]])
    return {
      child.lua_get([[_G._match_side]]),
      child.lua_get([[_G._match_group]]),
      child.lua_get([[_G._match_vname]]),
    }
  end

  it('matches a buffer by string shorthand filter (filetype)', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'neo-tree', open = 'echo test' },
              },
            },
          },
        },
      })
    )
    local winid, bufnr = U.make_tool_win(child, 'neo-tree')
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], 'left')
    expect.equality(result[2], 'explorer')
    expect.equality(result[3], 'filesystem')
  end)

  it('matches a buffer by function filter on filetype', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = {
                  filter = function(buf)
                    return vim.bo[buf].filetype == 'toolL'
                  end,
                  open = 'echo test',
                },
              },
            },
          },
        },
      })
    )
    local winid, bufnr = U.make_tool_win(child, 'toolL')
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], 'left')
    expect.equality(result[2], 'explorer')
  end)

  it('matches a buffer by function filter on filetype AND buftype', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = {
                  filter = function(buf)
                    return vim.bo[buf].filetype == 'neo-tree' and vim.bo[buf].buftype == 'nofile'
                  end,
                  open = 'echo test',
                },
              },
            },
          },
        },
      })
    )
    local winid, bufnr = U.make_tool_win(child, 'neo-tree')
    child.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], 'left')
  end)

  it('rejects when filter conditions are not met', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = {
                  filter = function(buf)
                    return vim.bo[buf].filetype == 'neo-tree' and vim.bo[buf].buftype == 'nofile'
                  end,
                  open = 'echo test',
                },
              },
            },
          },
        },
      })
    )
    local winid, bufnr = U.make_tool_win(child, 'neo-tree')
    child.api.nvim_set_option_value('buftype', 'acwrite', { buf = bufnr })
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], vim.NIL)
  end)

  it('matches a buffer by filter on buffer variable', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = {
                  filter = function(buf)
                    local ok, source = pcall(vim.api.nvim_buf_get_var, buf, 'neo_tree_source')
                    return ok and source == 'filesystem'
                  end,
                  open = 'echo test',
                },
              },
            },
          },
        },
      })
    )
    local winid, bufnr = U.make_tool_win(child, 'neo-tree', { neo_tree_source = 'filesystem' })
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], 'left')
  end)

  it('matches a buffer by filter on window property (floating)', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = {
                  filter = function(buf, win)
                    return vim.bo[buf].filetype == 'neo-tree' and vim.api.nvim_win_get_config(win).relative ~= ''
                  end,
                  open = 'echo test',
                },
              },
            },
          },
        },
      })
    )
    local bufnr = child.api.nvim_create_buf(false, true)
    child.api.nvim_set_option_value('filetype', 'neo-tree', { buf = bufnr })
    child.api.nvim_set_option_value('buflisted', false, { buf = bufnr })
    local winid =
      child.api.nvim_open_win(bufnr, false, { relative = 'editor', width = 10, height = 5, row = 0, col = 0 })
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], 'left')
    child.api.nvim_win_close(winid, true)
  end)

  it('returns nil when no view matches', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'neo-tree', open = 'echo test' },
              },
            },
          },
        },
      })
    )
    local winid, bufnr = U.make_tool_win(child, 'unmatched_ft')
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], vim.NIL)
  end)

  it('returns first match when multiple views match the same buffer', function()
    U.setup_config(
      child,
      U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                first = { filter = 'shared', open = 'echo first' },
                second = { filter = 'shared', open = 'echo second' },
              },
            },
          },
        },
      })
    )
    local winid, bufnr = U.make_tool_win(child, 'shared')
    local result = match_in_child(bufnr, winid)
    expect.equality(result[1], 'left')
    expect.equality(result[2], 'explorer')
    expect.equality(result[3] == 'first' or result[3] == 'second', true)
  end)
end)

--------------------------------------------------------------------------------
-- entities/group.lua  (pure — main process)
--------------------------------------------------------------------------------
describe('entities.group', function()
  before_each(function()
    local cfg = config.merge(U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            picker = { icon = 'E', key = 'e' },
            views = {
              filesystem = { filter = 'neo-tree', open = 'Neotree' },
              symbols = { filter = 'Outline', open = 'OutlineOpen' },
            },
          },
          terminal = {
            picker = { icon = 'T', key = 't' },
            views = {
              term = { filter = 'toggleterm', open = 'Terminal' },
            },
          },
        },
      },
      right = {
        size = 40,
        groups = {
          buffers = {
            picker = { icon = 'B', key = 'b' },
            views = {
              buffers_view = { filter = 'neo-tree', open = 'Neotree' },
            },
          },
        },
      },
    }))
    local reg = config.normalize(cfg)
    group_entity:register(reg)
  end)

  after_each(function()
    group_entity:clear()
  end)

  it('registers groups from a registry', function()
    expect.equality(#group_entity:list('left'), 2)
    expect.equality(#group_entity:list('right'), 1)
    expect.equality(#group_entity:list('bottom'), 0)
  end)

  it('looks up a group by side + name', function()
    local g = group_entity:get('left', 'explorer')
    expect.equality(g.icon, 'E')
    expect.equality(g.key, 'e')
  end)

  it('returns nil for unknown group', function()
    expect.equality(group_entity:get('left', 'nonexistent'), nil)
    expect.equality(group_entity:get('bottom', 'explorer'), nil)
  end)

  it('lists group names on a side in declaration order', function()
    local names = group_entity:list('left')
    expect.equality(#names, 2)
    expect.equality(names[1], 'explorer')
    expect.equality(names[2], 'terminal')
  end)

  it('returns view entries for a group', function()
    local views = group_entity:views_for('left', 'explorer')
    expect.equality(views.filesystem.filter, 'neo-tree')
    expect.equality(views.filesystem.open, 'Neotree')
    expect.equality(views.symbols.filter, 'Outline')
  end)

  it('returns empty map for unknown group', function()
    local v = group_entity:views_for('left', 'nonexistent')
    expect.equality(type(v), 'table')
    expect.equality(next(v), nil)
  end)

  it('iterates all groups across all sides in declaration order', function()
    local result = {}
    for side, gname, gdesc in group_entity:iter() do
      expect.equality(type(side), 'string')
      expect.equality(type(gname), 'string')
      expect.equality(type(gdesc), 'table')
      result[#result + 1] = { side = side, name = gname }
    end
    expect.equality(#result, 3)
    expect.equality(result[1].side, 'left')
    expect.equality(result[1].name, 'explorer')
    expect.equality(result[2].side, 'left')
    expect.equality(result[2].name, 'terminal')
    expect.equality(result[3].side, 'right')
    expect.equality(result[3].name, 'buffers')
  end)
end)

--------------------------------------------------------------------------------
-- entities/workspace.lua  (pure — main process)
--------------------------------------------------------------------------------
describe('entities.workspace', function()
  before_each(function()
    workspace_entity:clear()
  end)

  after_each(function()
    workspace_entity:clear()
  end)

  it('marks a group as open and is_open returns true', function()
    workspace_entity:mark_open('left', 'explorer')
    expect.equality(workspace_entity:is_open('left', 'explorer'), true)
  end)

  it('marks a group as closed and is_open returns false', function()
    workspace_entity:mark_open('left', 'explorer')
    workspace_entity:mark_closed('left', 'explorer')
    expect.equality(workspace_entity:is_open('left', 'explorer'), false)
  end)

  it('returns false for unknown group', function()
    expect.equality(workspace_entity:is_open('left', 'never_opened'), false)
  end)

  it('lists open groups on a side', function()
    workspace_entity:mark_open('left', 'explorer')
    workspace_entity:mark_open('left', 'terminal')
    workspace_entity:mark_open('right', 'buffers')
    local open_left = workspace_entity:open_groups('left')
    expect.equality(#open_left, 2)
    local open_right = workspace_entity:open_groups('right')
    expect.equality(#open_right, 1)
    local open_bottom = workspace_entity:open_groups('bottom')
    expect.equality(#open_bottom, 0)
  end)

  it('serializes state to a table', function()
    workspace_entity:mark_open('left', 'explorer')
    workspace_entity:mark_open('right', 'buffers')
    local tbl = workspace_entity:to_table()
    expect.equality(tbl.left.explorer, true)
    expect.equality(tbl.right.buffers, true)
  end)

  it('restores state from a serialized table', function()
    workspace_entity:mark_open('left', 'explorer')
    local saved = workspace_entity:to_table()
    workspace_entity:clear()
    workspace_entity:from_table(saved)
    expect.equality(workspace_entity:is_open('left', 'explorer'), true)
  end)

  it('isolates state between tabpages', function()
    workspace_entity:mark_open('left', 'explorer')
    expect.equality(workspace_entity:is_open('left', 'explorer'), true)

    vim.cmd.tabnew()
    expect.equality(workspace_entity:is_open('left', 'explorer'), false)

    workspace_entity:mark_open('left', 'explorer')
    expect.equality(workspace_entity:is_open('left', 'explorer'), true)

    vim.cmd.tabclose()
    expect.equality(workspace_entity:is_open('left', 'explorer'), true)
  end)

  it('to_table and from_table scope to current tabpage', function()
    workspace_entity:mark_open('left', 'explorer')
    local saved = workspace_entity:to_table()

    vim.cmd.tabnew()
    workspace_entity:from_table(saved)
    expect.equality(workspace_entity:is_open('left', 'explorer'), true)

    vim.cmd.tabclose()
    expect.equality(workspace_entity:is_open('left', 'explorer'), true)
  end)
end)

--------------------------------------------------------------------------------
-- entities/panel.lua  (child process)
--------------------------------------------------------------------------------
describe('entities.panel', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  it('places tool windows into reserved panels', function()
    -- Given: matching views configured for the left and right panels
    -- When: their windows are arranged
    -- Then: each buffer exposes its layout panel, group, and view metadata
    child.lua([[
      local cfg = require("layout.shared.config").merge({
        left = { size = 30, groups = {
          { name = "explorer", picker = { icon = "", key = "e" },
            views = { { name = "filesystem", filter = "toolL", open = "echo left" } } }
        } },
        right = { size = 30, groups = {
          { name = "buffers", picker = { icon = "", key = "b" },
            views = { { name = "buffer_list", filter = "toolR", open = "echo right" } } }
        } }
      })
      local reg = require("layout.shared.config").normalize(cfg)
      require("layout.entities.view"):register(reg)
      _G._panel_reg = reg
    ]])

    local winL, bufnrL = U.make_tool_win(child, 'toolL')
    child.cmd('rightbelow vsplit')
    local winR, bufnrR = U.make_tool_win(child, 'toolR')

    child.lua([[require("layout.entities.panel"):arrange(_G._panel_reg)]])

    vim.wait(200, function()
      return true
    end)

    local tree = U.normalize_tree(U.tree(child))
    expect.equality(tree, { 'row', { { 'leaf' }, { 'leaf' }, { 'leaf' } } })

    child.lua(string.format(
      [[
        _G._left_layout = vim.b[%d].layout
        _G._right_layout = vim.b[%d].layout
      ]],
      bufnrL,
      bufnrR
    ))
    expect.equality(child.lua_get([[_G._left_layout]]), {
      side = 'left',
      group = 'explorer',
      view = 'filesystem',
      enabled = true,
    })
    expect.equality(child.lua_get([[_G._right_layout]]), {
      side = 'right',
      group = 'buffers',
      view = 'buffer_list',
      enabled = true,
    })
  end)

  it('stops managing a buffer after its layout metadata is disabled', function()
    -- Given: a buffer already arranged in the left panel
    -- When: its layout metadata is replaced with enabled set to false and layout is re-evaluated
    -- Then: the buffer no longer matches a managed view and its metadata is not overwritten
    child.lua([[
      local cfg = require("layout.shared.config").merge({
        left = { size = 30, groups = {
          { name = "explorer", picker = { icon = "", key = "e" },
            views = { { name = "filesystem", filter = "toolL", open = "echo left" } } }
        } }
      })
      local reg = require("layout.shared.config").normalize(cfg)
      require("layout.entities.view"):register(reg)
      _G._panel_reg = reg
    ]])

    local winid, bufnr = U.make_tool_win(child, 'toolL')
    child.lua([[require("layout.entities.panel"):arrange(_G._panel_reg)]])
    child.lua(string.format(
      [[vim.b[%d].layout = {
        side = "left",
        group = "explorer",
        view = "filesystem",
        enabled = false,
      }]],
      bufnr
    ))
    child.lua([[require("layout.entities.panel"):arrange(_G._panel_reg)]])

    child.lua(string.format(
      [[
        local side = require("layout.entities.view"):match_by_buf(%d, %d)
        _G._disabled_side = side
        _G._disabled_layout = vim.b[%d].layout
      ]],
      bufnr,
      winid,
      bufnr
    ))
    expect.equality(child.lua_get([[_G._disabled_side]]), vim.NIL)
    expect.equality(child.lua_get([[_G._disabled_layout]]), {
      side = 'left',
      group = 'explorer',
      view = 'filesystem',
      enabled = false,
    })
  end)

  it('skips arrangement when no tool windows exist', function()
    child.lua([[
      local cfg = require("layout.shared.config").merge({
        left = { size = 30, groups = {
          { name = "explorer", picker = { icon = "", key = "e" },
            views = { { name = "filesystem", filter = "toolL", open = "echo left" } } }
        } }
      })
      local reg = require("layout.shared.config").normalize(cfg)
      require("layout.entities.view"):register(reg)
      _G._panel_reg = reg
    ]])

    child.lua([[require("layout.entities.panel"):arrange(_G._panel_reg)]])

    vim.wait(200, function()
      return true
    end)

    local wins = child.api.nvim_tabpage_list_wins(0)
    expect.equality(#wins, 1)
  end)
end)
