#!/bin/bash
# Renders every pickable hair style against every facial-hair style, one head
# each, from three-quarter front, side, three-quarter back, below and above,
# into .preview/hair/. Wraps tools/hair_capture.gd; see that file for the knobs.
#
#   .claude/hooks/render-hair.sh                        # every shot, helmeted
#   .claude/hooks/render-hair.sh below_front,side       # named shots
#   HAIR_PREVIEW_BARE=1 .claude/hooks/render-hair.sh    # the helmet shell left off
#   HAIR_PREVIEW_FACIALS=0 .claude/hooks/render-hair.sh # one facial column
#   HAIR_PREVIEW_HAIRS=6 .claude/hooks/render-hair.sh    # one hair row
#
# Godot's own --headless is a DUMMY renderer: it draws nothing and captures
# come back blank. Without a GPU this runs under xvfb-run on the Compatibility
# renderer and Mesa's software rasterizer, same as render-arena.sh.
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
  echo "[render-hair] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-hair] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

# A stale global class cache leaves every class_name the tool touches "not
# declared" — the same guard as run-gut.sh.
CACHE="$POSIX_DIR/.godot/global_script_class_cache.cfg"
if [ ! -f "$CACHE" ] \
    || [ -n "$(find "$POSIX_DIR/Scripts" -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null)" ]; then
  echo "[render-hair] class cache stale — reimporting..." >&2
  "$GODOT" --headless --path "$PROJECT_DIR" --import --quit >/dev/null 2>&1 || true
fi

export HAIR_PREVIEW_OUT="${HAIR_PREVIEW_OUT:-$POSIX_DIR/.preview/hair}"
if [ $# -gt 0 ]; then
  export HAIR_PREVIEW_SHOTS="$1"
  shift
fi

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy -s res://tools/hair_capture.gd "$@"
