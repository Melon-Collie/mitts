#!/bin/bash
# Renders what the arm anatomy model makes of each reference carry
# (tests/harness/arm_reference_carries.gd): the jersey, both arms coloured by
# whether they are in their ranges, the hands and the stick, four views a carry,
# with what binds printed. Wraps tools/arm_reference_capture.gd.
#
#   .claude/hooks/render-references.sh                  # every carry, into ./.preview/arm_reference
#   .claude/hooks/render-references.sh forehand,tight   # named carries only
#   .claude/hooks/render-references.sh --list           # the carry names
#
# Same xvfb / software-GL constraint as render-strip.sh: Godot's --headless
# draws nothing. Seconds for the set.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
POSIX_DIR="$PROJECT_DIR"
if command -v cygpath >/dev/null 2>&1; then
  PROJECT_DIR="$(cygpath -w "$PROJECT_DIR")"
fi

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
  GODOT="$(command -v godot || true)"
fi
if [ -z "$GODOT" ]; then
  echo "[render-references] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-references] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

# A stale global class cache leaves every class_name the tool touches "not
# declared" — the same guard as run-gut.sh.
CACHE="$POSIX_DIR/.godot/global_script_class_cache.cfg"
if [ ! -f "$CACHE" ] \
    || [ -n "$(find "$POSIX_DIR/Scripts" "$POSIX_DIR/tools" -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null)" ]; then
  echo "[render-references] class cache stale — reimporting..." >&2
  "$GODOT" --headless --path "$PROJECT_DIR" --import --quit >/dev/null 2>&1 || true
fi

export ARM_REFERENCE_OUT="${ARM_REFERENCE_OUT:-$POSIX_DIR/.preview/arm_reference}"

ARGS=()
if [ $# -gt 0 ]; then
  if [ "$1" = "--list" ]; then
    ARGS=(--list)
  else
    ARGS=(--only="$1")
  fi
fi

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy -s res://tools/arm_reference_capture.gd -- "${ARGS[@]}"
