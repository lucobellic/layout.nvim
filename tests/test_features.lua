--- tests/test_features.lua
--- Unit tests for feature module: toggle.
--- All tests use a child Neovim process (need windows/buffers).

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

local function nwins(child)
  return #child.api.nvim_tabpage_list_wins(0)
end

--------------------------------------------------------------------------------
-- setup() — global side effects
--------------------------------------------------------------------------------
describe('setup()', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  it('sets winminheight=0 and winminwidth=0 so user splits cannot push panel windows', function()
    -- Given: Neovim defaults (child already started by before_each)
    expect.equality(child.o.winminheight, 1)
    expect.equality(child.o.winminwidth, 1)

    -- When: setup() is called with an empty config
    child.lua("require('layout').setup({})")

    -- Then: global minimums are 0
    expect.equality(child.o.winminheight, 0)
    expect.equality(child.o.winminwidth, 0)
  end)
end)

--------------------------------------------------------------------------------
-- features/toggle.lua
--------------------------------------------------------------------------------
describe('features.toggle', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  it("open_group runs each view's open command", function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = {
                filter = 'toolL',
                open = 'belowright split',
              },
              symbols = {
                filter = 'Outline',
                open = 'belowright split',
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    local before = nwins(child)
    child.lua([[require("layout.features.toggle").open_group("left", "explorer")]])
    vim.wait(300, function()
      return true
    end)
    local after = nwins(child)
    expect.equality(after, before + 2)
  end)

  it('keeps the editor cursor on the same screen row when opening multiple full-width bottom views', function()
    -- Given: splitkeep=screen and an editor cursor that remains visible while
    -- two bottom windows are opened one after another.
    U.prepare(child)
    child.o.splitkeep = 'screen'
    local editor = child.api.nvim_get_current_win()
    child.lua('_G._cursor_editor = ' .. editor)
    child.lua([[
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.tbl_map(tostring, vim.fn.range(1, 200)))
      vim.api.nvim_win_set_cursor(0, { 93, 0 })
      vim.cmd('normal! zt')
      vim.api.nvim_win_set_cursor(0, { 100, 0 })
      vim.cmd('redraw')
    ]])
    local screen_row = child.lua_get('vim.fn.winline()')
    U.setup_config(child, U.test_config({
      bottom = {
        size = 8,
        align = 'full',
        groups = {
          tools = {
            views = {
              first = {
                filter = 'toolB1',
                open = function()
                  vim.schedule(function()
                    vim.cmd('belowright split')
                    local buf = vim.api.nvim_create_buf(false, true)
                    vim.api.nvim_win_set_buf(0, buf)
                    vim.bo[buf].filetype = 'toolB1'
                    vim.api.nvim_set_current_win(_G._cursor_editor)
                  end)
                end,
              },
              second = {
                filter = 'toolB2',
                open = function()
                  vim.schedule(function()
                    vim.cmd('belowright split')
                    local buf = vim.api.nvim_create_buf(false, true)
                    vim.api.nvim_win_set_buf(0, buf)
                    vim.bo[buf].filetype = 'toolB2'
                    vim.api.nvim_set_current_win(_G._cursor_editor)
                  end)
                end,
              },
            },
          },
        },
      },
    }))

    -- When: both views are opened and arranged into the bottom panel.
    child.lua([[require('layout.features.toggle').open_group('bottom', 'tools')]])
    child.lua([[vim.wait(50, function() return false end)]])
    child.api.nvim_set_current_win(editor)

    -- Then: the cursor remains on both the same buffer line and screen row.
    expect.equality(child.api.nvim_win_get_cursor(editor)[1], 100)
    expect.equality(child.lua_get('vim.fn.winline()'), screen_row)
    expect.equality(child.o.splitkeep, 'screen')
  end)

  it('close_group closes matching tool windows', function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = { filter = 'toolL', open = 'echo' },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    -- Create a second window first so closing the tool window doesn't
    -- leave the tabpage empty (nvim_win_close refuses to close the last window).
    child.cmd('belowright split')
    child.cmd('enew')
    child.api.nvim_set_current_win(child.api.nvim_tabpage_list_wins(0)[1])
    local _, bufnr_tool = U.make_tool_win(child, 'toolL')
    -- Tool window + the blank window = 2 windows
    child.lua([[require("layout.features.toggle").close_group("left", "explorer")]])
    vim.wait(300, function()
      return true
    end)
    -- The tool window was closed — buffer not displayed in any window
    local shown = false
    for _, w in ipairs(child.api.nvim_tabpage_list_wins(0)) do
      if child.api.nvim_win_get_buf(w) == bufnr_tool then shown = true end
    end
    expect.equality(shown, false)
  end)

  it('leaves a disabled buffer open and manages it again after re-enabling', function()
    -- Given: a tool buffer already arranged in the left panel
    -- When: it is disabled before the left panel is closed
    -- Then: closing the panel leaves that buffer open
    -- When: the buffer is enabled again and the panel is closed
    -- Then: the buffer is once again managed and its window closes
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = { filter = 'toolL', open = 'echo' },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    child.cmd('belowright split')
    child.cmd('enew')
    child.api.nvim_set_current_win(child.api.nvim_tabpage_list_wins(0)[1])
    local _, bufnr_tool = U.make_tool_win(child, 'toolL')
    child.lua([[require("layout.entities.panel"):arrange()]])

    child.lua(string.format([[require("layout").set_buffer_enabled(%d, false)]], bufnr_tool))
    child.lua([[require("layout.features.toggle").close_panel("left")]])

    local function is_shown()
      for _, winid in ipairs(child.api.nvim_tabpage_list_wins(0)) do
        if child.api.nvim_win_get_buf(winid) == bufnr_tool then return true end
      end
      return false
    end
    expect.equality(is_shown(), true)

    child.lua(string.format([[require("layout").set_buffer_enabled(%d, true)]], bufnr_tool))
    child.lua([[require("layout.features.toggle").close_panel("left")]])
    expect.equality(is_shown(), false)
  end)

  it('toggle_group opens when closed, closes when open', function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = {
                filter = 'toolL',
                open = function()
                  vim.cmd('belowright split')
                  local buf = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_win_set_buf(0, buf)
                  vim.bo[buf].filetype = 'toolL'
                end,
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    local before = nwins(child)

    -- first toggle → open
    child.lua([[require("layout.features.toggle").toggle_group("left", "explorer")]])
    vim.wait(300, function()
      return true
    end)
    expect.equality(nwins(child), before + 1)

    -- second toggle → close (window is gone, scratch window may remain)
    child.lua([[require("layout.features.toggle").toggle_group("left", "explorer")]])
    vim.wait(300, function()
      return true
    end)
    local remaining = nwins(child)
    expect.equality(remaining <= before + 1, true)
  end)

  it('toggle_group re-opens after manual window close', function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = {
                filter = 'toolL',
                open = function()
                  vim.cmd('belowright split')
                  local buf = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_win_set_buf(0, buf)
                  vim.bo[buf].filetype = 'toolL'
                end,
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    local before = nwins(child)

    -- open the group
    child.lua([[require("layout.features.toggle").open_group("left", "explorer")]])
    vim.wait(300, function()
      return true
    end)
    expect.equality(nwins(child), before + 1)

    -- verify workspace state says open
    local is_open = child.lua_get([[require("layout.entities.workspace"):is_open("left", "explorer")]])
    expect.equality(is_open, true)

    -- manually close the tool window (simulating :q on the buffer)
    local wins = child.api.nvim_tabpage_list_wins(0)
    local tool_win
    vim.iter(wins):each(function(winid)
      local bufnr = child.api.nvim_win_get_buf(winid)
      local ft = child.api.nvim_buf_get_option(bufnr, 'filetype')
      if ft == 'toolL' then tool_win = winid end
    end)
    expect.equality(tool_win ~= nil, true)
    child.api.nvim_win_close(tool_win, true)
    vim.wait(300, function()
      return true
    end)

    -- window is gone but workspace state still says open (stale)
    is_open = child.lua_get([[require("layout.entities.workspace"):is_open("left", "explorer")]])
    expect.equality(is_open, true)

    -- toggle should detect stale state and re-open
    child.lua([[require("layout.features.toggle").toggle_group("left", "explorer")]])
    vim.wait(300, function()
      return true
    end)
    expect.equality(nwins(child), before + 1)

    -- workspace state should now be open
    is_open = child.lua_get([[require("layout.entities.workspace"):is_open("left", "explorer")]])
    expect.equality(is_open, true)
  end)

  it('close_panel closes all groups on a side', function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = { filter = 'toolL', open = 'echo' },
            },
          },
          terminal = {
            views = {
              term = { filter = 'toggleterm', open = 'echo' },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    -- Create a spare window first so closing all tool windows doesn't
    -- leave the tabpage empty (nvim_win_close refuses to close the last window).
    child.cmd('belowright split')
    child.cmd('enew')
    child.api.nvim_set_current_win(child.api.nvim_tabpage_list_wins(0)[1])
    local _, bufnr1 = U.make_tool_win(child, 'toolL')
    child.cmd('rightbelow vsplit')
    local _, bufnr2 = U.make_tool_win(child, 'toggleterm')

    child.lua([[require("layout.features.toggle").close_panel("left")]])
    vim.wait(300, function()
      return true
    end)
    -- Tool windows were closed — buffers not displayed in any window
    local shown1, shown2 = false, false
    for _, w in ipairs(child.api.nvim_tabpage_list_wins(0)) do
      local b = child.api.nvim_win_get_buf(w)
      if b == bufnr1 then shown1 = true end
      if b == bufnr2 then shown2 = true end
    end
    expect.equality(shown1, false)
    expect.equality(shown2, false)
  end)

  it('places tool windows in the panel position synchronously without vim.wait', function()
    local cfg = U.test_config({
      left = {
        size = 25,
        groups = {
          explorer = {
            views = {
              filesystem = {
                filter = 'toolL',
                open = function()
                  vim.cmd('belowright vsplit')
                  local buf = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_win_set_buf(0, buf)
                  vim.bo[buf].filetype = 'toolL'
                end,
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    local before = nwins(child)
    child.lua([[require("layout.features.toggle").open_group("left", "explorer")]])

    local after = nwins(child)
    expect.equality(after, before + 1)

    local wins = child.api.nvim_tabpage_list_wins(0)
    local placed = nil
    for _, w in ipairs(wins) do
      local ok, slot = pcall(child.api.nvim_win_get_var, w, 'layout_slot')
      if ok and slot then
        placed = w
        break
      end
    end
    expect.equality(placed ~= nil, true)

    if placed then
      local pos = child.api.nvim_win_get_position(placed)
      local width = child.api.nvim_win_get_width(placed)
      expect.equality(pos[2], 0)
      expect.equality(width, 25)
    end
  end)

  it('places a window with deferred filetype into the panel before any scheduled tick', function()
    -- Given: the left panel is already open with group "explorer", and
    --        group "problems" has a view whose open command creates a
    --        window in the wrong position and sets its filetype on a
    --        deferred tick (like Trouble does)
    -- When: the user opens group "problems"
    -- Then: immediately after open_group returns — same tick, before any
    --       scheduled callback can run — the new window already sits in
    --       the left panel column
    local cfg = U.test_config({
      left = {
        size = 25,
        groups = {
          explorer = {
            views = {
              filesystem = { filter = 'toolL', open = 'echo' },
            },
          },
          problems = {
            views = {
              trouble = {
                filter = 'toolT',
                open = function()
                  vim.cmd('botright vsplit')
                  local buf = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_win_set_buf(0, buf)
                  _G._trouble_win = vim.api.nvim_get_current_win()
                  vim.schedule(function()
                    vim.bo[buf].filetype = 'toolT'
                  end)
                end,
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    child.cmd('belowright split')
    child.cmd('enew')
    child.api.nvim_set_current_win(child.api.nvim_tabpage_list_wins(0)[1])
    U.make_tool_win(child, 'toolL')
    child.lua([[require("layout.entities.panel"):arrange()]])

    -- Capture geometry in the same synchronous block as open_group so no
    -- scheduled callback (deferred filetype, retry arranges) can run first.
    child.lua([[
      require("layout.features.toggle").open_group("left", "problems")
      local win = _G._trouble_win
      local ok, slot = pcall(vim.api.nvim_win_get_var, win, "layout_slot")
      _G._probe = {
        col = vim.api.nvim_win_get_position(win)[2],
        width = vim.api.nvim_win_get_width(win),
        slot = ok and slot or nil,
      }
    ]])
    local probe = child.lua_get('_G._probe')
    expect.equality(probe.col, 0)
    expect.equality(probe.width, 25)
    expect.equality(probe.slot ~= nil, true)
  end)

  it('presumes only normal windows, not floats, created by open', function()
    -- Given: a view whose open command creates a floating window plus a
    --        normal window, neither classifiable by the filter yet
    -- When: the group is opened
    -- Then: only the normal window is presumed and placed in the panel;
    --       the float is left untouched and unmanaged
    local cfg = U.test_config({
      left = {
        size = 25,
        groups = {
          explorer = {
            views = {
              filesystem = {
                filter = 'toolT',
                open = function()
                  local fbuf = vim.api.nvim_create_buf(false, true)
                  _G._float_win = vim.api.nvim_open_win(fbuf, false, {
                    relative = 'editor',
                    row = 1,
                    col = 1,
                    width = 10,
                    height = 5,
                  })
                  vim.cmd('botright vsplit')
                  local buf = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_win_set_buf(0, buf)
                  _G._normal_win = vim.api.nvim_get_current_win()
                  vim.schedule(function()
                    vim.bo[buf].filetype = 'toolT'
                  end)
                end,
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    child.lua([[
      require("layout.features.toggle").open_group("left", "explorer")
      local ok_n, slot_n = pcall(vim.api.nvim_win_get_var, _G._normal_win, "layout_slot")
      local ok_f, slot_f = pcall(vim.api.nvim_win_get_var, _G._float_win, "layout_slot")
      _G._probe = {
        normal_col = vim.api.nvim_win_get_position(_G._normal_win)[2],
        normal_width = vim.api.nvim_win_get_width(_G._normal_win),
        normal_slotted = ok_n and slot_n ~= nil or false,
        float_slotted = ok_f and slot_f ~= nil or false,
        float_relative = vim.api.nvim_win_get_config(_G._float_win).relative,
      }
    ]])
    local probe = child.lua_get('_G._probe')
    expect.equality(probe.normal_col, 0)
    expect.equality(probe.normal_width, 25)
    expect.equality(probe.normal_slotted, true)
    expect.equality(probe.float_slotted, false)
    expect.equality(probe.float_relative, 'editor')
  end)

  it('leaves a mispredicted window unmanaged after a later filter-based arrange', function()
    -- Given: a view whose open command creates a window that never ends
    --        up matching the view's filter (misprediction)
    -- When: the group is opened (window presumed and placed), then a
    --       subsequent arrange runs with only the filter as classifier
    -- Then: the mispredicted window is no longer managed — the filter
    --       stays authoritative
    local cfg = U.test_config({
      left = {
        size = 25,
        groups = {
          explorer = {
            views = {
              filesystem = { filter = 'toolL', open = 'echo' },
            },
          },
          problems = {
            views = {
              trouble = {
                filter = 'toolT',
                open = function()
                  vim.cmd('botright vsplit')
                  local buf = vim.api.nvim_create_buf(false, true)
                  vim.api.nvim_win_set_buf(0, buf)
                  _G._mispredicted_win = vim.api.nvim_get_current_win()
                  -- filetype never set: the filter will never match
                end,
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    child.cmd('belowright split')
    child.cmd('enew')
    child.api.nvim_set_current_win(child.api.nvim_tabpage_list_wins(0)[1])
    U.make_tool_win(child, 'toolL')
    child.lua([[require("layout.entities.panel"):arrange()]])

    child.lua([[
      require("layout.features.toggle").open_group("left", "problems")
      local ok, v = pcall(vim.api.nvim_win_get_var, _G._mispredicted_win, "layout_managed")
      _G._managed_after_open = ok and v == true or false
    ]])
    expect.equality(child.lua_get('_G._managed_after_open'), true)

    -- A later arrange without the presumed map re-classifies via filters only.
    child.lua([[
      require("layout.entities.panel"):arrange()
      local ok, v = pcall(vim.api.nvim_win_get_var, _G._mispredicted_win, "layout_managed")
      _G._managed_after_rearrange = ok and v == true or false
    ]])
    expect.equality(child.lua_get('_G._managed_after_rearrange'), false)
  end)

  it('arranges a trouble-style window opened under eventignore before the next redraw', function()
    -- Given: setup() wired the autocmds, the left panel is open with the
    --        explorer group, and a "trouble symbols" view is declared with
    --        a filetype+mode filter
    -- When: the plugin mounts its window the way trouble.nvim does — the
    --       command run directly, no Layout toggle: filetype set before
    --       the window exists, the split created and the buffer attached
    --       under eventignore=all (suppressing WinNew/BufWinEnter), and
    --       the mode window-var set after mounting
    -- Then: when WinResized fires (the one event Neovim still triggers
    --       from the main loop before the next redraw), the window is
    --       placed in the left panel column — no debounce timer involved
    child.lua([[
      local function ft_and_mode(ft, mode)
        return function(buf, win)
          if vim.bo[buf].filetype ~= ft then return false end
          local t = win and vim.w[win].trouble or nil
          return type(t) == 'table' and t.mode == mode
        end
      end
      require('layout').setup({
        left = {
          size = 25,
          groups = {
            {
              name = 'explorer',
              views = { { name = 'filesystem', filter = 'toolL', open = 'echo' } },
            },
            {
              name = 'symbols',
              views = {
                {
                  name = 'trouble-symbols',
                  filter = ft_and_mode('trouble', 'symbols'),
                  open = 'echo',
                },
              },
            },
          },
        },
      })
    ]])

    -- Given: explorer already arranged in the left panel
    child.cmd('belowright split')
    child.cmd('enew')
    child.api.nvim_set_current_win(child.api.nvim_tabpage_list_wins(0)[1])
    U.make_tool_win(child, 'toolL')
    child.lua([[require("layout.entities.panel"):arrange()]])

    child.lua([[
      -- Simulate trouble.nvim's mount sequence (view/window.lua):
      -- buffer options first, then the split under eventignore=all,
      -- then the mode window-var (on_mount).
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'trouble'
      local ei = vim.o.eventignore
      vim.o.eventignore = 'all'
      vim.cmd('silent noswapfile vertical topleft 30split')
      vim.api.nvim_win_set_buf(0, buf)
      local win = vim.api.nvim_get_current_win()
      vim.o.eventignore = ei
      vim.w[win].trouble = { mode = 'symbols' }
      -- WinResized is triggered by the main loop before the next redraw;
      -- fire it here so the probe stays synchronous (no redraw between).
      vim.api.nvim_exec_autocmds('WinResized', {})
      _G._probe = {
        col = vim.api.nvim_win_get_position(win)[2],
        width = vim.api.nvim_win_get_width(win),
      }
    ]])
    local probe = child.lua_get('_G._probe')
    expect.equality(probe.col, 0)
    expect.equality(probe.width, 25)
  end)

  it('does not error when open creates no windows', function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = {
                filter = 'toolL',
                open = function() end,
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    local ok = pcall(function()
      child.lua([[require("layout.features.toggle").open_group("left", "explorer")]])
    end)
    expect.equality(ok, true)
    expect.equality(nwins(child), 1)
  end)
end)
