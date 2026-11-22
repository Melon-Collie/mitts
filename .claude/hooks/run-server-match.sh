#!/bin/bash
# Launches the game as a dedicated server, the way a container would, and
# reports how it ended: the exit code, the result line and every engine error.
# The probe (probe-headless-host.sh --server) drives a match from a tool script
# and measures it; this is the launch itself, through Boot
# (Scripts/game/dedicated_server.gd, docs/dedicated-server-plan.md).
#
#   .claude/hooks/run-server-match.sh                  # a 3v3 of bots, one 20 s period
#   .claude/hooks/run-server-match.sh match.json       # that config
#   MITTS_MATCH_CONFIG='{...}' .claude/hooks/run-server-match.sh --env   # config from the environment
#
# The match runs in real time. Each run gets a throwaway user data directory.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
if command -v cygpath >/dev/null 2>&1; then
  PROJECT_DIR="$(cygpath -w "$PROJECT_DIR")"
fi

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
  GODOT="$(command -v godot || true)"
fi
if [ -z "$GODOT" ]; then
  echo "[run-server-match] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  exit 1
fi

USER_DATA="$(mktemp -d)"
LOG="$(mktemp)"
DEFAULT_CONFIG="$(mktemp --suffix=.json)"
trap 'rm -rf "$USER_DATA" "$LOG" "$DEFAULT_CONFIG"' EXIT
export XDG_DATA_HOME="$USER_DATA"
export APPDATA="$USER_DATA"

ARGS=(--server)
case "${1:-}" in
  --env) ;;
  "")
    echo '{"team_size": 3, "num_periods": 1, "period_duration": 20, "ot_enabled": false, "fill_bots": true}' > "$DEFAULT_CONFIG"
    ARGS+=("--match-config=$DEFAULT_CONFIG")
    ;;
  *) ARGS+=("--match-config=$1") ;;
esac

"$GODOT" --headless --path "$PROJECT_DIR" --audio-driver Dummy -- "${ARGS[@]}" > "$LOG" 2>&1
CODE=$?

echo "[run-server-match] exit code $CODE"
grep '^\[server\]' "$LOG" || echo "[run-server-match] the server printed nothing"
echo "[run-server-match] engine errors and warnings (count, message):"
grep -E '^(SCRIPT )?ERROR|^WARNING' "$LOG" | sort | uniq -c | sort -rn || true
if grep -q '^SCRIPT ERROR' "$LOG"; then
  echo "[run-server-match] where each script error was raised (first of each):"
  grep -A3 '^SCRIPT ERROR' "$LOG" | awk '!seen[$0]++' | head -40
fi
exit "$CODE"
