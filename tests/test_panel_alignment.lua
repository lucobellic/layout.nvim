-- tests/test_panel_alignment.lua
-- Verify that the four bottom-panel alignment modes
-- (contained, left_aligned, right_aligned, full) produce the
-- expected winlayout tree AND per-window geometry using only
-- native Neovim split commands (no plugin logic).

local U = require("tests.util")
local MiniTest = require("mini.test")
local expect = MiniTest.expect

describe("Bottom panel alignment", function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
  end)

  after_each(function()
    child.stop()
  end)

  describe("contained", function()
    it("places bottom under center only — left/right keep full height", function()
      -- Given: the base [L | C | R] row at fixed dimensions
      --   cols=122, lines=41 (leaves room for 2 vertical + 1 horizontal separator)
      local base = U.make_base(child)

      -- When: the contained alignment is applied (split center below)
      local wins = U.apply_contained(child, base)

      -- Then: the winlayout tree should nest center+its-bottom inside a column,
      --       while left and right remain top-level leaves
      local raw_tree = U.tree(child)
      local norm = U.normalize_tree(raw_tree)
      expect.equality(norm, U.EXPECTED.contained.tree)

      -- Then: per-window geometry matches expected positions and sizes
      local geo = U.geometry_by_tag(child, wins) -- wins has L, C_top, bottom, R
      for tagname, dims in pairs(U.EXPECTED.contained.geometry) do
        expect.equality(
          geo[tagname],
          dims,
          { fail_reason = "geometry mismatch for " .. tagname }
        )
      end
    end)
  end)

  describe("left_aligned", function()
    it("bottom spans left+center — right takes full height", function()
      -- Given: a fresh tabpage

      -- When: the left_aligned layout is built
      local wins = U.make_left_aligned(child)

      -- Then: the winlayout tree nests left, center, and bottom inside a
      --       column which sits in a row beside the right leaf
      local norm = U.normalize_tree(U.tree(child))
      expect.equality(norm, U.EXPECTED.left_aligned.tree)

      -- Then: per-window geometry — bottom spans L+C width (90), R stays full height
      local geo = U.geometry_by_tag(child, wins)
      for tagname, dims in pairs(U.EXPECTED.left_aligned.geometry) do
        expect.equality(
          geo[tagname],
          dims,
          { fail_reason = "geometry mismatch for " .. tagname }
        )
      end
    end)
  end)

  describe("right_aligned", function()
    it("bottom spans center+right — left takes full height", function()
      local wins = U.make_right_aligned(child)

      local norm = U.normalize_tree(U.tree(child))
      expect.equality(norm, U.EXPECTED.right_aligned.tree)

      local geo = U.geometry_by_tag(child, wins)
      for tagname, dims in pairs(U.EXPECTED.right_aligned.geometry) do
        expect.equality(
          geo[tagname],
          dims,
          { fail_reason = "geometry mismatch for " .. tagname }
        )
      end
    end)
  end)

  describe("full", function()
    it("bottom spans left+center+right — full width", function()
      local wins = U.make_full(child)

      local norm = U.normalize_tree(U.tree(child))
      expect.equality(norm, U.EXPECTED.full.tree)

      local geo = U.geometry_by_tag(child, wins)
      for tagname, dims in pairs(U.EXPECTED.full.geometry) do
        expect.equality(
          geo[tagname],
          dims,
          { fail_reason = "geometry mismatch for " .. tagname }
        )
      end
    end)
  end)
end)