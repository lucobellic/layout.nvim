local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

describe('floating icon rail', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
    child.cmd('set laststatus=0 cmdheight=0 showtabline=0')
  end)

  after_each(function()
    child.stop()
  end)

  local function wait_for_rail()
    child.lua([[
      vim.wait(1000, function()
        return require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()] ~= nil
      end)
    ]])
  end

  it('shows all configured group icons without changing the split layout', function()
    -- Given: groups are configured across left, right, and bottom panels
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { picker = { icon = 'E', key = 'e' }, views = {} },
        },
      },
      right = {
        groups = {
          outline = { picker = { icon = 'O', key = 'o' }, views = {} },
        },
      },
      bottom = {
        groups = {
          terminal = { picker = { icon = 'T', key = 't' }, views = {} },
        },
      },
    })
    cfg.statusline = {
      rail = {
        enabled = true,
        position = 'left',
        groups = { top = 'left', middle = 'bottom', bottom = 'right' },
      },
    }

    -- When: layout is set up with the floating rail enabled
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()

    -- Then: left, bottom, and right icons occupy top, middle, and bottom
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    local height = child.api.nvim_win_get_height(rail.winid)
    local lines = child.api.nvim_buf_get_lines(rail.bufnr, 0, -1, false)
    expect.equality(lines[1], 'E')
    expect.equality(lines[math.floor((height - 1) / 2) + 1], 'T')
    expect.equality(lines[height], 'O')

    -- Then: the rail is a one-column float and the normal layout is unchanged
    local config = child.api.nvim_win_get_config(rail.winid)
    expect.equality(config.relative, 'editor')
    expect.equality(config.width, 1)
    expect.equality(config.col, 0)
    expect.equality(child.fn.winlayout()[1], 'leaf')
  end)

  it('shows icon-only groups that do not participate in keyboard picking', function()
    -- Given: a rail group has an icon but intentionally has no picker key
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { picker = { icon = 'E' }, views = {} },
        },
      },
    })
    cfg.statusline = { rail = { enabled = true, groups = { top = 'left' } } }

    -- When: the rail is rendered
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()

    -- Then: the configured icon is visible even without a key
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    expect.equality(child.api.nvim_buf_get_lines(rail.bufnr, 0, 1, false), { 'E' })
  end)

  it('does not render text wider than the configured rail', function()
    -- Given: a two-column glyph is configured in a one-column rail
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { picker = { icon = '界', key = 'e' }, views = {} },
        },
      },
    })
    cfg.statusline = { rail = { enabled = true, width = 1, groups = { top = 'left' } } }

    -- When: the rail is rendered
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()

    -- Then: its buffer content fits the window display width
    local width = child.lua_get([[(function()
      local rail = require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]
      return vim.fn.strdisplaywidth(vim.api.nvim_buf_get_lines(rail.bufnr, 0, 1, false)[1])
    end)()]])
    expect.equality(width <= 1, true)
  end)

  it('leaves user mouse settings untouched while disabled', function()
    -- Given: the user owns the global mouse mapping and mousemove option
    child.cmd([[nnoremap <LeftMouse> <Cmd>let g:user_mouse = 1<CR>]])
    child.o.mousemoveevent = false
    local before = child.fn.maparg('<LeftMouse>', 'n')

    -- When: layout is configured with its default disabled rail
    child.lua([[require('layout').setup({ statusline = { rail = { enabled = false } } })]])

    -- Then: setup did not install global rail interaction hooks
    expect.equality(child.fn.maparg('<LeftMouse>', 'n'), before)
    expect.equality(child.o.mousemoveevent, false)
  end)

  it('restores mouse settings when a hoverable rail is disabled', function()
    -- Given: rail setup temporarily enabled click interception and mouse movement
    child.cmd([[nnoremap <LeftMouse> <Cmd>let g:user_mouse = 1<CR>]])
    child.o.mousemoveevent = false
    local before = child.fn.maparg('<LeftMouse>', 'n')
    child.lua([[
      require('layout').setup({
        statusline = { rail = { enabled = true, hover = true, groups = {} } },
      })
    ]])

    -- When: setup is repeated with the rail disabled
    child.lua([[require('layout').setup({ statusline = { rail = { enabled = false } } })]])

    -- Then: the user's mapping and original option value are restored
    expect.equality(child.fn.maparg('<LeftMouse>', 'n'), before)
    expect.equality(child.o.mousemoveevent, false)
  end)

  it('aligns the rail to the far right after the editor is resized', function()
    -- Given: a right-aligned rail
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { picker = { icon = 'E', key = 'e' }, views = {} },
        },
      },
    })
    cfg.statusline = { rail = { enabled = true, width = 3, position = 'right', groups = { top = 'left' } } }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()

    -- When: the editor width changes and the rail is refreshed
    child.o.columns = 100
    child.lua([[require('layout.features.rail'):refresh()]])

    -- Then: its configured columns remain at the right editor edge
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    local config = child.api.nvim_win_get_config(rail.winid)
    expect.equality(config.width, 3)
    expect.equality(config.col, 97)
  end)

  local pick_pose_text = {
    left = { text = 'eE', highlights = { { 0, 1, 'LayoutPickInactiveLeft1' }, { 1, 2, 'LayoutInactiveLeft1' } } },
    left_separator = {
      text = 'eE',
      highlights = { { 0, 1, 'LayoutPickInactiveLeft1' }, { 1, 2, 'LayoutInactiveLeft1' } },
    },
    right = { text = 'Ee', highlights = { { 0, 1, 'LayoutInactiveLeft1' }, { 1, 2, 'LayoutPickInactiveLeft1' } } },
    right_separator = {
      text = 'Ee',
      highlights = { { 0, 1, 'LayoutInactiveLeft1' }, { 1, 2, 'LayoutPickInactiveLeft1' } },
    },
    icon = { text = 'e', highlights = { { 0, 1, 'LayoutPickInactiveLeft1' } } },
  }

  for pose, expected in pairs(pick_pose_text) do
    it(('uses the %s statusline pick-key pose in picker mode'):format(pose), function()
      -- Given: a rail with a configured icon, picker key, and statusline key pose
      local cfg = U.test_config({
        left = {
          groups = {
            explorer = { picker = { icon = 'E', key = 'e' }, views = {} },
          },
        },
      })
      cfg.statusline = {
        pick_key_pose = pose,
        rail = { enabled = true, width = 2, groups = { top = 'left' } },
      }
      child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
      wait_for_rail()

      -- When: picker mode is enabled and the rail is rendered
      child.lua([[
        require('layout.features.statusline').pick_mode = true
        require('layout.features.rail'):render()
      ]])

      -- Then: the key follows the pose and only the key receives the pick highlight
      local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
      expect.equality(child.api.nvim_buf_get_lines(rail.bufnr, 0, 1, false), { expected.text })
      local marks = child.api.nvim_buf_get_extmarks(rail.bufnr, -1, 0, -1, { details = true })
      local highlights = vim.tbl_map(function(mark)
        return { mark[3], mark[4].end_col, mark[4].hl_group }
      end, marks)
      expect.equality(highlights, expected.highlights)
    end)
  end

  it('adds configured left padding to icons and picker keys', function()
    -- Given: a four-column rail with two columns of left padding
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { picker = { icon = 'E', key = 'e' }, views = {} },
        },
      },
    })
    cfg.statusline = {
      rail = { enabled = true, width = 4, padding = 2, groups = { top = 'left' } },
    }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()

    -- When: the icon is rendered, then picker mode is enabled
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    local icon = child.api.nvim_buf_get_lines(rail.bufnr, 0, 1, false)
    child.lua([[
      require('layout.features.statusline').pick_mode = true
      require('layout.features.rail'):render()
    ]])

    -- Then: both values are indented without changing the configured rail width
    expect.equality(icon, { '  E' })
    expect.equality(child.api.nvim_buf_get_lines(rail.bufnr, 0, 1, false), { '  Ee' })
    expect.equality(child.api.nvim_win_get_width(rail.winid), 4)
  end)

  it('dispatches a rail row through the existing statusline click map', function()
    -- Given: a rail row backed by the first statusline entry
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = {
            picker = { icon = 'E', key = 'e' },
            views = { filesystem = { filter = 'leftft', open = 'belowright split' } },
          },
        },
      },
    })
    cfg.statusline = { rail = { enabled = true, groups = { top = 'left' } } }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local before = #child.api.nvim_tabpage_list_wins(0)

    -- When: the first rail row is clicked
    child.lua([[require('layout.features.rail'):on_click(1)]])

    -- Then: the existing toggle callback opens the matching group
    expect.equality(#child.api.nvim_tabpage_list_wins(0), before + 1)
  end)

  it('defers window creation when setup runs during tabline evaluation', function()
    -- Given: lazy setup is invoked by a tabline expression under textlock
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { picker = { icon = 'E', key = 'e' }, views = {} },
        },
      },
    })
    cfg.statusline = { rail = { enabled = true, groups = { top = 'left' } } }
    child.lua('_G._rail_cfg = ' .. vim.inspect(cfg))
    child.lua([[
      _G._setup_rail_from_tabline = function()
        require('layout').setup(_G._rail_cfg)
        return ''
      end
    ]])

    -- When: Neovim evaluates the expression
    local ok = child.lua_get([[
      pcall(vim.api.nvim_eval_statusline, '%!v:lua._setup_rail_from_tabline()', { winid = 0 })
    ]])

    -- Then: setup does not mutate windows under textlock, and the rail appears later
    expect.equality(ok, true)
    wait_for_rail()
  end)

  it('omits groups from panel sides not assigned to a rail section', function()
    -- Given: left and right panel groups but only right is assigned to the rail
    local cfg = U.test_config({
      left = {
        groups = {
          hidden = { picker = { icon = 'H', key = 'h' }, views = {} },
        },
      },
      right = {
        groups = {
          visible = { picker = { icon = 'V', key = 'v' }, views = {} },
        },
      },
    })
    cfg.statusline = { rail = { enabled = true, groups = { top = 'right' } } }

    -- When: the rail is created
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()

    -- Then: only the explicitly assigned group appears
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    local text = table.concat(child.api.nvim_buf_get_lines(rail.bufnr, 0, -1, false), '')
    expect.equality(text:find('V', 1, true) ~= nil, true)
    expect.equality(text:find('H', 1, true), nil)
  end)

  it('packs sections in order when their anchored ranges overlap', function()
    -- Given: more positioned icons than a three-row rail can anchor separately
    local cfg = U.test_config({
      left = {
        groups = {
          a = { picker = { icon = 'A', key = 'a' }, views = {} },
        },
      },
      bottom = {
        groups = {
          b = { picker = { icon = 'B', key = 'b' }, views = {} },
          c = { picker = { icon = 'C', key = 'c' }, views = {} },
        },
      },
      right = {
        groups = {
          d = { picker = { icon = 'D', key = 'd' }, views = {} },
        },
      },
    })
    cfg.statusline = {
      rail = { enabled = true, groups = { top = 'left', middle = 'bottom', bottom = 'right' } },
    }
    child.o.lines = 3

    -- When: the rail is created
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()

    -- Then: all icons remain packed in section and declaration order
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    expect.equality(child.api.nvim_buf_get_lines(rail.bufnr, 0, -1, false), { 'A', 'B', 'C', 'D' })
  end)
end)

describe('buffer icon rail', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
    child.cmd('set laststatus=0 cmdheight=0 showtabline=0 winminwidth=0 winminheight=0')
  end)

  after_each(function()
    child.stop()
  end)

  local function wait_for_rail()
    child.lua([[
      vim.wait(1000, function()
        local state = require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]
        return state ~= nil and vim.api.nvim_win_is_valid(state.winid)
      end)
    ]])
  end

  it('reserves an empty fixed-width normal window at the configured edge', function()
    -- Given: a right-positioned buffer rail whose configured side has no groups
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', width = 3, position = 'right', groups = { top = 'left' } },
    }

    -- When: the rail is set up and refreshed after an attempted resize
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    child.api.nvim_win_set_width(rail.winid, 7)
    child.lua([[require('layout.features.rail'):refresh()]])

    -- Then: it remains a normal, empty window of the configured width at the far right
    local position = child.api.nvim_win_get_position(rail.winid)
    expect.equality(child.api.nvim_win_get_config(rail.winid).relative, '')
    expect.equality(child.api.nvim_win_get_width(rail.winid), 3)
    expect.equality(position[2], child.o.columns - 3)
    expect.equality(#child.api.nvim_tabpage_list_wins(0), 2)
  end)

  it('preserves a user-defined global winwidth when creating the rail without focusing it', function()
    -- Given: a user-defined global winwidth and a configured narrow buffer rail
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', width = 3, position = 'left', groups = { top = 'left' } },
    }
    local editor = child.api.nvim_get_current_win()
    child.o.winwidth = 30

    -- When: the rail is created while the editor remains current
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    child.lua([[vim.wait(50)]])

    -- Then: creating and placing the rail does not leak its temporary minimum
    expect.equality(child.api.nvim_get_current_win(), editor)
    expect.equality(child.o.winwidth, 30)
  end)

  it('preserves winwidth set immediately after setup before deferred rail creation', function()
    -- Given: setup schedules creation of a narrow buffer rail
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', width = 3, position = 'left', groups = { top = 'left' } },
    }

    -- When: the user sets winwidth before deferred rail creation runs
    child.lua([[
      require('layout').setup(]] .. vim.inspect(cfg) .. [[)
      vim.o.winwidth = 30
    ]])
    wait_for_rail()
    child.lua([[vim.wait(50)]])

    -- Then: transient rail placement never changes the newer global value
    expect.equality(child.o.winwidth, 30)
  end)

  it('keeps its configured width without changing winwidth when entered', function()
    -- Given: a three-column buffer rail and a larger user-configured winwidth
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', width = 3, position = 'left', groups = { top = 'left' } },
    }
    child.o.winwidth = 30
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])

    -- When: the rail becomes the current window
    child.api.nvim_set_current_win(rail.winid)

    -- Then: focus is rejected synchronously so the narrow rail remains fixed
    expect.equality(child.api.nvim_get_current_win() ~= rail.winid, true)
    expect.equality(child.api.nvim_win_get_width(rail.winid), 3)
    expect.equality(child.o.winwidth, 30)
  end)

  it('toggles all buffer rails through the public API', function()
    -- Given: enabled buffer rails have been created in two tabs
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', width = 2, position = 'left', groups = { top = 'left' } },
    }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    child.cmd('tabnew')
    wait_for_rail()
    expect.equality(child.lua_get([[vim.tbl_count(require('layout.features.rail').state)]]), 2)

    -- When: the public rail API is toggled off
    child.lua([[require('layout').toggle_rail()]])

    -- Then: every tab's rail is hidden
    expect.equality(child.lua_get([[vim.tbl_count(require('layout.features.rail').state)]]), 0)
    expect.equality(#child.api.nvim_tabpage_list_wins(0), 1)

    -- When: the public rail API is toggled on
    child.lua([[require('layout').toggle_rail()]])
    wait_for_rail()
    child.cmd('tabprevious')
    wait_for_rail()

    -- Then: rails are shown again in both tabs
    expect.equality(child.lua_get([[vim.tbl_count(require('layout.features.rail').state)]]), 2)
  end)

  it('dispatches clicks without focusing the rail or changing winwidth', function()
    -- Given: a clickable buffer rail entry
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = {
            picker = { icon = 'E', key = 'e' },
            views = { filesystem = { filter = 'leftft', open = 'belowright split' } },
          },
        },
      },
    })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', position = 'left', groups = { top = 'left' } },
    }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    child.o.winwidth = 30

    -- When: the first icon is clicked while the editor remains focused
    local position = child.api.nvim_win_get_position(rail.winid)
    child.api.nvim_input_mouse('left', 'press', '', 0, position[1], position[2])
    child.api.nvim_input_mouse('left', 'release', '', 0, position[1], position[2])
    child.lua([[vim.wait(1000, function() return #vim.api.nvim_tabpage_list_wins(0) == 3 end)]])

    -- Then: the click opens the group without focusing the rail or changing options
    expect.equality(#child.api.nvim_tabpage_list_wins(0), 3)
    expect.equality(child.api.nvim_win_is_valid(rail.winid), true)
    expect.equality(child.api.nvim_get_current_win() ~= rail.winid, true)
    expect.equality(child.o.winwidth, 30)
  end)

  it('forwards clicks outside the rail to Neovim', function()
    -- Given: an enabled buffer rail and two lines in the focused editor
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', width = 3, position = 'left', groups = { top = 'left' } },
    }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local editor = child.api.nvim_get_current_win()
    child.api.nvim_buf_set_lines(0, 0, -1, false, { 'first', 'second' })

    -- When: the second editor line is clicked
    local position = child.api.nvim_win_get_position(editor)
    child.api.nvim_input_mouse('left', 'press', '', 0, position[1] + 1, position[2])
    child.api.nvim_input_mouse('left', 'release', '', 0, position[1] + 1, position[2])
    child.lua([[vim.wait(50)]])

    -- Then: normal mouse handling moves the editor cursor
    expect.equality(child.api.nvim_win_get_cursor(editor)[1], 2)
  end)

  it('highlights an icon while hovered and restores it when the mouse leaves', function()
    -- Given: a buffer rail with one inactive icon and mouse movement reporting
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = {
            picker = { icon = 'E', key = 'e' },
            views = { filesystem = { filter = 'leftft', open = 'belowright split' } },
          },
        },
      },
    })
    cfg.statusline = {
      rail = { enabled = true, hover = true, mode = 'buffer', position = 'left', groups = { top = 'left' } },
    }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])

    -- When: the mouse moves over the first icon
    child.lua([[
      local rail = require('layout.features.rail')
      rail:update_hover({ winid = rail.state[vim.api.nvim_get_current_tabpage()].winid, line = 1 })
    ]])

    -- Then: the icon uses its indexed hover highlight without taking focus
    local hovered = child.api.nvim_buf_get_extmarks(rail.bufnr, -1, 0, -1, { details = true })
    expect.equality(hovered[1][4].hl_group, 'LayoutHoverLeft1')
    expect.equality(child.api.nvim_get_current_win() ~= rail.winid, true)

    -- When: the mouse leaves the rail
    child.lua([[require('layout.features.rail'):update_hover({ winid = 0, line = 0 })]])

    -- Then: the icon returns to its inactive highlight
    local restored = child.api.nvim_buf_get_extmarks(rail.bufnr, -1, 0, -1, { details = true })
    expect.equality(restored[1][4].hl_group, 'LayoutInactiveLeft1')
  end)

  it('does not enable or apply hover behavior by default', function()
    -- Given: a rail without the opt-in hover option
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', position = 'left', groups = { top = 'left' } },
    }
    child.o.mousemoveevent = false

    -- When: the rail is set up and receives a synthetic hover update
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    child.lua([[
      local rail = require('layout.features.rail')
      rail:update_hover({ winid = rail.state[vim.api.nvim_get_current_tabpage()].winid, line = 1 })
    ]])

    -- Then: mouse movement reporting and hover state remain disabled
    expect.equality(child.o.mousemoveevent, false)
    local hover_enabled = child.lua_get([=[
      require('layout.features.rail').hover_line[vim.api.nvim_get_current_tabpage()] ~= nil
    ]=])
    expect.equality(hover_enabled, false)
    expect.equality(child.api.nvim_win_is_valid(rail.winid), true)
  end)

  it('recreates the reserved edge window after it is manually closed', function()
    -- Given: an empty left buffer rail
    local cfg = U.test_config({ left = { groups = {} } })
    cfg.statusline = {
      rail = { enabled = true, mode = 'buffer', position = 'left', groups = { top = 'left' } },
    }
    child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
    wait_for_rail()
    local original =
      child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()].winid]=])

    -- When: the user closes the rail window
    child.api.nvim_win_close(original, true)
    child.lua('_G._closed_rail = ' .. original)
    child.lua([[
      vim.wait(1000, function()
        local state = require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]
        return state and state.winid ~= _G._closed_rail and vim.api.nvim_win_is_valid(state.winid)
      end)
    ]])

    -- Then: a new fixed-width rail is reserved at the outer edge
    local rail = child.lua_get([=[require('layout.features.rail').state[vim.api.nvim_get_current_tabpage()]]=])
    expect.equality(child.api.nvim_win_get_width(rail.winid), 1)
    expect.equality(child.api.nvim_win_get_position(rail.winid)[2], 0)
  end)

  it('stays full-height outside panels for every bottom alignment', function()
    -- Given: left, right, and bottom views plus a left buffer rail
    for _, align in ipairs({ 'contained', 'left_aligned', 'right_aligned', 'full' }) do
      child.cmd('tabnew | only')
      child.o.columns = 122
      child.o.lines = 41
      local cfg = U.test_config({
        left = {
          size = 20,
          groups = {
            left = {
              picker = { icon = 'L', key = 'l' },
              views = {
                view = { filter = 'railleft', open = 'echo' },
              },
            },
          },
        },
        right = {
          size = 20,
          groups = {
            right = {
              picker = { icon = 'R', key = 'r' },
              views = {
                view = { filter = 'railright', open = 'echo' },
              },
            },
          },
        },
        bottom = {
          size = 8,
          align = align,
          groups = {
            bottom = {
              picker = { icon = 'B', key = 'b' },
              views = {
                view = { filter = 'railbottom', open = 'echo' },
              },
            },
          },
        },
      })
      cfg.statusline = {
        rail = {
          enabled = true,
          mode = 'buffer',
          position = 'left',
          groups = { top = 'left', middle = 'bottom', bottom = 'right' },
        },
      }
      child.lua('require("layout").setup(' .. vim.inspect(cfg) .. ')')
      wait_for_rail()
      child.lua([[
        require('layout.entities.panel.model.size'):clear()
        local eventignore = vim.o.eventignore
        vim.o.eventignore = 'all'
        for _, ft in ipairs({ 'railleft', 'railright', 'railbottom' }) do
          vim.cmd('vsplit')
          vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))
          vim.bo.filetype = ft
        end
        vim.o.eventignore = eventignore
        require('layout.entities.panel'):arrange()
      ]])

      -- When: placement applies the requested bottom alignment
      local geometry = child.lua_get([[(function()
        local result = {}
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local ok, slot = pcall(vim.api.nvim_win_get_var, win, 'layout_slot')
          if ok then
            local pos = vim.api.nvim_win_get_position(win)
            result[slot] = {
              row = pos[1], col = pos[2], width = vim.api.nvim_win_get_width(win),
              height = vim.api.nvim_win_get_height(win),
            }
          end
        end
        return result
      end)()]])

      -- Then: the rail wraps the complete layout and panel widths stay configured
      expect.equality(geometry.Q.row, 0)
      expect.equality(geometry.Q.col, 0)
      expect.equality(geometry.Q.width, 1)
      expect.equality(geometry.Q.height > geometry.B1.height, true)
      expect.equality(geometry.L1.width, 20)
      expect.equality(geometry.R1.width, 20, { fail_reason = 'right panel width for ' .. align })
      expect.equality(geometry.B1.col > geometry.Q.col, true)
    end
  end)
end)
