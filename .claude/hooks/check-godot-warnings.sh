#!/bin/bash
# Fails on any GDScript analyzer warning in the project — the SHADOWED_*,
# STATIC_CALLED_ON_INSTANCE, INT_AS_ENUM, NARROWING_CONVERSION family the editor's
# debugger lists and gdlint cannot see. Wraps tools/gdscript_warning_scan.gd.
#
#   .claude/hooks/check-godot-warnings.sh
#
# Outside the editor Godot sends analyzer warnings only to an attached debugger,
# so a headless run never prints them. Raised to ERROR they print as parse
# errors, so this writes an override.cfg (read at startup, layered over
# project.godot) raising every WARN-level warning, compiles every script, and
# removes the file again. Silence a deliberate one at its site with
# @warning_ignore("<name>"), never by lowering the project's level.
#
# Exit 0 clean, 1 on any warning or parse error, 2 when it could not run.
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
  echo "[godot-warnings] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  echo "[godot-warnings] (web sessions: run .claude/hooks/wait-for-godot.sh first)" >&2
  exit 2
fi

# A run killed before its trap fired leaves its override behind, which would turn
# every warning into a load failure in the editor too; the marker line tells that
# leftover apart from an override.cfg someone keeps on purpose.
OVERRIDE="$POSIX_DIR/override.cfg"
MARKER="; written by .claude/hooks/check-godot-warnings.sh"
if [ -e "$OVERRIDE" ]; then
  if [ "$(head -n 1 "$OVERRIDE" | tr -d '\r')" != "$MARKER" ]; then
    echo "[godot-warnings] $OVERRIDE already exists; refusing to overwrite it." >&2
    exit 2
  fi
  rm -f "$OVERRIDE"
fi

# A stale global class cache fails every class_name the scan touches as "not
# declared" — the same guard as run-gut.sh.
CACHE="$POSIX_DIR/.godot/global_script_class_cache.cfg"
if [ ! -f "$CACHE" ] \
    || [ -n "$(find "$POSIX_DIR/Scripts" "$POSIX_DIR/tests" "$POSIX_DIR/tools" -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null)" ]; then
  echo "[godot-warnings] class cache stale — reimporting..." >&2
  "$GODOT" --headless --path "$PROJECT_DIR" --import --quit >/dev/null 2>&1 || true
fi

# Redirected to files rather than piped: the Windows console exe throttles
# badly on an MSYS pipe.
LOG="$(mktemp)"
trap 'rm -f "$OVERRIDE" "$LOG"' EXIT

"$GODOT" --headless --path "$PROJECT_DIR" -s res://tools/gdscript_warning_scan.gd \
  -- --levels > "$LOG" 2>&1 || true
LEVELS="$(tr -d '\r' < "$LOG" | grep -E '^gdscript/warnings/[a-z_]+=2$' || true)"
if [ -z "$LEVELS" ]; then
  echo "[godot-warnings] could not read the warning levels:" >&2
  cat "$LOG" >&2
  exit 2
fi
printf '%s\n[debug]\n\n%s\n' "$MARKER" "$LEVELS" > "$OVERRIDE"

"$GODOT" --headless --path "$PROJECT_DIR" -s res://tools/gdscript_warning_scan.gd \
  > "$LOG" 2>&1 || true
if ! grep -q '^\[gdscript-warning-scan\] compiled' "$LOG"; then
  echo "[godot-warnings] the scan did not finish:" >&2
  cat "$LOG" >&2
  exit 2
fi

# Each finding is a "SCRIPT ERROR: Parse Error: <message>" line followed by
# "at: GDScript::reload (res://<path>:<line>)". A script compiled twice (a
# dependency, then directly) reports twice, hence the sort -u.
FINDINGS="$(tr -d '\r' < "$LOG" | awk '
  /^SCRIPT ERROR: Parse Error: / { msg = substr($0, length("SCRIPT ERROR: Parse Error: ") + 1); next }
  msg != "" && /at: GDScript::reload \(res:\/\// {
    loc = $0
    sub(/.*at: GDScript::reload \(res:\/\//, "", loc)
    sub(/\)[^)]*$/, "", loc)
    sub(/ \(Warning treated as error\.\)$/, "", msg)
    print loc ": " msg
  }
  { msg = "" }
' | sort -t: -k1,1 -k2,2n -u)"

if [ -n "$FINDINGS" ]; then
  echo "$FINDINGS"
  echo "" >&2
  echo "[godot-warnings] $(echo "$FINDINGS" | wc -l | tr -d ' ') GDScript warning(s) above." >&2
  echo "[godot-warnings] Fix them, or silence a deliberate one with @warning_ignore(\"<name>\")." >&2
  exit 1
fi
tr -d '\r' < "$LOG" | grep '^\[gdscript-warning-scan\]'
echo "[godot-warnings] clean."
