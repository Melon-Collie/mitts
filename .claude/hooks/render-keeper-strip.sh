#!/bin/bash
# Renders the new keeper's moves (KeeperFootwork) as frame strips: a frame
# every few ticks from the shooter's side, behind and high in front, one sheet per
# scenario to .preview/keeper/strip_<name>.png, with each frame's phase, place
# and speed printed. Wraps tools/keeper_strip.gd.
#
#   .claude/hooks/render-keeper-strip.sh               # every scenario
#   .claude/hooks/render-keeper-strip.sh t_push        # named scenarios only
#
# Same constraint as render-keeper.sh: Godot's --headless draws nothing, so this
# runs under xvfb-run on the Compatibility renderer and software GL.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
if command -v cygpath >/dev/null 2>&1; then
  PROJECT_DIR="$(cygpath -w "$PROJECT_DIR")"
fi

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
  GODOT="$(command -v godot || true)"
fi
if [ -z "$GODOT" ]; then
  echo "[render-keeper-strip] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-keeper-strip] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

if [ $# -gt 0 ]; then
  export KEEPER_STRIP_SCENARIOS="$1"
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy -s res://tools/keeper_strip.gd
