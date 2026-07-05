#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MINI_PATH="${MINI_NVIM_PATH:-}"

if [ -z "$MINI_PATH" ]; then
  for candidate in \
    "$HOME/.local/share/kickstart/lazy/mini.nvim" \
    "$HOME/.local/share/nvim/lazy/mini.nvim" \
    "$HOME/.local/share/nvim/site/pack/packer/start/mini.nvim" \
    "$HOME/.local/share/nvim/plugged/mini.nvim"; do
    if [ -d "$candidate" ]; then
      MINI_PATH="$candidate"
      break
    fi
  done
fi

if [ -z "$MINI_PATH" ]; then
  echo "Error: Could not find mini.nvim." >&2
  echo "Set MINI_NVIM_PATH to the mini.nvim directory, e.g.:" >&2
  echo "  export MINI_NVIM_PATH=~/.local/share/nvim/lazy/mini.nvim" >&2
  exit 1
fi

exec nvim --headless -u NONE \
  -c "set rtp+=${MINI_PATH},${REPO_ROOT}" \
  -c "luafile ${REPO_ROOT}/scripts/minitest.lua" \
  -c 'lua MiniTest.run({ collect = { emulate_busted = true, find_files = function() return vim.fn.globpath("tests", "**/test_*.lua", true, true) end } })' \
  -c 'lua local s = MiniTest._session; local ok = s == nil or (s.n_failures + s.n_errors) == 0; vim.cmd(ok and "qa!" or "cquit")'
