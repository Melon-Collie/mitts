#!/bin/bash
# Sweeps the cursor round a carrier and renders the arms at each step, printing
# per frame how close each arm comes to the torso and how the shaft sits in each
# glove, and for the moving scenarios the blade against the cursor tick by tick.
# Wraps tools/arm_sweep.gd; see tools/arm_sweep_runner.gd for the scenarios.
#
#   .claude/hooks/render-arms.sh                           # every scenario
#   .claude/hooks/render-arms.sh carry_sweep,tight_sweep   # named scenarios only
#   .claude/hooks/render-arms.sh --list
#
# Same xvfb / software-GL constraint as render-poses.sh: Godot's --headless
# draws nothing. A few seconds a scenario.
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
  echo "[render-arms] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-arms] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

ARGS=()
if [ "${1:-}" = "--list" ]; then
  ARGS=(--list)
elif [ $# -gt 0 ]; then
  ARGS=(--only="$1")
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy -s res://tools/arm_sweep.gd -- "${ARGS[@]}"
