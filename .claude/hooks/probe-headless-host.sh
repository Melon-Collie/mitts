#!/bin/bash
# Plays a whole bot match on a host with no skater of its own, headless, and
# prints whether it reached GAME_OVER, each phase with the tick rate held in it,
# the CPU the process used, and every engine error it logged. Wraps
# tools/headless_host_probe.gd (docs/dedicated-server-plan.md).
#
#   .claude/hooks/probe-headless-host.sh                          # 5v5, 3 x 40 s
#   .claude/hooks/probe-headless-host.sh --team-size=3 --period=20
#   .claude/hooks/probe-headless-host.sh --max-fps=30             # a server's frame rate
#
# The match runs in real time, so a run takes about as long as the match does.
# Each run gets a throwaway user data directory.
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
  echo "[probe-headless-host] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  exit 1
fi

USER_DATA="$(mktemp -d)"
LOG="$(mktemp)"
trap 'rm -rf "$USER_DATA" "$LOG"' EXIT
export XDG_DATA_HOME="$USER_DATA"
export APPDATA="$USER_DATA"

START="$(date +%s.%N)"
"$GODOT" --headless --path "$PROJECT_DIR" --audio-driver Dummy \
  -s res://tools/headless_host_probe.gd -- "$@" > "$LOG" 2>&1 &
PID=$!
CPU_TICKS=0
while kill -0 "$PID" 2>/dev/null; do
  if [ -r "/proc/$PID/stat" ]; then
    CPU_TICKS="$(awk '{print $14 + $15}' "/proc/$PID/stat" 2>/dev/null || echo "$CPU_TICKS")"
  fi
  sleep 1
done
wait "$PID" || true
END="$(date +%s.%N)"

grep '^\[headless-host\] {' "$LOG" || echo "[probe-headless-host] no result line"
if [ "$CPU_TICKS" != "0" ]; then
  awk -v t="$CPU_TICKS" -v hz="$(getconf CLK_TCK)" -v s="$START" -v e="$END" \
    'BEGIN { printf "[probe-headless-host] cpu %.1f s over %.1f s wall = %.2f cores\n", t / hz, e - s, (t / hz) / (e - s) }'
fi
echo "[probe-headless-host] engine errors and warnings (count, message):"
grep -E '^(SCRIPT )?ERROR|^WARNING' "$LOG" | sort | uniq -c | sort -rn || true
