-- scripts/minitest.lua
-- Project runner for mini.test. Source this from a Neovim that has
-- `mini.nvim` and the project root on 'runtimepath', then call
-- `MiniTest.run()` (all tests) or `MiniTest.run_file(path)`.
--
-- Example (headless, one file):
--   nvim --headless -u NONE \
--     -c "set rtp+=<path/to/mini.nvim>,<repo-root>" \
--     -c "luafile scripts/minitest.lua" \
--     -c 'lua MiniTest.run_file("tests/test_panel_alignment.lua")' \
--     -c "qa!"

local is_headless = #vim.api.nvim_list_uis() == 0

require('mini.test').setup({
  execute = is_headless and {
    reporter = require('mini.test').gen_reporter.stdout({ quit_on_finish = false }),
  } or nil,
  collect = {
    emulate_busted = true,
    find_files = function()
      return vim.fn.globpath('tests', '**/test_*.lua', true, true)
    end,
  },
})

