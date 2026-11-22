#!/bin/bash
# Staged own-goal trials: in an all-bot match, a loose puck behind and beside a
# net with that team's defenseman coming to it, every combination of puck spot,
# approach and forecheck, both teams' nets in turn. Wraps tools/own_goal_stage.gd;
# prints each trial's outcome and a summary per team size, and the trace of any
# own goal. Headless, software-only; runs the sim as fast as the CPU allows.
#
#   .claude/hooks/stage-own-goals.sh            # 3v3 and 5v5, both sides of the net
#   .claude/hooks/stage-own-goals.sh 5          # one team size
#   STAGE_OUT=/tmp/stage .claude/hooks/stage-own-goals.sh   # where the logs go
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
POSIX_DIR="$PROJECT_DIR"
if command -v cygpath >/dev/null 2>&1; then
  PROJECT_DIR="$(cygpath -w "$PROJECT_DIR")"
fi
GODOT="${GODOT_BIN:-$(command -v godot || true)}"
if [ -z "$GODOT" ]; then
  echo "[stage-own-goals] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  exit 1
fi
OUT="${STAGE_OUT:-$POSIX_DIR/.preview/own_goal_stage}"
mkdir -p "$OUT"
SIZES="${1:-3,5}"

pids=()
IFS=',' read -ra LIST <<< "$SIZES"
for n in "${LIST[@]}"; do
  for side in left right; do
    (
      USER_DATA="$(mktemp -d)"
      trap 'rm -rf "$USER_DATA"' EXIT
      XDG_DATA_HOME="$USER_DATA" APPDATA="$USER_DATA" "$GODOT" --headless --path "$PROJECT_DIR" \
        --audio-driver Dummy --fixed-fps 90 -s res://tools/own_goal_stage.gd -- \
        --team-size="$n" --side="$side" > "$OUT/stage_${n}v${n}_$side.log" 2>&1 || true
    ) &
    pids+=($!)
  done
done
wait "${pids[@]}"
for f in "$OUT"/stage_*.log; do
  echo "== $(basename "$f")"
  grep -h "SUMMARY\|OWN GOAL" "$f" || echo "(no summary: see $f)"
done
