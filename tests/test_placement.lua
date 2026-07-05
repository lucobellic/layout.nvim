-- tests/test_placement.lua
-- BDD scenarios for the window placement engine
-- (lua/layout/shared/placement.lua). Verifies tree shape, per-slot
-- geometry, window identity preservation, and idempotency, using the same
-- child-process + winlayout approach as test_panel_alignment.lua.

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect

-- Project root on the child's rtp so `require("layout.shared.placement")`
-- resolves inside the headless child process.
local ROOT = vim.fn.getcwd()

describe('placement.place', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
  end)

  after_each(function()
    child.stop()
  end)

  --------------------------------------------------------------------------------
  -- Helper: run placement inside the child.
  --------------------------------------------------------------------------------
  local function place(spec)
    child.lua(
      [[
      local P = require("layout.shared.placement")
      P.place(...)
    ]],
      { spec }
    )
  end

  local function norm_tree()
    return U.normalize_tree(U.tree(child))
  end

  local function geo_by_slot()
    return U.geometry_by_tag(child, U.slots_by_tag(child))
  end

  --------------------------------------------------------------------------------
  -- from a single editor window
  --------------------------------------------------------------------------------
  describe('from a single editor window', function()
    it('places one left window as a full-height left column', function()
      -- Given: an editor and a tool window in a flat row
      local wins, bufs = U.make_scattered(child, { 'editor', 'toolL' })

      -- When: toolL is placed into the left panel (size 30)
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
      })

      -- Then: tree is row[ L1 | C ]
      expect.equality(norm_tree(), { 'row', { { 'leaf' }, { 'leaf' } } })

      -- Then: geometry — L1 left full height width 30, C fills the rest
      local geo = geo_by_slot()
      expect.equality(geo.L1, { row = 0, col = 0, width = 30, height = 41 })
      expect.equality(geo.C, { row = 0, col = 31, width = 91, height = 41 })

      -- Then: the tool buffer landed in the L1 slot
      expect.equality(U.slot_buf(child, 'L1'), bufs.toolL)
    end)

    it('places left+right+bottom (contained) reproducing the canonical tree', function()
      -- Given: editor + three tools, flat row
      local wins, bufs = U.make_scattered(child, { 'editor', 'toolL', 'toolR', 'toolB' })

      -- When: placed contained
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'contained', slots = { { winid = wins.toolB } } },
      })

      -- Then: canonical contained tree
      expect.equality(norm_tree(), U.EXPECTED.contained.tree)

      -- Then: canonical geometry, relabeled by slot
      local geo = geo_by_slot()
      expect.equality(geo.L1, U.EXPECTED.contained.geometry.L)
      expect.equality(geo.C, U.EXPECTED.contained.geometry.C_top)
      expect.equality(geo.B1, U.EXPECTED.contained.geometry.bottom)
      expect.equality(geo.R1, U.EXPECTED.contained.geometry.R)
    end)
  end)

  --------------------------------------------------------------------------------
  -- from several unassigned windows
  --------------------------------------------------------------------------------
  describe('from several unassigned windows', function()
    it('collects each tool into its declared region, leaving the editor as center', function()
      -- Given: two editors and two tools scattered in a row
      local wins, bufs = U.make_scattered(child, { 'ed1', 'toolL', 'ed2', 'toolR' })

      -- When: tools are placed left + right
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
      })

      -- Then: tools reach the edges while both unassigned editor windows survive
      local slots = U.slots_by_tag(child)
      expect.equality(slots.L1, wins.toolL)
      expect.equality(slots.R1, wins.toolR)
      expect.equality(#child.api.nvim_tabpage_list_wins(0), 4)
      expect.equality(child.api.nvim_win_is_valid(wins.ed1), true)
      expect.equality(child.api.nvim_win_is_valid(wins.ed2), true)
      expect.equality(U.geometry(child, wins.toolL).col, 0)
      expect.equality(U.geometry(child, wins.toolR).col, 92)
      expect.equality(U.slot_buf(child, 'L1'), bufs.toolL)
      expect.equality(U.slot_buf(child, 'R1'), bufs.toolR)
    end)
  end)

  --------------------------------------------------------------------------------
  -- multi-window stacking
  --------------------------------------------------------------------------------
  describe('multi-window stacking', function()
    it('stacks two views vertically in the left panel', function()
      -- Given: editor + two tools
      local wins, bufs = U.make_scattered(child, { 'editor', 't1', 't2' })

      -- When: both tools stacked in the left panel (sizes sum to col height - sep)
      place({
        left = {
          size = 30,
          slots = { { winid = wins.t1, size = 15 }, { winid = wins.t2, size = 25 } },
        },
      })

      -- Then: tree is row[ col(L1, L2) | C ]
      expect.equality(norm_tree(), { 'row', { { 'col', { { 'leaf' }, { 'leaf' } } }, { 'leaf' } } })

      local geo = geo_by_slot()
      expect.equality(geo.L1, { row = 0, col = 0, width = 30, height = 15 })
      expect.equality(geo.L2, { row = 16, col = 0, width = 30, height = 25 })
      expect.equality(geo.C, { row = 0, col = 31, width = 91, height = 41 })
    end)

    it('gives a size-less slot the remaining height (flex) when a sibling has a size', function()
      -- Given: editor + two tools, both un-sized initially
      local wins, bufs = U.make_scattered(child, { 'editor', 't1', 't2' })

      -- When: both stacked in the left panel; t1 has no size (flex),
      -- t2 has size 25.  Column height is 41, minus 1 separator = 40,
      -- so the flex slot L1 should take 40 - 25 = 15.
      place({
        left = {
          size = 30,
          slots = { { winid = wins.t1 }, { winid = wins.t2, size = 25 } },
        },
      })

      local geo = geo_by_slot()
      expect.equality(geo.L1.height, 15)
      expect.equality(geo.L2.height, 25)
    end)

    it('splits the panel height equally when all slots are size-less (flex)', function()
      -- Given: editor + two tools, none sized
      local wins, bufs = U.make_scattered(child, { 'editor', 't1', 't2' })

      -- When: both stacked in the left panel with no per-view size.
      -- Column height is 41, minus 1 separator = 40, split equally => 20/20.
      place({
        left = {
          size = 30,
          slots = { { winid = wins.t1 }, { winid = wins.t2 } },
        },
      })

      local geo = geo_by_slot()
      expect.equality(geo.L1.height, 20)
      expect.equality(geo.L2.height, 20)
    end)

    it('distributes remainder to the last flex slot when four views are un-sized', function()
      -- Given: editor + four tools, none sized
      local wins, bufs = U.make_scattered(child, { 'editor', 't1', 't2', 't3', 't4' })

      -- When: four stacked in the left panel with no per-view size.
      -- Column height 41, 3 separators => 38, floor(38/4)=9, remainder 2
      -- => 9/9/9/11 (last flex slot takes the extra 2).
      place({
        left = {
          size = 30,
          slots = {
            { winid = wins.t1 },
            { winid = wins.t2 },
            { winid = wins.t3 },
            { winid = wins.t4 },
          },
        },
      })

      local geo = geo_by_slot()
      expect.equality(geo.L1.height, 9)
      expect.equality(geo.L2.height, 9)
      expect.equality(geo.L3.height, 9)
      expect.equality(geo.L4.height, 11)
    end)

    it('splits the bottom panel width equally when all slots are size-less (flex)', function()
      -- Given: editor + two tools
      local wins, bufs = U.make_scattered(child, { 'editor', 'b1', 'b2' })

      -- When: both stacked in the bottom panel with no per-view size.
      -- Bottom row width = 122 (full), 1 separator => 121, split => 60/61.
      place({
        bottom = {
          size = 15,
          align = 'full',
          slots = { { winid = wins.b1 }, { winid = wins.b2 } },
        },
      })

      local geo = geo_by_slot()
      expect.equality(geo.B1.width + geo.B2.width, 121)
      expect.equality(math.abs(geo.B1.width - geo.B2.width) <= 1, true)
    end)

    it('stacks two views horizontally in the bottom panel', function()
      -- Given: editor + two tools
      local wins, bufs = U.make_scattered(child, { 'editor', 'b1', 'b2' })

      -- When: both stacked in the bottom panel (widths sum to full width - sep)
      place({
        bottom = {
          size = 15,
          align = 'contained',
          slots = { { winid = wins.b1, size = 60 }, { winid = wins.b2, size = 61 } },
        },
      })

      -- Then: tree is col[ C, row(B1, B2) ]
      expect.equality(norm_tree(), { 'col', { { 'leaf' }, { 'row', { { 'leaf' }, { 'leaf' } } } } })

      local geo = geo_by_slot()
      expect.equality(geo.C, { row = 0, col = 0, width = 122, height = 25 })
      expect.equality(geo.B1, { row = 26, col = 0, width = 60, height = 15 })
      expect.equality(geo.B2, { row = 26, col = 61, width = 61, height = 15 })
    end)
  end)

  --------------------------------------------------------------------------------
  -- bottom panel alignment (reproduces the 4 canonical layouts via the API)
  --------------------------------------------------------------------------------
  describe('bottom panel alignment', function()
    local function scenario(name, align, builder)
      it(name, function()
        local wins, bufs = U.make_scattered(child, { 'editor', 'toolL', 'toolR', 'toolB' })
        builder(wins, bufs)
        expect.equality(norm_tree(), U.EXPECTED[align].tree)
        local geo = geo_by_slot()
        local exp = U.EXPECTED[align].geometry
        expect.equality(geo.L1, exp.L)
        expect.equality(geo.C, exp.C_top or exp.C)
        expect.equality(geo.B1, exp.bottom)
        expect.equality(geo.R1, exp.R)
      end)
    end

    scenario('contained', 'contained', function(wins)
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'contained', slots = { { winid = wins.toolB } } },
      })
    end)

    scenario('left_aligned', 'left_aligned', function(wins)
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'left_aligned', slots = { { winid = wins.toolB } } },
      })
    end)

    scenario('right_aligned', 'right_aligned', function(wins)
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'right_aligned', slots = { { winid = wins.toolB } } },
      })
    end)

    scenario('full', 'full', function(wins)
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'full', slots = { { winid = wins.toolB } } },
      })
    end)
  end)

  describe('corrective relocation', function()
    it('preserves every source window id while correcting a scattered layout', function()
      -- Given: editor and tool windows with stable handles and local state
      local wins = U.make_scattered(child, { 'editor', 'toolL', 'toolR', 'toolB' })
      child.api.nvim_win_set_var(wins.toolL, 'preserved', 'yes')

      -- When: all tools are relocated into their regions
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'contained', slots = { { winid = wins.toolB } } },
      })

      -- Then: placement moved the original windows instead of rebuilding them
      local slots = U.slots_by_tag(child)
      expect.equality(slots.L1, wins.toolL)
      expect.equality(slots.R1, wins.toolR)
      expect.equality(slots.B1, wins.toolB)
      expect.equality(slots.C, wins.editor)
      expect.equality(child.api.nvim_win_get_var(wins.toolL, 'preserved'), 'yes')
    end)

    it('is idempotent when the windows already occupy the target shape', function()
      -- Given: a correctly placed layout
      local wins = U.make_scattered(child, { 'editor', 'toolL', 'toolR', 'toolB' })
      local spec = {
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'full', slots = { { winid = wins.toolB } } },
      }
      place(spec)
      local before = U.tree(child)

      -- When: the same placement is requested again
      place(spec)

      -- Then: the exact window tree, including leaf ids, is unchanged
      expect.equality(U.tree(child), before)
    end)

    it('is idempotent while preserving multiple center editor splits', function()
      -- Given: two editor splits surrounded by correctly placed tools
      local wins = U.make_scattered(child, { 'ed1', 'toolL', 'ed2', 'toolR' })
      local spec = {
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
      }
      place(spec)
      local before = U.tree(child)

      -- When: the same placement is requested again
      place(spec)

      -- Then: the full center subtree and all concrete window IDs survive
      expect.equality(U.tree(child), before)
      expect.equality(child.api.nvim_win_is_valid(wins.ed1), true)
      expect.equality(child.api.nvim_win_is_valid(wins.ed2), true)
    end)

    it('corrects size drift without changing the window tree', function()
      -- Given: a placed layout whose left width was manually changed
      local wins = U.make_scattered(child, { 'editor', 'toolL', 'toolR' })
      local spec = {
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
      }
      place(spec)
      child.api.nvim_win_set_width(wins.toolL, 35)
      local before = U.tree(child)

      -- When: placement runs again
      place(spec)

      -- Then: only geometry is corrected
      expect.equality(U.tree(child), before)
      expect.equality(child.api.nvim_win_get_width(wins.toolL), 30)
    end)
  end)

  --------------------------------------------------------------------------------
  -- window tagging
  --------------------------------------------------------------------------------
  describe('window tagging', function()
    it('sets layout_managed on panel windows and not on the center', function()
      -- Given: editor + three tools, flat row
      local wins = U.make_scattered(child, { 'editor', 'toolL', 'toolR', 'toolB' })

      -- When: tools are placed in their respective panels
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
        bottom = { size = 15, align = 'contained', slots = { { winid = wins.toolB } } },
      })
      local slots = U.slots_by_tag(child)

      -- Then: panel windows carry layout_managed = true
      local function is_managed(label)
        return child.api.nvim_win_get_var(slots[label], 'layout_managed')
      end
      expect.equality(is_managed('L1'), true)
      expect.equality(is_managed('R1'), true)
      expect.equality(is_managed('B1'), true)

      -- Then: the center window does NOT carry layout_managed
      local ok = pcall(child.api.nvim_win_get_var, slots.C, 'layout_managed')
      expect.equality(ok, false)
    end)

    it('clears layout_managed from windows no longer in panels', function()
      -- Given: a layout with left + right panels
      local wins = U.make_scattered(child, { 'editor', 'toolL', 'toolR' })
      place({
        left = { size = 30, slots = { { winid = wins.toolL } } },
        right = { size = 30, slots = { { winid = wins.toolR } } },
      })

      -- Then: toolL is managed
      expect.equality(child.api.nvim_win_get_var(wins.toolL, 'layout_managed'), true)

      -- When: toolL is removed from the layout (only right remains)
      place({
        right = { size = 30, slots = { { winid = wins.toolR } } },
      })

      -- Then: toolL no longer has layout_managed
      local ok = pcall(child.api.nvim_win_get_var, wins.toolL, 'layout_managed')
      expect.equality(ok, false)

      -- Then: toolR is still managed
      expect.equality(child.api.nvim_win_get_var(wins.toolR, 'layout_managed'), true)
    end)
  end)

  --------------------------------------------------------------------------------
  -- center window preservation
  --------------------------------------------------------------------------------
  describe('center window preservation', function()
    it('does not equalize center windows when equalalways is on and a panel is placed', function()
      -- Given: two editor windows stacked vertically with unequal heights
      U.prepare(child)
      child.cmd('set equalalways')

      local ed1 = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed1, U.named_buf(child, 'ed1'))
      U.tag_window(child, ed1, 'ed1')

      child.cmd('belowright split')
      local ed2 = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed2, U.named_buf(child, 'ed2'))
      U.tag_window(child, ed2, 'ed2')

      child.api.nvim_win_set_height(ed1, 25)
      child.api.nvim_win_set_height(ed2, 15)

      -- And: a tool window opened to the left
      child.cmd('topleft vsplit')
      local toolL = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolL, U.named_buf(child, 'toolL'))

      expect.equality(child.api.nvim_win_get_height(ed1), 25)
      expect.equality(child.api.nvim_win_get_height(ed2), 15)

      -- When: the tool window is placed into the left panel
      place({
        left = { size = 30, slots = { { winid = toolL } } },
      })

      -- Then: center windows keep their heights — NOT equalized to 20/20
      expect.equality(child.api.nvim_win_get_height(ed1), 25)
      expect.equality(child.api.nvim_win_get_height(ed2), 15)
    end)

    it('preserves center window widths with equalalways on', function()
      -- Given: two editor windows side-by-side with unequal widths
      U.prepare(child)
      child.cmd('set equalalways')

      local ed1 = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed1, U.named_buf(child, 'ed1'))
      U.tag_window(child, ed1, 'ed1')

      child.cmd('rightbelow vsplit')
      local ed2 = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed2, U.named_buf(child, 'ed2'))
      U.tag_window(child, ed2, 'ed2')

      child.api.nvim_win_set_width(ed1, 80)
      child.api.nvim_win_set_width(ed2, 41)
      expect.equality(child.api.nvim_win_get_width(ed1) ~= child.api.nvim_win_get_width(ed2), true)

      local ratio_before = child.api.nvim_win_get_width(ed1) / child.api.nvim_win_get_width(ed2)

      -- And: a tool window for the bottom panel
      child.cmd('aboveleft split')
      local toolB = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolB, U.named_buf(child, 'toolB'))

      -- When: the tool window is placed into the bottom panel (full align)
      place({
        bottom = { size = 15, align = 'full', slots = { { winid = toolB } } },
      })

      -- Then: center windows keep their width ratio — NOT equalized
      local w1 = child.api.nvim_win_get_width(ed1)
      local w2 = child.api.nvim_win_get_width(ed2)
      expect.equality(w1 ~= w2, true)
      local ratio_after = w1 / w2
      expect.equality(math.abs(ratio_before - ratio_after) < 0.1, true)
    end)
  end)

  --------------------------------------------------------------------------------
  -- panel size stability under center splits
  --------------------------------------------------------------------------------
  describe('panel size stability under center splits', function()
    it('bottom panel height does not shrink when opening center splits (winminheight=0)', function()
      -- Given: a placed layout with a bottom panel and one center window.
      -- winminheight=0 lets the engine freely shrink the center frame
      -- instead of pushing the bottom panel upward.
      U.prepare(child)
      child.cmd('set winminheight=0 winminwidth=0 equalalways')

      local ed = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed, U.named_buf(child, 'ed'))
      U.tag_window(child, ed, 'ed')

      child.cmd('belowright split')
      local toolB = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolB, U.named_buf(child, 'toolB'))

      place({
        bottom = { size = 15, align = 'full', slots = { { winid = toolB } } },
      })

      local h_before = child.api.nvim_win_get_height(toolB)
      expect.equality(h_before, 15)

      -- When: the user opens several center splits in a row.
      -- equalalways equalizes non-fixed windows; winfixheight on the
      -- bottom panel protects it; winminheight=0 lets center shrink to 0.
      for i = 1, 5 do
        child.api.nvim_set_current_win(ed)
        child.cmd('belowright split')
        local w = child.api.nvim_get_current_win()
        child.api.nvim_win_set_buf(w, U.named_buf(child, 'c' .. i))
      end

      -- Then: the bottom panel height is unchanged — center splits shrank
      -- the center frame, not the bottom panel.
      expect.equality(child.api.nvim_win_get_height(toolB), h_before)
    end)

    it('bottom panel height does not grow when closing center splits (winminheight=0)', function()
      -- Given: a placed layout with a bottom panel and several center splits.
      U.prepare(child)
      child.cmd('set winminheight=0 winminwidth=0 equalalways')

      local ed = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed, U.named_buf(child, 'ed'))
      U.tag_window(child, ed, 'ed')

      child.cmd('belowright split')
      local toolB = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolB, U.named_buf(child, 'toolB'))

      place({
        bottom = { size = 15, align = 'full', slots = { { winid = toolB } } },
      })

      local center_wins = {}
      for i = 1, 5 do
        child.api.nvim_set_current_win(ed)
        child.cmd('belowright split')
        local w = child.api.nvim_get_current_win()
        child.api.nvim_win_set_buf(w, U.named_buf(child, 'c' .. i))
        center_wins[#center_wins + 1] = w
      end

      local h_before = child.api.nvim_win_get_height(toolB)
      expect.equality(h_before, 15)

      -- When: the user closes the center splits one at a time
      for _, w in ipairs(center_wins) do
        child.api.nvim_win_close(w, true)
      end

      -- Then: the bottom panel height is restored exactly — no surplus
      -- from winminheight pushing the center frame downward.
      expect.equality(child.api.nvim_win_get_height(toolB), 15)
    end)

    it('bottom panel stays stable when center splits opened with left panel present (full align)', function()
      -- Given: a placed layout with left + bottom panels (full align).
      U.prepare(child)
      child.cmd('set winminheight=0 winminwidth=0 equalalways')

      local ed = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed, U.named_buf(child, 'ed'))

      child.cmd('topleft vsplit')
      local toolL = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolL, U.named_buf(child, 'toolL'))

      child.cmd('wincmd l') -- back to editor
      child.cmd('belowright split')
      local toolB = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolB, U.named_buf(child, 'toolB'))

      place({
        left = { size = 30, slots = { { winid = toolL } } },
        bottom = { size = 15, align = 'full', slots = { { winid = toolB } } },
      })

      local h_before = child.api.nvim_win_get_height(toolB)
      expect.equality(h_before, 15)

      -- When: the user opens several center splits
      child.api.nvim_set_current_win(ed)
      for i = 1, 5 do
        child.cmd('belowright split')
        local w = child.api.nvim_get_current_win()
        child.api.nvim_win_set_buf(w, U.named_buf(child, 'c' .. i))
        child.api.nvim_set_current_win(ed)
      end

      -- Then: the bottom panel height is unchanged
      local h_after = child.api.nvim_win_get_height(toolB)
      expect.equality(h_after, h_before)
    end)

    it('bottom panel stays stable when center splits opened with left panel present (contained align)', function()
      -- Given: a placed layout with left + bottom panels (contained align).
      U.prepare(child)
      child.cmd('set winminheight=0 winminwidth=0 equalalways')

      local ed = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(ed, U.named_buf(child, 'ed'))

      child.cmd('topleft vsplit')
      local toolL = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolL, U.named_buf(child, 'toolL'))

      child.cmd('wincmd l') -- back to editor
      child.cmd('belowright split')
      local toolB = child.api.nvim_get_current_win()
      child.api.nvim_win_set_buf(toolB, U.named_buf(child, 'toolB'))

      place({
        left = { size = 30, slots = { { winid = toolL } } },
        bottom = { size = 15, align = 'contained', slots = { { winid = toolB } } },
      })

      local h_before = child.api.nvim_win_get_height(toolB)
      expect.equality(h_before, 15)

      -- When: the user opens several center splits
      child.api.nvim_set_current_win(ed)
      for i = 1, 5 do
        child.cmd('belowright split')
        local w = child.api.nvim_get_current_win()
        child.api.nvim_win_set_buf(w, U.named_buf(child, 'c' .. i))
        child.api.nvim_set_current_win(ed)
      end

      -- Then: the bottom panel height is unchanged
      local h_after = child.api.nvim_win_get_height(toolB)
      expect.equality(h_after, h_before)
    end)
  end)
end)
