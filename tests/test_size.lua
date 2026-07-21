-- tests/test_size.lua
-- BDD scenarios for resolving the shared panel/view size option.

local MiniTest = require('mini.test')
local expect = MiniTest.expect

describe('shared size resolution', function()
  it('resolves a fraction against its container and floors the result', function()
    -- Given: a size expressed as a fraction of a 41-cell container
    -- When: the size is resolved
    local resolved = require('layout.shared.size').resolve(0.25, 41)

    -- Then: it occupies the floored proportional number of cells
    expect.equality(resolved, 10)
  end)

  it('keeps a positive integer as an absolute size', function()
    -- Given: a size expressed as an absolute row/column count
    -- When: the size is resolved against any container
    local resolved = require('layout.shared.size').resolve(12, 41)

    -- Then: the absolute count is unchanged
    expect.equality(resolved, 12)
  end)

  it('rejects zero, negative, and non-integral absolute sizes', function()
    -- Given: values which represent neither a fraction nor an absolute count
    -- When: each value is validated
    local Size = require('layout.shared.size')
    local zero_ok = pcall(Size.validate, 0)
    local negative_ok = pcall(Size.validate, -1)
    local decimal_ok = pcall(Size.validate, 1.5)

    -- Then: each invalid value is rejected
    expect.equality({ zero_ok, negative_ok, decimal_ok }, { false, false, false })
  end)

  it('converts transient dimensions into a valid representable fraction', function()
    -- Given: zero and oversized dimensions observed during resize churn
    local Size = require('layout.shared.size')

    -- When: each dimension is converted relative to its container
    local collapsed = Size.to_fraction(0, 40)
    local oversized = Size.to_fraction(50, 40)

    -- Then: both values remain valid fractions strictly between zero and one
    expect.equality(collapsed, 1 / 40)
    expect.equality(oversized, 39 / 40)
  end)
end)
