#!/bin/bash
# Skates every jersey-hem sim (HemSimMode: sway, flaps, springs, soft_body)
# through one scripted run side by side, renders a sheet of them from the side,
# behind and ahead at a set of moments, and prints how far each one's tail went
# inside the thighs and pants. Wraps tools/hem_compare.gd; see the runner for the
# scenario.
#
#   .claude/hooks/render-hem.sh
#
# Unlike render-poses.sh this runs the engine's own loop, at a fixed 60 fps, so
# the soft body's physics steps as it would in a match. Same xvfb/software-GL
# constraint; a few minutes a run.
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
  echo "[render-hem] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-hem] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

# A real window is fine where there's a display (a dev machine); xvfb-run
# supplies one where there isn't (CI, web sessions), and software GL with it.
RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy --fixed-fps 60 -s res://tools/hem_compare.gd -- "$@"
