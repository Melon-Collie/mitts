#!/bin/bash
# Renders the new keeper (Scripts/actors/keeper/) in every taught stance from
# the front, side, three-quarter, the shooter's spot and behind, with the mouth
# as a shot straight on sees him, his save boxes overlaid, and writes one
# contact sheet per stance plus one of every stance from the front to
# .preview/keeper/. Wraps tools/keeper_capture.gd; KEEPER_CAPTURE_BOXES=0 hides
# the boxes.
#
#   .claude/hooks/render-keeper.sh --baseline   # record the baseline first
#   .claude/hooks/render-keeper.sh              # render + diff against it
#
# Same constraint as render-poses.sh: Godot's --headless draws nothing, so this
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
  echo "[render-keeper] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-keeper] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy -s res://tools/keeper_capture.gd -- "$@"
