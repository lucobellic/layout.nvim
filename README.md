# layout.nvim

An opinionated panel manager for Neovim that brings standard IDE-style
window arrangements with reserved left/right/bottom panels, declarative view
configuration, persistent per-project layouts, and zero dependencies.

Requires Neovim 0.10 or newer.

## Setup

Groups and views are arrays because declaration order controls panel stacking,
statusline order, and picker order. A string filter matches `filetype`; a
function filter receives `(bufnr, winid)`.

```lua
require('layout').setup({
  left = {
    size = 30, -- cells, or a fraction such as 0.25
    groups = {
      {
        name = 'explorer',
        picker = { icon = 'E', key = 'e' },
        views = {
          {
            name = 'filesystem',
            filter = 'neo-tree',
            open = 'Neotree action=show source=filesystem position=left',
          },
        },
      },
    },
  },
  right = { size = 40, groups = {} },
  bottom = {
    size = 15,
    align = 'full', -- contained, left_aligned, right_aligned, or full
    groups = {},
  },
  events = { 'FileType', 'WinEnter', 'BufWinEnter' },
  live_resize_debounce = 250,
  workspaces = {
    auto_save = true,
    auto_restore = true,
    dir = vim.fn.stdpath('data') .. '/layout',
  },
})
```

Each view may also define `size`, `bo`, and `wo`. View `size` controls its
stacking dimension within the panel. `bo` and `wo` apply buffer-local and
window-local options after placement.

## Commands

- `:Layout toggle [side] <group>` opens or closes a group. The side is required when names are ambiguous.
- `:Layout close <left|right|bottom>` closes every group on a panel.
- `:Layout pick` prompts for a configured picker key.
- `:Layout save` writes the current workspace snapshot.
- `:Layout restore` replaces configured panel views with the saved snapshot.
- `:Layout forget` deletes the current workspace snapshot.

Public Lua helpers include `require('layout').pick([refresh])`,
`get_statusline(side)`, `toggle_rail()`, and
`set_buffer_enabled(bufnr, enabled)`. The last helper temporarily excludes an
already managed buffer from placement.

## Statusline And Rail

`get_statusline(side)` returns one statusline-formatted string per configured
group icon. Entries support active/inactive highlights, click regions, and
picker-key rendering.

The optional icon rail shows every configured group in a fixed-width window.
It can either float over the editor or reserve a normal buffer window:

```lua
require('layout').setup({
  statusline = {
    colors = {
      hover = 'PmenuSel', -- highlight linked by hovered rail icons
    },
    pick_key_pose = 'right_separator', -- rail maps separator poses to their side
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

The rail uses the existing statusline highlights, picker keys, `pick_key_pose`,
active state, and click handling. In picker mode, `left` and `left_separator`
place the key before the icon, `right` and `right_separator` place it after the
icon, and `icon` replaces the icon. Float mode overlays the outermost editor column. Buffer
mode reserves a fixed-width, full-height split outside all left, right,
and bottom panels. Buffer rails are clickable. While one is
entered, layout.nvim returns focus to an editor window so the rail can remain
narrower than the global `winwidth` without changing that option.

Toggle the configured rail globally at runtime:

```lua
require('layout').toggle_rail()
```

Icons wider than the configured rail are clipped by display width. Groups with
an icon but no key remain visible and clickable, but do not participate in
keyboard picking.

## Persistence

Workspace files are keyed by the current working directory. Automatic saving
runs after managed window changes and before a directory change or exit.
Automatic restoration applies the destination directory's exact saved set of
views; changing to a directory without a snapshot closes views inherited from
the previous workspace.

## Health Check

Run the built-in diagnostics after configuring the plugin:

```vim
:checkhealth layout
```

The report checks the Neovim version, setup and registry state, workspace
storage access, and metadata for managed windows in the current tabpage.

Each rail section selects a configured panel side. Unmapped sides are omitted.
When the sections do not fit at their ideal anchors, they are packed in top,
middle, bottom order.
