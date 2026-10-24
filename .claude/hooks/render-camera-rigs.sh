#!/bin/bash
# Candidate gameplay-camera rigs, measured and rendered (tools/camera_rig_preview.gd;
# the rig list is tools/camera_rigs.gd). Writes projection.md — how each rig maps
# the aim cursor onto the ice — and one PNG per rig per frozen match moment.
#
#   .claude/hooks/render-camera-rigs.sh                   # table + every still
#   .claude/hooks/render-camera-rigs.sh now_h10,sh45      # named rigs only
#   .claude/hooks/render-camera-rigs.sh --measure         # the table alone, headless, seconds
#   CAMERA_RIGS_OUT=/tmp/rigs .claude/hooks/render-camera-rigs.sh
#
# The stills have render-ui.sh's constraints (xvfb, software Compatibility
# renderer, about a frame a second in a match, a throwaway user data directory).
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
  echo "[render-camera-rigs] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-camera-rigs] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

ARGS=(--out="${CAMERA_RIGS_OUT:-$POSIX_DIR/.preview/camera_rigs}")
MEASURE=0
for a in "$@"; do
  if [ "$a" = "--measure" ]; then
    MEASURE=1
    ARGS+=(--measure)
  else
    ARGS+=(--only="$a")
  fi
done

USER_DATA="$(mktemp -d)"
trap 'rm -rf "$USER_DATA"' EXIT
export XDG_DATA_HOME="$USER_DATA"
export APPDATA="$USER_DATA"

if [ "$MEASURE" = 1 ]; then
  "$GODOT" --headless --path "$PROJECT_DIR" --audio-driver Dummy \
    -s res://tools/camera_rig_preview.gd -- "${ARGS[@]}"
  exit $?
fi

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a -s "-screen 0 1920x1080x24")
  export LIBGL_ALWAYS_SOFTWARE=1
fi

"${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --audio-driver Dummy --resolution 1920x1080 \
  -s res://tools/camera_rig_preview.gd -- "${ARGS[@]}"
