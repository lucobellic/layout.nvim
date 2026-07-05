--- tests/test_persistence.lua
--- Unit tests for persistence modules: shared/lib, shared/store,
--- features/save, features/restore.
---
--- cwd_hash is a pure test. The rest require a child process (file IO / windows).

local U = require("tests.util")
local MiniTest = require("mini.test")
local expect = MiniTest.expect
local ROOT = vim.fn.getcwd()

local lib = require("layout.shared.lib")

--------------------------------------------------------------------------------
-- shared/lib.lua  (pure — main process)
--------------------------------------------------------------------------------
describe("shared.lib", function()
  describe("cwd_hash", function()
    it("returns a stable 12-char hex hash for the same path", function()
      local h1 = lib.cwd_hash("/home/user/project")
      local h2 = lib.cwd_hash("/home/user/project")
      expect.equality(#h1, 12)
      expect.equality(h1, h2)
    end)

    it("produces different hashes for different paths", function()
      local h1 = lib.cwd_hash("/home/user/project-a")
      local h2 = lib.cwd_hash("/home/user/project-b")
      expect.equality(h1 == h2, false)
    end)

    it("produces a lowercase hex string", function()
      local h = lib.cwd_hash("/test")
      expect.equality(string.match(h, "^[0-9a-f]+$") ~= nil, true)
    end)
  end)
end)

--------------------------------------------------------------------------------
-- shared/store.lua  (child process — needs file I/O)
--------------------------------------------------------------------------------
describe("shared.store", function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd("set rtp+=" .. ROOT)
    child.lua([[
      _G.TEST_STORE_DIR = vim.fn.tempname() .. "-layout-store"
      vim.fn.mkdir(_G.TEST_STORE_DIR, "p")
      _G.TEST_CFG = vim.tbl_deep_extend("force",
        require("layout.shared.config").defaults,
        { workspaces = { dir = _G.TEST_STORE_DIR } }
      )
    ]])
  end)

  after_each(function()
    child.lua([[
      if _G.TEST_STORE_DIR then pcall(vim.fn.delete, _G.TEST_STORE_DIR, "rf") end
    ]])
    child.stop()
  end)

  it("save writes a JSON file for the current cwd", function()
    child.lua([[
      local store = require("layout.shared.store")
      store.save(_G.TEST_CFG, {
        sides = { left = { explorer = { "neo-tree" } } },
      })
      _G._saved_fname = _G.TEST_STORE_DIR .. "/" .. require("layout.shared.lib").cwd_hash(vim.fn.getcwd()) .. ".json"
    ]])

    local fname = child.lua_get([[_G._saved_fname]])
    -- Check file exists by embedding the path in a Lua expression
    child.lua(string.format("_G._check_fname = %q", fname))
    local exists = child.lua_get([[vim.fn.filereadable(_G._check_fname) == 1]])
    expect.equality(exists, true)
  end)

  it("load returns the saved state", function()
    child.lua([[
      local store = require("layout.shared.store")
      store.save(_G.TEST_CFG, {
        sides = { left = { explorer = { "neo-tree" } } },
      })
      _G._loaded = store.load(_G.TEST_CFG)
    ]])
    local state = child.lua_get([[_G._loaded]])
    expect.equality(state.sides.left.explorer[1], "neo-tree")
  end)

  it("load returns nil when no file exists", function()
    child.lua([[
      local store = require("layout.shared.store")
      _G._loaded_nil = store.load(_G.TEST_CFG)
    ]])
    local state = child.lua_get([[_G._loaded_nil]])
    expect.equality(state, vim.NIL)
  end)

  it("forget deletes the saved file", function()
    child.lua([[
      local store = require("layout.shared.store")
      store.save(_G.TEST_CFG, { sides = { left = {} } })
      store.forget(_G.TEST_CFG)
      _G._forgotten = store.load(_G.TEST_CFG)
    ]])
    local exists = child.lua_get([[_G._forgotten]])
    expect.equality(exists, vim.NIL)
  end)
end)

--------------------------------------------------------------------------------
-- features/save.lua  (child process — needs windows + file I/O)
--------------------------------------------------------------------------------
describe("features.save", function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd("set rtp+=" .. ROOT)
    child.lua([[
      _G.TEST_STORE_DIR = vim.fn.tempname() .. "-layout-save"
      vim.fn.mkdir(_G.TEST_STORE_DIR, "p")
      _G.TEST_CFG = vim.tbl_deep_extend("force",
        require("layout.shared.config").defaults,
        { workspaces = { dir = _G.TEST_STORE_DIR } }
      )
    ]])
  end)

  after_each(function()
    child.lua([[
      if _G.TEST_STORE_DIR then pcall(vim.fn.delete, _G.TEST_STORE_DIR, "rf") end
    ]])
    child.stop()
  end)

  it("snapshots open tool windows to a saved file", function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = { filter = "toolL", open = "echo" },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    U.make_tool_win(child, "toolL")

    child.lua([[
      require("layout.features.save").save(_G.TEST_CFG)
      local store = require("layout.shared.store")
      _G._snapshot = store.load(_G.TEST_CFG)
    ]])

    local state = child.lua_get([[_G._snapshot]])
    expect.equality(state.sides.left.explorer[1], "toolL")
  end)
end)

--------------------------------------------------------------------------------
-- features/restore.lua  (child process — needs windows + file I/O)
--------------------------------------------------------------------------------
describe("features.restore", function()
  local child

  before_each(function()
    child = MiniTest.new_child_neovim()
    child.start()
    child.cmd("set rtp+=" .. ROOT)
    child.lua([[
      _G.TEST_STORE_DIR = vim.fn.tempname() .. "-layout-restore"
      vim.fn.mkdir(_G.TEST_STORE_DIR, "p")
      _G.TEST_CFG = vim.tbl_deep_extend("force",
        require("layout.shared.config").defaults,
        { workspaces = { dir = _G.TEST_STORE_DIR, auto_restore = true } }
      )
    ]])
  end)

  after_each(function()
    child.lua([[
      if _G.TEST_STORE_DIR then pcall(vim.fn.delete, _G.TEST_STORE_DIR, "rf") end
    ]])
    child.stop()
  end)

  it("restores saved open groups by calling their open commands", function()
    local cfg = U.test_config({
      left = {
        size = 30,
        groups = {
          explorer = {
            views = {
              filesystem = {
                filter = "toolL",
                open = "belowright split",
              },
            },
          },
        },
      },
    })
    U.setup_config(child, cfg)

    child.lua([[
      local store = require("layout.shared.store")
      store.save(_G.TEST_CFG, {
        sides = { left = { explorer = { "toolL" } } },
      })
    ]])

    local before = #child.api.nvim_tabpage_list_wins(0)

    child.lua([[
      require("layout.features.restore").restore(_G.TEST_CFG)
    ]])
    vim.wait(500, function() return true end)

    local after = #child.api.nvim_tabpage_list_wins(0)
    expect.equality(after, before + 1)
  end)
end)
