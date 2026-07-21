--- tests/test_config.lua
--- Pure unit tests for config.normalize() — the config -> registry parser.
--- No child process needed; all tests run in the main Neovim process.

local MiniTest = require('mini.test')
local expect = MiniTest.expect
local config = require('layout.shared.config')

describe('config.normalize', function()
  describe('config parsing', function()
    it('parses a config into a structured registry', function()
      local cfg = config.merge({
        left = {
          size = 30,
          groups = {
            {
              name = 'explorer',
              picker = { icon = '', key = 'e' },
              views = {
                { name = 'filesystem', filter = 'neo-tree', open = 'Neotree' },
              },
            },
          },
        },
        right = {
          size = 40,
          groups = {
            {
              name = 'buffers',
              picker = { icon = '', key = 'b' },
              views = {
                {
                  name = 'buffers_view',
                  filter = function(buf)
                    return vim.bo[buf].filetype == 'neo-tree'
                  end,
                  open = 'Neotree',
                },
              },
            },
          },
        },
        bottom = {
          size = 15,
          groups = {
            {
              name = 'git',
              picker = { icon = '', key = 'g' },
              views = {
                {
                  name = 'git_status',
                  filter = function(buf)
                    local ft = vim.bo[buf].filetype
                    return ft == 'neo-tree' or ft == 'Trouble'
                  end,
                  open = 'Neotree',
                  size = 8,
                  bo = { buflisted = false },
                  wo = { number = false },
                },
              },
            },
          },
        },
      })

      local reg = config.normalize(cfg)

      expect.equality(reg.left.size, 30)
      expect.equality(reg.right.size, 40)
      expect.equality(reg.bottom.size, 15)

      expect.equality(reg.left.groups.explorer.icon, '')
      expect.equality(reg.left.groups.explorer.key, 'e')

      local v = reg.left.groups.explorer.views.filesystem
      expect.equality(v.filter, 'neo-tree')
      expect.equality(v.open, 'Neotree')

      v = reg.right.groups.buffers.views.buffers_view
      expect.equality(type(v.filter), 'function')
      expect.equality(v.open, 'Neotree')

      v = reg.bottom.groups.git.views.git_status
      expect.equality(type(v.filter), 'function')
      expect.equality(v.size, 8)
      expect.equality(v.bo.buflisted, false)
      expect.equality(v.wo.number, false)
    end)
  end)

  describe('entry filtering', function()
    it('skips view entries without a .filter field', function()
      local cfg = config.merge({
        left = {
          size = 30,
          groups = {
            {
              name = 'mygroup',
              picker = { icon = '', key = 'm' },
              views = {
                { name = 'real_view', filter = 'test', open = 'echo' },
                { name = 'not_a_view', some_random_key = true },
              },
            },
          },
        },
      })
      local reg = config.normalize(cfg)
      local g = reg.left.groups.mygroup
      expect.equality(g.views.real_view.filter, 'test')
      expect.equality(g.views.not_a_view, nil)
    end)
  end)

  describe('missing sides', function()
    it('produces empty groups for sides present only in defaults', function()
      local cfg = config.merge({
        left = {
          size = 30,
          groups = {
            {
              name = 'explorer',
              picker = { icon = '', key = 'e' },
              views = {
                { name = 'filesystem', filter = 'neo-tree', open = 'Neotree' },
              },
            },
          },
        },
      })
      local reg = config.normalize(cfg)
      expect.equality(reg.left ~= nil, true)
      expect.equality(reg.left.groups.explorer.views.filesystem.open, 'Neotree')
      -- defaults fill in right + bottom with empty groups
      expect.equality(reg.right.size, 40)
      expect.equality(reg.right.groups, {})
      expect.equality(reg.bottom.size, 15)
      expect.equality(reg.bottom.groups, {})
    end)
  end)

  describe('default size inheritance', function()
    it('uses the default size when a side has no explicit size', function()
      local cfg = config.merge({
        left = {
          groups = {
            {
              name = 'explorer',
              picker = { icon = '', key = 'e' },
              views = {
                { name = 'fs', filter = 'test', open = 'echo' },
              },
            },
          },
        },
      })
      local reg = config.normalize(cfg)
      expect.equality(reg.left.size, 30) -- default from config.merge
    end)

    it('preserves fractional panel and view sizes', function()
      -- Given: panel and view sizes expressed as fractions
      local cfg = config.merge({
        left = {
          size = 0.25,
          groups = {
            {
              name = 'explorer',
              views = {
                { name = 'filesystem', filter = 'test', open = 'echo', size = 0.5 },
              },
            },
          },
        },
      })

      -- When: the config is normalized
      local reg = config.normalize(cfg)

      -- Then: fractions remain unresolved until their container is known
      expect.equality(reg.left.size, 0.25)
      expect.equality(reg.left.groups.explorer.views.filesystem.size, 0.5)
    end)

    it('rejects an invalid configured size', function()
      -- Given: a panel size which is neither a fraction nor a positive integer
      local cfg = config.merge({ left = { size = 0 } })

      -- When: the config is normalized
      local ok = pcall(config.normalize, cfg)

      -- Then: setup fails instead of forwarding an invalid window dimension
      expect.equality(ok, false)
    end)
  end)

  describe('group and view registration', function()
    it('produces group and view order from array position', function()
      local cfg = {
        left = {
          size = 30,
          groups = {
            {
              name = 'git',
              picker = { icon = '', key = 'g' },
              views = {
                { name = 'status', filter = 'git', open = 'Git' },
                { name = 'log', filter = 'gitlog', open = 'GitLog' },
              },
            },
            {
              name = 'explorer',
              picker = { icon = '', key = 'e' },
              views = {
                { name = 'filesystem', filter = 'neo-tree', open = 'Neotree' },
              },
            },
          },
        },
      }
      cfg = config.merge(cfg)
      local reg = config.normalize(cfg)

      -- Groups in declaration order: git, explorer
      expect.equality(reg.left._order[1], 'git')
      expect.equality(reg.left._order[2], 'explorer')

      -- Views in git: status, log (declaration order)
      local g = reg.left.groups.git
      expect.equality(g._order[1], 'status')
      expect.equality(g._order[2], 'log')
      expect.equality(g.views.status.filter, 'git')
      expect.equality(g.views.log.filter, 'gitlog')

      -- Views in explorer: filesystem
      local e = reg.left.groups.explorer
      expect.equality(e._order[1], 'filesystem')
      expect.equality(e.views.filesystem.filter, 'neo-tree')
    end)
  end)
end)
