# layout.nvim — Agent Instructions

## Features

Before implementing a new feature, define its expected behavior using
BDD-style scenarios (`describe`/`it` blocks). Each scenario must describe
the feature in plain terms: given a set of preconditions, when an action
occurs, then specific outcomes should be observed.

When the behavior is ambiguous or under-specified, pause and ask the user
to clarify before proceeding. Do not assume default behavior — validated
expectations prevent rework.

Example:

```lua
describe("Layout toggle", function()
  it("opens a view in the correct panel", function()
    -- Given: a view "neo-tree" declared on the left panel
    -- When:  the user runs :Layout toggle neo-tree
    -- Then:  a window opens in the left panel column
  end)

  it("closes an open view when toggled again", function()
    -- Given: "neo-tree" is already open in the left panel
    -- When:  the user runs :Layout toggle neo-tree
    -- Then:  the view closes and the panel width stays reserved
  end)
end)
```

## Code style

All Lua code must use LuaLS annotations for type documentation. See the
`luals` skill for the full conventions (`---@class`, `---@field`, `---@param`,
`---@return`, `---@type`, `---@alias`, `---@public`).

## Tests

Run tests using `scripts/run_tests.sh`
