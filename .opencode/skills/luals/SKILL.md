---
name: luals
description: >
  Use LuaLS (EmmyLua) annotations for all Lua type documentation. Apply
  @class/@field/@param/@return/@type/@alias annotations to new and modified
  code. Follow the layout.nvim conventions: prefixed type names, annotations
  on all functions, @public on module exports.
---

# LuaLS Documentation Style

All Lua code must use [LuaLS](https://luals.github.io/wiki/annotations)
(EmmyLua-style) annotations for type information and documentation. The Lua
language server uses these to provide completions, diagnostics, and hover
information.

## Type Definitions

Define shared types with `---@class` and `---@alias` at the top of the module,
before any code. Prefix type names with the module namespace (e.g. `Foo.Spec`,
`Foo.Plan`).

```lua
---@alias Foo.Align "left"|"right"|"full"

---@class Foo.Slot
---@field winid? integer
---@field bufnr? integer
---@field size? integer Stacking height/width

---@class Foo.Spec
---@field left? Foo.Regoin
---@field right? Foo.Regoin
---@field center? boolean
```

- Group related `---@class`, `---@alias`, and `---@field` definitions together.
- Use `?` suffix on `---@field` for optional fields.
- Add inline descriptions after the type for complex fields.

## Function Annotations

Every function — public and private — must carry `---@param` and `---@return`
annotations describing its types. Public module functions additionally use
`---@public`.

```lua
---@class Foo
local M = {}

---Compute the plan for the given spec.
---@public
---@param spec Foo.Spec
---@return Foo.Plan
function M.plan(spec)
  ...
end

---@param label string
---@return integer? width
---@return integer? height
local function desired_dims(label)
  ...
end
```

- Use multiple `---@return` lines for multiple return values.
- Make optional returns explicit with `?` suffix (e.g. `---@return integer?`).
- Prefix the module table with `---@class ModName` for type-aware completions.

## Variable Annotations

Use `---@type` to annotate module-level tables and variables where the type is
not obvious from context.

```lua
---@type table<string, string>
local SIDES = { left = "L", right = "R" }

---@type table<Foo.Align, fun(spec: Foo.Spec, root: integer, tagmap: Foo.Tagmap)>
local BUILDERS = {
  left = build_left,
  right = build_right,
}
```

- Prefer `table<K, V>` generic syntax for maps.
- Use `fun(args): ret` for function references.
- Annotate complex nested callbacks and data structures.

## Comment Convention

- `---` (triple dash): Doc comments for types and API documentation.
  These are consumed by the Lua language server.
- `--` (double dash): Regular inline explanatory text for developers.
  Not processed by the language server.

```lua
-- This is a regular comment explaining implementation intent.
---@param ... This is a type annotation for the language server.
local function foo(...) end
```

## Enum Aliases

For enumerated values, use `---@alias` with `---|` for member documentation:

```lua
---@alias DeviceSide
---| '"left"' # Left side of the device
---| '"right"' # Right side of the device
---| '"top"' # Top side
---| '"bottom"' # Bottom side
```

Each member can have an inline `# comment` for hover documentation.

## Do Not

- Omit `---@param`/`---@return` on any function — even local helpers.
- Use `---` doc comments for plain explanatory text; use `--` instead.
- Create types in function bodies — all type definitions go at module top.
- Skip `---@class` on the module table `M`.
