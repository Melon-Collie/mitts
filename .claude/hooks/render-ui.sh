#!/bin/bash
# Renders the menus and HUD offscreen and writes one PNG per shot — the "how
# does this screen read" check a headless GUT run cannot make. Wraps
# tools/ui_preview.gd; the shot list is in tools/ui_preview_runner.gd.
#
#   .claude/hooks/render-ui.sh                  # every shot, into ./.preview/ui
#   .claude/hooks/render-ui.sh options,side     # shot names or group prefixes
#   .claude/hooks/render-ui.sh --list           # print the shot list
#   UI_PREVIEW_OUT=/tmp/ui .claude/hooks/render-ui.sh
#
# Every run starts from a throwaway user data directory, so the screens show
# first-run defaults (prefs, callouts, the tutorial gate) and a run never
# writes your own settings.
#
# Same renderer constraint as render-arena.sh: --headless draws nothing, so
# this runs under xvfb-run on the Compatibility backend and Mesa's software
# rasterizer. That draws UI faithfully but the 3D world only roughly (no
# SDFGI/SSR, so the ice reads blown out), and a match runs at about one frame
# a second — expect several minutes for the full set, most of it in-match.
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
  echo "[render-ui] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-ui] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

ARGS=(--out="${UI_PREVIEW_OUT:-$POSIX_DIR/.preview/ui}")
if [ $# -gt 0 ]; then
  if [ "$1" = "--list" ]; then
    ARGS+=(--list)
  else
    ARGS+=(--only="$1")
  fi
  shift
fi

# user:// resolves under XDG_DATA_HOME on Linux and APPDATA on Windows.
USER_DATA="$(mktemp -d)"
trap 'rm -rf "$USER_DATA"' EXIT
export XDG_DATA_HOME="$USER_DATA"
export APPDATA="$USER_DATA"

# A real window is fine where there's a display (a dev machine); xvfb-run
# supplies one where there isn't (CI, web sessions). The UI is laid out for
# 1920x1080, so the virtual screen is that size.
RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a -s "-screen 0 1920x1080x24")
  export LIBGL_ALWAYS_SOFTWARE=1
fi

"${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy --resolution 1920x1080 \
  -s res://tools/ui_preview.gd -- "${ARGS[@]}" "$@"
