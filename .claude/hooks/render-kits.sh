#!/bin/bash
# Lays every team's home and away kit out flat and writes one PNG per team — for
# editing data/team_colors.json without a skater wearing the kit. Wraps
# tools/kit_capture.gd; see that file for what is drawn and from where.
#
#   .claude/hooks/render-kits.sh                # every team, into ./.preview/kits
#   .claude/hooks/render-kits.sh papaya,lime    # named teams (or slot numbers)
#   KIT_PREVIEW_NAME=Smith KIT_PREVIEW_NUMBER=7 .claude/hooks/render-kits.sh
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
  echo "[render-kits] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-kits] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

# A stale global class cache leaves every class_name the tool touches "not
# declared" — the same guard as run-gut.sh.
CACHE="$POSIX_DIR/.godot/global_script_class_cache.cfg"
if [ ! -f "$CACHE" ] \
    || [ -n "$(find "$POSIX_DIR/Scripts" -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null)" ]; then
  echo "[render-kits] class cache stale — reimporting..." >&2
  "$GODOT" --headless --path "$PROJECT_DIR" --import --quit >/dev/null 2>&1 || true
fi

export KIT_PREVIEW_OUT="${KIT_PREVIEW_OUT:-$POSIX_DIR/.preview/kits}"
if [ $# -gt 0 ]; then
  export KIT_PREVIEW_TEAMS="$1"
  shift
fi

# A real window is fine where there's a display (a dev machine); xvfb-run
# supplies one where there isn't (CI, web sessions).
RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a)
  export LIBGL_ALWAYS_SOFTWARE=1
fi

exec "${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy --resolution 640x360 -s res://tools/kit_capture.gd "$@"
