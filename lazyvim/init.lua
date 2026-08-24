local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')

vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyDone',
  once = true,
  callback = function()
    vim.schedule(function()
      vim.cmd('Neotree action=show source=filesystem position=left')
      vim.cmd('Neotree action=show source=buffers position=right')
      vim.cmd('Neotree action=show source=git_status position=bottom')
    end)
  end,
})

require('lazy').setup({
  spec = {
    {
      dir = repo_root,
      name = 'layout.nvim',
      lazy = false,
      keys = {
        {
          '<leader>;',
          function()
            require('layout').pick()
          end,
          desc = 'Layout Pick',
          mode = { 'n', 'v' },
        },
        { '<leader>wh', '<cmd>Layout close left<cr>', desc = 'Layout Close Left' },
        { '<leader>wl', '<cmd>Layout close right<cr>', desc = 'Layout Close Right' },
        { '<leader>wj', '<cmd>Layout close bottom<cr>', desc = 'Layout Close Bottom' },
      },
      opts = {
        left = {
          size = 30,
          groups = {
            {
              name = 'explorer',
              picker = { icon = '', key = 'e' },
              views = {
                {
                  name = 'filesystem',
                  filter = function(buf)
                    return vim.bo[buf].filetype == 'neo-tree' and vim.b[buf].neo_tree_source == 'filesystem'
                  end,
                  open = 'Neotree action=show source=filesystem position=left',
                },
              },
            },
          },
        },
        right = {
          size = 40,
          groups = {
            {
              name = 'buffers',
              picker = { icon = '', key = 'l' },
              views = {
                {
                  name = 'buffers_view',
                  filter = function(buf)
                    return vim.bo[buf].filetype == 'neo-tree' and vim.b[buf].neo_tree_source == 'buffers'
                  end,
                  open = 'Neotree action=show source=buffers position=right',
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
              picker = { icon = '', key = 'b' },
              views = {
                {
                  name = 'git_status',
                  filter = function(buf)
                    return vim.bo[buf].filetype == 'neo-tree' and vim.b[buf].neo_tree_source == 'git_status'
                  end,
                  open = 'Neotree action=show source=git_status position=bottom',
                },
              },
            },
          },
        },
      },
    },
    {
      'nvim-neo-tree/neo-tree.nvim',
      branch = 'v3.x',
      dependencies = {
        'nvim-lua/plenary.nvim',
        'MunifTanjim/nui.nvim',
        'nvim-tree/nvim-web-devicons',
      },
      lazy = false,
      opts = {
        window = {
          position = 'left',
          width = 30,
        },
      },
    },
  },
  install = {
    colorscheme = { 'habamax' },
  },
  checker = {
    enabled = false,
  },
  change_detection = {
    enabled = false,
  },
})
