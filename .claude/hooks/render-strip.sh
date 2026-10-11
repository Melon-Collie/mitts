#!/bin/bash
# Renders the skating gait as frame strips — a stroke over a cycle, from behind,
# beside and ahead, with the locomotion mix printed per frame. Wraps
# tools/gait_strip.gd; see tools/gait_strip_runner.gd for the scenarios.
#
#   .claude/hooks/render-strip.sh                  # every scenario
#   .claude/hooks/render-strip.sh turn45,keyD      # named scenarios only
#
# Same xvfb / software-GL constraint as render-poses.sh: Godot's --headless
# draws nothing. Expect ~20 s a scenario.
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
  echo "[render-strip] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-strip] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

ARGS=()
if [ $# -gt 0 ]; then
  ARGS=(--only="$1")
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy -s res://tools/gait_strip.gd -- "${ARGS[@]}"
