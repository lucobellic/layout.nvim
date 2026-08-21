--- tests/test_resize.lua
--- BDD scenarios for panel resizing — verifying that user-initiated
--- panel resizes are detected and preserved across arrangement cycles.
---
--- Tests that the panel size tracking model (entities/panel/model/size.lua)
--- captures live dimensions from managed windows and feeds them back
--- into the placement spec so the user's preferred size survives
--- window opens, repositioning, and panel close/reopen.

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

describe('panel resizing', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.lua([[require("layout.entities.panel.model.size"):clear()]])
    child.stop()
  end)

  --- Return the winid of the first managed window for a side (L1, R1, B1).
  ---@param child table
  ---@param slot_label string  e.g. "L1"
  ---@return integer?
  local function managed_win(child, slot_label)
    local wins = child.api.nvim_tabpage_list_wins(0)
    for _, w in ipairs(wins) do
      local ok, slot = pcall(child.api.nvim_win_get_var, w, 'layout_slot')
      if ok and slot == slot_label then return w end
    end
    return nil
  end

  --------------------------------------------------------------------------------
  -- resizing is kept
  --------------------------------------------------------------------------------
  describe('resizing is kept', function()
    it('keeps a user-resized panel width on the next arrange', function()
      -- Given: registered views with left panel at config size 30
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
        })
      )

      -- When: a tool window is placed in the left panel
      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      expect.equality(child.api.nvim_win_get_width(winL), 30)

      -- When: the user resizes the panel window to 40
      child.api.nvim_win_set_width(winL, 40)
      expect.equality(child.api.nvim_win_get_width(winL), 40)

      -- When: a new arrange cycle runs (e.g. triggered by a view's events)
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      -- Then: the window keeps the user's width, not the config default
      expect.equality(child.api.nvim_win_get_width(winL), 40)
    end)

    it('detects programmatic resize via nvim_win_set_width and keeps it', function()
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
        })
      )

      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      -- Programmatically resize to 50
      child.api.nvim_win_set_width(winL, 50)

      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      expect.equality(child.api.nvim_win_get_width(winL), 50)
    end)

    it('captures a stable-topology WinResized event before the next arrange', function()
      -- Given: an arranged left panel with autocmds enabled
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'toolL', open = 'echo left' },
              },
            },
          },
        },
      })
      cfg.live_resize_debounce = 10
      U.setup_config(child, cfg)

      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.lua([[require("layout.autocmds"):setup(_G._reg, _G._c)]])

      -- When: a stale lifecycle flag exists, then the panel is resized without
      -- adding or closing a normal window
      child.lua([[require("layout.entities.panel.model.size"):mark_topology_changed()]])
      child.api.nvim_win_set_width(winL, 40)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {})]])
      vim.wait(100, function()
        return true
      end)

      -- Then: a later placement uses the new live size rather than restoring 30
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      expect.equality(child.api.nvim_win_get_width(winL), 40)
    end)

    it('keeps user-resized view heights within a group on the next arrange', function()
      -- Given: two views stacked in one left-panel group with configured sizes
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  first = { filter = 'toolA', open = 'echo first', size = 10 },
                  second = { filter = 'toolB', open = 'echo second', size = 30 },
                },
              },
            },
          },
        })
      )
      local first = U.make_tool_win(child, 'toolA')
      child.cmd('belowright split')
      local second = U.make_tool_win(child, 'toolB')
      child.lua([[require('layout.entities.panel'):arrange(_G._reg)]])
      expect.equality(child.api.nvim_win_get_height(first), 10)
      local initial_second = child.api.nvim_win_get_height(second)

      -- When: the user moves the separator and another arrangement runs
      child.api.nvim_win_set_height(first, 8)
      child.lua([[require('layout.entities.panel'):arrange(_G._reg)]])

      -- Then: both live heights are retained instead of restoring config sizes
      expect.equality(child.api.nvim_win_get_height(first), 8)
      expect.equality(child.api.nvim_win_get_height(second), initial_second + 2)
    end)

    it('keeps user-resized view widths within a bottom group after reopening it', function()
      -- Given: two views stacked horizontally in one bottom-panel group
      U.setup_config(
        child,
        U.test_config({
          bottom = {
            size = 15,
            groups = {
              tools = {
                views = {
                  first = { filter = 'toolA', open = 'echo first' },
                  second = { filter = 'toolB', open = 'echo second' },
                },
              },
            },
          },
        })
      )
      local first = U.make_tool_win(child, 'toolA')
      child.cmd('belowright vsplit')
      local second = U.make_tool_win(child, 'toolB')
      child.lua([[require('layout.entities.panel'):arrange(_G._reg)]])

      -- When: the user moves the separator, closes both views, and reopens them
      local expected_first = child.api.nvim_win_get_width(first) + 5
      child.api.nvim_win_set_width(first, expected_first)
      child.lua([[require('layout.entities.panel'):arrange(_G._reg)]])
      local expected_second = child.api.nvim_win_get_width(second)
      child.api.nvim_win_close(first, true)
      child.api.nvim_win_close(second, true)
      local reopened_first = U.make_tool_win(child, 'toolA')
      child.cmd('belowright vsplit')
      local reopened_second = U.make_tool_win(child, 'toolB')
      child.lua([[require('layout.entities.panel'):arrange(_G._reg)]])

      -- Then: the group restores the user-selected internal widths
      expect.equality(child.api.nvim_win_get_width(reopened_first), expected_first)
      expect.equality(child.api.nvim_win_get_width(reopened_second), expected_second)
    end)
  end)

  --------------------------------------------------------------------------------
  -- resize and placement coordination
  --------------------------------------------------------------------------------
  describe('resize and placement coordination', function()
    it('defers automatic arrangement until a manual resize stream is quiet', function()
      -- Given: an arranged panel with automatic events enabled
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'toolL', open = 'echo left' },
              },
            },
          },
        },
      })
      cfg.live_resize_debounce = 100
      U.setup_config(child, cfg)
      local winL, bufL = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.lua([[
        require("layout.autocmds"):setup(_G._reg, _G._c)
        local Panel = require("layout.entities.panel")
        local arrange = Panel.arrange
        _G._automatic_arranges = 0
        Panel.arrange = function(self, ...)
          _G._automatic_arranges = _G._automatic_arranges + 1
          return arrange(self, ...)
        end
      ]])

      -- When: a manual resize is followed by an automatic event during its
      -- quiet period
      child.api.nvim_win_set_width(winL, 40)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {})]])
      child.lua([[vim.api.nvim_exec_autocmds('FileType', { buffer = ... })]], { bufL })
      child.lua([[vim.wait(60)]])

      -- Then: placement has not fought the in-progress resize
      expect.equality(child.lua_get([[_G._automatic_arranges]]), 0)
      expect.equality(child.api.nvim_win_get_width(winL), 40)

      -- When: the resize stream has been quiet for the configured delay
      child.lua([[vim.wait(80)]])

      -- Then: the pending arrangement runs once and keeps the final size
      expect.equality(child.lua_get([[_G._automatic_arranges]]), 1)
      expect.equality(child.api.nvim_win_get_width(winL), 40)
    end)

    it('does not restore an old panel size when topology changes during a resize stream', function()
      -- Given: an active manual resize stream at width 35
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'toolL', open = 'echo left' },
              },
            },
          },
        },
      })
      cfg.live_resize_debounce = 100
      U.setup_config(child, cfg)
      local winL = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.lua([[require("layout.autocmds"):setup(_G._reg, _G._c)]])
      child.api.nvim_win_set_width(winL, 35)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {})]])

      -- When: another normal window appears and the user continues dragging
      child.lua([[
        local eventignore = vim.o.eventignore
        vim.o.eventignore = 'all'
        vim.cmd('belowright split')
        vim.o.eventignore = eventignore
      ]])
      child.api.nvim_win_set_width(winL, 38)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {})]])

      -- Then: topology correction is deferred instead of restoring width 35
      expect.equality(child.api.nvim_win_get_width(winL), 38)

      -- When: dragging reaches width 40 and becomes quiet
      child.api.nvim_win_set_width(winL, 40)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {}); vim.wait(140)]])

      -- Then: one corrected layout retains the final user-selected width
      expect.equality(child.api.nvim_win_get_width(winL), 40)
      expect.equality(child.lua_get([[require("layout.entities.panel.model.size"):topology_changed()]]), false)
    end)

    it('releases the placement transaction after an error', function()
      -- Given: a successfully arranged panel with an active resize stream
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'toolL', open = 'echo left' },
              },
            },
          },
        },
      })
      cfg.live_resize_debounce = 100
      U.setup_config(child, cfg)
      local winL = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.lua([[require("layout.autocmds"):setup(_G._reg, _G._c)]])
      child.api.nvim_win_set_width(winL, 35)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {})]])

      -- When: a later placement mutates geometry before failing
      child.lua(
        [[
        local Placement = require("layout.shared.placement")
        local place = Placement.place
        local win = ...
        Placement.place = function()
          vim.api.nvim_win_set_width(win, 20)
          error("forced placement failure")
        end
        _G._placement_failed = not pcall(
          require("layout.entities.panel").arrange,
          require("layout.entities.panel"),
          _G._reg
        )
        Placement.place = place
      ]],
        { winL }
      )
      expect.equality(child.lua_get([[_G._placement_failed]]), true)

      -- When: failed partial geometry emits WinResized during the active stream
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {})]])

      -- When: arrangement is retried
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      -- Then: partial geometry was not captured and the lock was released
      expect.equality(child.api.nvim_win_get_width(winL), 35)
    end)

    it('shares preferences without comparing applied geometry across tabpages', function()
      -- Given: tab A has a manually resized left panel at width 40
      local cfg = U.test_config({
        left = {
          size = 30,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'toolL', open = 'echo left' },
              },
            },
          },
        },
      })
      cfg.live_resize_debounce = 10
      U.setup_config(child, cfg)
      local winA = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.lua([[require("layout.autocmds"):setup(_G._reg, _G._c)]])
      child.api.nvim_win_set_width(winA, 40)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {}); vim.wait(20)]])

      -- When: tab B opens the same panel and changes the shared preference
      child.cmd('tabnew')
      local winB = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      expect.equality(child.api.nvim_win_get_width(winB), 40)
      child.api.nvim_win_set_width(winB, 35)
      child.lua([[vim.api.nvim_exec_autocmds('WinResized', {}); vim.wait(20)]])

      -- Then: returning to tab A applies width 35 without adopting tab A's
      -- previously committed width 40 as a new preference
      child.cmd('tabprevious')
      child.lua([[vim.wait(30)]])
      expect.equality(child.api.nvim_win_get_width(winA), 35)
    end)
  end)

  --------------------------------------------------------------------------------
  -- new window in existing panel
  --------------------------------------------------------------------------------
  describe('new window in existing panel', function()
    it('uses the current panel size when opening a new window in an existing panel', function()
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
        })
      )

      -- Place first tool window and resize it
      local win1, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      child.api.nvim_win_set_width(win1, 40)

      -- Arrange once so the resize is captured by the size model
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)
      expect.equality(child.api.nvim_win_get_width(win1), 40)

      -- Place a second tool window
      local win2, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      -- Then: both windows in the left panel use the tracked size
      expect.equality(child.api.nvim_win_get_width(win1), 40)
      expect.equality(child.api.nvim_win_get_width(win2), 40)
    end)
  end)

  --------------------------------------------------------------------------------
  -- config fallback
  --------------------------------------------------------------------------------
  describe('config fallback', function()
    it('opens at config size when no panel was previously open', function()
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
        })
      )

      -- Given: no pre-existing tool windows, size model is empty

      -- When: the first tool window opens
      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      -- Then: it opens at the configured size (fallback from registry)
      expect.equality(child.api.nvim_win_get_width(winL), 30)
    end)

    it('resizes a fractional panel when the editor dimensions change', function()
      -- Given: a left panel configured to occupy one quarter of editor width
      child.o.columns = 122
      local cfg = U.test_config({
        left = {
          size = 0.25,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'toolL', open = 'echo left' },
              },
            },
          },
        },
      })
      cfg.live_resize_debounce = 10
      U.setup_config(child, cfg)
      local winL = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.lua([[require("layout.autocmds"):setup(_G._reg, _G._c)]])
      expect.equality(child.api.nvim_win_get_width(winL), 30)

      -- When: the editor grows from 122 to 162 columns
      child.o.columns = 162
      child.lua([[vim.api.nvim_exec_autocmds('VimResized', {}); vim.wait(100)]])

      -- Then: the configured fraction is preserved and resolves to the new width
      expect.equality(child.api.nvim_win_get_width(winL), 40)
    end)

    it('updates a fractional preference after a manual panel resize', function()
      -- Given: a quarter-width panel in a 122-column editor
      child.o.columns = 122
      local cfg = U.test_config({
        left = {
          size = 0.25,
          groups = {
            explorer = {
              views = {
                filesystem = { filter = 'toolL', open = 'echo left' },
              },
            },
          },
        },
      })
      cfg.live_resize_debounce = 10
      U.setup_config(child, cfg)
      local winL = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      -- When: the user changes it to 40 columns, then the editor grows
      child.api.nvim_win_set_width(winL, 40)
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.lua([[require("layout.autocmds"):setup(_G._reg, _G._c)]])
      child.o.columns = 162
      child.lua([[vim.api.nvim_exec_autocmds('VimResized', {}); vim.wait(100)]])

      -- Then: the remembered 40/122 ratio is applied to the new editor width
      expect.equality(child.api.nvim_win_get_width(winL), 53)
    end)

    it('does not retain a transient zero dimension as a fractional preference', function()
      -- Given: an arranged fractional bottom panel
      local cfg = U.test_config({
        bottom = {
          size = 0.25,
          groups = {
            terminal = {
              views = {
                shell = { filter = 'toolB', open = 'echo bottom' },
              },
            },
          },
        },
      })
      U.setup_config(child, cfg)
      local winB = U.make_tool_win(child, 'toolB')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      -- When: resize churn temporarily collapses the panel to zero rows
      child.api.nvim_win_set_height(winB, 0)
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      -- Then: arrangement restores a valid visible size without retaining zero
      expect.equality(child.api.nvim_win_get_height(winB) >= 1, true)
    end)
  end)

  --------------------------------------------------------------------------------
  -- close and reopen
  --------------------------------------------------------------------------------
  describe('close and reopen', function()
    it('remembers the resized size when a panel is closed and reopened', function()
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
        })
      )

      -- Open panel and resize
      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      child.api.nvim_win_set_width(winL, 40)
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)
      expect.equality(child.api.nvim_win_get_width(winL), 40)

      -- Close the panel (close the tool window)
      pcall(child.api.nvim_win_close, winL, true)
      vim.wait(200, function()
        return true
      end)

      -- The early return in arrange leaves tracked size untouched
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      -- Open a new tool window
      local win2, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      -- Then: the new window opens at the previously remembered size
      expect.equality(child.api.nvim_win_get_width(win2), 40)
    end)

    it('settles an empty panel topology without discarding its remembered size', function()
      -- Given: a left panel whose user-resized width has been committed
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
        })
      )

      child.cmd('belowright vsplit')
      child.api.nvim_set_current_win(child.api.nvim_tabpage_list_wins(0)[1])
      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      child.api.nvim_win_set_width(winL, 40)
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      -- When: the panel closes while topology capture is suspended, and an
      -- arrange observes that no managed windows remain
      child.lua([[require("layout.entities.panel.model.size"):mark_topology_changed()]])
      child.api.nvim_win_close(winL, true)
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      -- Then: reopening the panel uses the remembered width and does not leave
      -- a stale topology flag that would restore an unrelated future resize
      local win2, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      expect.equality(child.api.nvim_win_get_width(win2), 40)
      expect.equality(child.lua_get([[require("layout.entities.panel.model.size"):topology_changed()]]), false)
    end)
  end)

  --------------------------------------------------------------------------------
  -- floating windows do not affect panel topology
  --------------------------------------------------------------------------------
  describe('floating windows do not affect panel topology', function()
    it('captures a panel resize made while an unrelated float is open', function()
      -- Given: an arranged left panel
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
        })
      )

      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      -- When: the panel is resized with an unrelated floating window present
      child.api.nvim_win_set_width(winL, 40)
      child.lua([[
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
        require("layout.entities.panel.model.size"):update_live()
        require("layout.entities.panel"):arrange(_G._reg)
      ]])

      -- Then: the float does not make the live resize look like a topology change
      expect.equality(child.api.nvim_win_get_width(winL), 40)
    end)
  end)

  --------------------------------------------------------------------------------
  -- bottom panel stability with side panels present
  --------------------------------------------------------------------------------
  describe('bottom panel stability with side panels present', function()
    --- Focus the first non-managed window.
    ---@param child table
    ---@return integer
    local function focus_center(child)
      for _, w in ipairs(child.api.nvim_tabpage_list_wins(0)) do
        local ok, managed = pcall(child.api.nvim_win_get_var, w, 'layout_managed')
        if not (ok and managed) then
          child.api.nvim_set_current_win(w)
          return w
        end
      end
      error('expected a non-managed center window')
    end

    --- Open a center split. Returns the new window id.
    ---@param child table
    ---@return integer
    local function center_split(child)
      focus_center(child)
      child.cmd('belowright split')
      return child.api.nvim_get_current_win()
    end

    it('bottom panel height stays stable when center splits are opened with left panel (full align)', function()
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
          bottom = {
            size = 15,
            align = 'full',
            groups = {
              term = {
                views = {
                  shell = { filter = 'toolB', open = 'echo bot' },
                },
              },
            },
          },
        })
      )

      -- Given: left and full-width bottom panels are both open, with the
      -- default positive minimum height constraining every center split.
      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      focus_center(child)
      local winB, _ = U.make_tool_win(child, 'toolB')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])

      expect.equality(winL ~= winB, true)
      expect.equality(child.api.nvim_win_get_var(winL, 'layout_slot'), 'L1')
      expect.equality(child.api.nvim_win_get_var(winB, 'layout_slot'), 'B1')
      child.o.winminheight = 1
      child.lua([[require("layout.autocmds"):setup(_G._reg, _G._c)]])

      local h_before = child.api.nvim_win_get_height(winB)
      expect.equality(h_before, 15)

      -- When: several splits are opened from a centered window.
      for _ = 1, 5 do
        center_split(child)
      end

      -- Then: WinResized restores the panel synchronously, before the split
      -- command returns and Neovim has an opportunity to redraw the jump.
      -- And: layout.nvim must not adopt the collateral resize as the user's
      -- preferred bottom-panel height.
      expect.equality(child.api.nvim_win_get_height(winB), h_before)
    end)

    it('bottom panel height stays stable when center splits are opened with left panel (contained align)', function()
      U.setup_config(
        child,
        U.test_config({
          left = {
            size = 30,
            groups = {
              explorer = {
                views = {
                  filesystem = { filter = 'toolL', open = 'echo left' },
                },
              },
            },
          },
          bottom = {
            size = 15,
            align = 'contained',
            groups = {
              term = {
                views = {
                  shell = { filter = 'toolB', open = 'echo bot' },
                },
              },
            },
          },
        })
      )

      -- Open left and bottom panels
      local winL, _ = U.make_tool_win(child, 'toolL')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      local winB, _ = U.make_tool_win(child, 'toolB')
      child.lua([[require("layout.entities.panel"):arrange(_G._reg)]])
      vim.wait(200, function()
        return true
      end)

      local h_before = child.api.nvim_win_get_height(winB)
      expect.equality(h_before, 15)

      -- Open center splits
      for _ = 1, 5 do
        center_split(child)
      end

      -- Then: bottom panel height unchanged
      expect.equality(child.api.nvim_win_get_height(winB), h_before)
    end)
  end)
end)
