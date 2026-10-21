#!/bin/bash
# Measures what each Video setting costs in a live 5v5 against bots, on the
# Forward+ renderer the game ships with, and writes a markdown table. Wraps
# tools/graphics_cost.gd; the condition list is in tools/graphics_cost_runner.gd.
#
#   .claude/hooks/measure-graphics.sh                    # every setting
#   .claude/hooks/measure-graphics.sh shadows,crowd      # labels or prefixes
#   .claude/hooks/measure-graphics.sh --list
#   GRAPHICS_COST_OUT=/tmp/cost.md .claude/hooks/measure-graphics.sh
#
# On a machine with a graphics card the GPU times are real; run it there for the
# numbers players would see. In a web session there is no GPU: it runs on Mesa's
# software Vulkan (lavapipe) under xvfb, where draw calls and triangles are exact
# but times only rank the passes, and a frame takes about a second, so the
# rotations are cut down (GRAPHICS_COST_ROTATIONS / _SETTLE / _SAMPLES override).
#
# Every run gets a throwaway user data directory, so it measures the shipped
# defaults and never touches your prefs.
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
  echo "[measure-graphics] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[measure-graphics] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 1
fi

ARGS=(--out="${GRAPHICS_COST_OUT:-$POSIX_DIR/.preview/graphics_cost.md}")
if [ $# -gt 0 ]; then
  if [ "$1" = "--list" ]; then
    ARGS+=(--list)
  else
    ARGS+=(--only="$1")
  fi
  shift
fi
mkdir -p "$POSIX_DIR/.preview"

USER_DATA="$(mktemp -d)"
trap 'rm -rf "$USER_DATA"' EXIT
export XDG_DATA_HOME="$USER_DATA"
export APPDATA="$USER_DATA"

RUNNER=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a -s "-screen 0 1280x720x24")
  LVP=/usr/share/vulkan/icd.d/lvp_icd.json
  if [ -f "$LVP" ]; then
    export VK_ICD_FILENAMES="$LVP"
  else
    echo "[measure-graphics] no display and no lavapipe ($LVP):" >&2
    echo "[measure-graphics]   apt-get install mesa-vulkan-drivers" >&2
    exit 1
  fi
  export GRAPHICS_COST_ROTATIONS="${GRAPHICS_COST_ROTATIONS:-2}"
  export GRAPHICS_COST_SETTLE="${GRAPHICS_COST_SETTLE:-4}"
  export GRAPHICS_COST_SAMPLES="${GRAPHICS_COST_SAMPLES:-6}"
fi

"${RUNNER[@]}" "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver vulkan --rendering-method forward_plus \
  --audio-driver Dummy --resolution 1280x720 \
  -s res://tools/graphics_cost.gd -- "${ARGS[@]}" "$@"
