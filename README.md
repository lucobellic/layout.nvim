# layout.nvim

An opinionated panel manager for Neovim that brings standard IDE-style
window arrangements with reserved left/right/bottom panels, declarative view
configuration, persistent per-project layouts, and zero dependencies.

The optional icon rail shows every configured group in a fixed-width window.
It can either float over the editor or reserve a normal buffer window:

```lua
require('layout').setup({
  statusline = {
    colors = {
      hover = 'PmenuSel', -- highlight linked by hovered rail icons
    },
    rail = {
      enabled = true,
      hover = true, -- opt in to mouse hover highlighting
      mode = 'float', -- "float" (default) or "buffer"
      position = 'left', -- "left" or "right"
      width = 1, -- positive integer number of columns
      padding = 0, -- spaces before each icon, included in width
      groups = {
        top = 'left',
        middle = 'bottom',
        bottom = 'right',
      },
    },
  },
})
```

The rail uses the existing statusline highlights, picker keys, active state,
and click handling. Float mode overlays the outermost editor column. Buffer
mode reserves a fixed-width, full-height split outside all left, right,
and bottom panels. Buffer rails remain focusable and clickable. While one is
entered, layout.nvim returns focus to an editor window so the rail can remain
narrower than the global `winwidth` without changing that option.

Toggle the configured rail globally at runtime:

```lua
require('layout').toggle_rail()
```

Each rail section selects a configured panel side. Unmapped sides are omitted.
When the sections do not fit at their ideal anchors, they are packed in top,
middle, bottom order.
