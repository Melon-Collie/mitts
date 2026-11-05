#!/bin/bash
# Renders one instant of a match against bots from the live GameCamera
# and a grid of pitch / FOV / scale setups around the puck carrier, one PNG
# each plus metrics.json (tools/camera_study_runner.gd has the setups).
#
#   .claude/hooks/render-camera.sh                  # every setup, into ./.preview/camera
#   .claude/hooks/render-camera.sh p45_f65,chase    # named setups only
#   .claude/hooks/render-camera.sh --list
#
# Same renderer constraint as render-ui.sh: xvfb-run, Compatibility backend,
# software rasterizer; a throwaway user data directory.
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
  echo "[render-camera] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  exit 1
fi

ARGS=(--out="${CAMERA_STUDY_OUT:-$POSIX_DIR/.preview/camera}")
if [ $# -gt 0 ]; then
  if [ "$1" = "--list" ]; then
    ARGS+=(--list)
  else
    ARGS+=(--only="$1")
  fi
  shift
fi

USER_DATA="$(mktemp -d)"
trap 'rm -rf "$USER_DATA"' EXIT
export XDG_DATA_HOME="$USER_DATA"
export APPDATA="$USER_DATA"

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a -s "-screen 0 1920x1080x24")
  export LIBGL_ALWAYS_SOFTWARE=1
fi

"${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy --resolution 1920x1080 \
  -s res://tools/camera_study.gd -- "${ARGS[@]}" "$@"
