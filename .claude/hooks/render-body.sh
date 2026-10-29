#!/bin/bash
# Renders the connected-body prototype (SkaterConnectedMesh) beside the rig's
# current body, pose by pose, from four sides, to .preview/body/. Wraps
# tools/body_preview.gd; see that file for the flags.
#
#   .claude/hooks/render-body.sh                 # the whole set
#   .claude/hooks/render-body.sh --only=stride   # poses whose name contains it
#
# Same xvfb / software-GL arrangement as render-poses.sh, and as slow.
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
  echo "[render-body] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[render-body] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
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
  --audio-driver Dummy -s res://tools/body_preview.gd -- "$@"
