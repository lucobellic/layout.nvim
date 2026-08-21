---BDD tests for :checkhealth layout diagnostics.

local MiniTest = require('mini.test')
local U = require('tests.util')
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

describe('layout health check', function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd('set rtp+=' .. ROOT)
    child.lua([[
      _G.health_results = {}
      vim.health = {}
      for _, level in ipairs({ 'start', 'ok', 'info', 'warn', 'error' }) do
        vim.health[level] = function(message, advice)
          table.insert(_G.health_results, { level = level, message = message, advice = advice })
        end
      end
      function _G.run_layout_health()
        _G.health_results = {}
        package.loaded['layout.health'] = nil
        require('layout.health').check()
      end
      function _G.health_has(level, pattern)
        return vim.iter(_G.health_results):any(function(result)
          return result.level == level and result.message:match(pattern) ~= nil
        end)
      end
    ]])
  end)

  after_each(function()
    child.stop()
  end)

  it('reports setup as required when the plugin is not configured', function()
    -- Given: layout.nvim is installed but setup() has not run
    -- When: its health check runs
    child.lua([[_G.run_layout_health()]])

    -- Then: the report explains how to initialize the plugin
    expect.equality(child.lua_get([[_G.health_has('error', 'setup%(%) has not been called')]]), true)
  end)

  it('rejects unsupported Neovim versions', function()
    -- Given: layout.nvim is evaluated on Neovim older than 0.10
    child.lua([[vim.version = function() return { major = 0, minor = 9, patch = 5 } end]])

    -- When: its health check runs
    child.lua([[_G.run_layout_health()]])

    -- Then: the minimum supported version is reported
    expect.equality(child.lua_get([[_G.health_has('error', 'requires Neovim 0%.10 or newer')]]), true)
  end)

  it('reports configured groups, views, and writable workspace storage', function()
    -- Given: a valid setup with a writable workspace directory
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { views = { filesystem = { filter = 'toolL', open = 'echo' } } },
        },
      },
    })
    cfg.workspaces.dir = vim.fn.tempname() .. '-health'
    child.lua('_G.health_cfg = ' .. vim.inspect(cfg))
    child.lua([[require('layout').setup(_G.health_cfg)]])

    -- When: its health check runs
    child.lua([[_G.run_layout_health()]])

    -- Then: setup, registry, and deferred directory creation are healthy
    expect.equality(child.lua_get([[_G.health_has('ok', '1 group%(s%) and 1 view%(s%)')]]), true)
    expect.equality(child.lua_get([[_G.health_has('ok', 'will be created')]]), true)
    expect.equality(child.lua_get([[_G.health_has('error', '.')]]), false)
  end)

  it('reports a workspace path that is an existing file', function()
    -- Given: workspace storage points at a regular file
    child.lua([[
      _G.health_file = vim.fn.tempname()
      vim.fn.writefile({ 'not a directory' }, _G.health_file)
      require('layout').setup({
        workspaces = { auto_save = false, auto_restore = false, dir = _G.health_file },
      })
    ]])

    -- When: its health check runs
    child.lua([[_G.run_layout_health()]])

    -- Then: the invalid storage target is reported as an error
    expect.equality(child.lua_get([[_G.health_has('error', 'not a directory')]]), true)
    child.lua([[vim.fn.delete(_G.health_file)]])
  end)

  it('reports runtime registries that no longer match the configuration', function()
    -- Given: setup completed before the registered views were unexpectedly cleared
    local cfg = U.test_config({
      left = {
        groups = {
          explorer = { views = { filesystem = { filter = 'toolL', open = 'echo' } } },
        },
      },
    })
    child.lua('_G.health_cfg = ' .. vim.inspect(cfg))
    child.lua([[
      require('layout').setup(_G.health_cfg)
      require('layout.entities.view'):clear()
    ]])

    -- When: its health check runs
    child.lua([[_G.run_layout_health()]])

    -- Then: the registry mismatch is actionable
    expect.equality(child.lua_get([[_G.health_has('error', 'runtime registries are out of sync')]]), true)
  end)

  it('warns when a matching window has not been placed and tagged', function()
    -- Given: a matching tool buffer exists without panel arrangement metadata
    U.setup_config(
      child,
      U.test_config({
        left = {
          groups = {
            explorer = { views = { filesystem = { filter = 'toolL', open = 'echo' } } },
          },
        },
      })
    )
    child.lua([[
      local Layout = require('layout')
      Layout.config = require('layout.shared.config').merge(_G._c)
      Layout.registry = _G._reg
    ]])
    U.make_tool_win(child, 'toolL')

    -- When: its health check runs
    child.lua([[_G.run_layout_health()]])

    -- Then: the inconsistent window is identified
    expect.equality(child.lua_get([[_G.health_has('warn', 'inconsistent layout metadata')]]), true)
  end)

  it('accepts matching windows after panel placement', function()
    -- Given: a matching tool window has been arranged into its configured panel
    U.setup_config(
      child,
      U.test_config({
        left = {
          groups = {
            explorer = { views = { filesystem = { filter = 'toolL', open = 'echo' } } },
          },
        },
      })
    )
    child.lua([[
      local Layout = require('layout')
      Layout.config = require('layout.shared.config').merge(_G._c)
      Layout.registry = _G._reg
    ]])
    U.make_tool_win(child, 'toolL')
    child.lua([[require('layout.entities.panel'):arrange()]])

    -- When: its health check runs
    child.lua([[_G.run_layout_health()]])

    -- Then: managed-window metadata is healthy
    expect.equality(child.lua_get([[_G.health_has('ok', 'managed window%(s%) have consistent metadata')]]), true)
    expect.equality(child.lua_get([[_G.health_has('warn', 'inconsistent layout metadata')]]), false)
  end)
end)
