#!/bin/bash
# What the main thread spends on a live match against bots, by skater count,
# headless (nothing drawn: the frame is the CPU's alone). Wraps
# tools/frame_cost.gd and writes a markdown table.
#
#   .claude/hooks/measure-frame-cost.sh                 # 2,4,6,8,10 skaters
#   .claude/hooks/measure-frame-cost.sh 4,10            # chosen counts
#   FRAME_COST_RUNS=3 FRAME_COST_FRAMES=2000 .claude/hooks/measure-frame-cost.sh
#   FRAME_COST_OUT=/tmp/cost.md .claude/hooks/measure-frame-cost.sh
#   FRAME_COST_RENDER=1 .claude/hooks/measure-frame-cost.sh  # drawn: + CPU render, draws
#
# FRAME_COST_RENDER=1 draws the match (Forward+, as shipped) and adds the
# engine's CPU render time and the draw calls per frame. Without a display it
# runs under xvfb on software Vulkan, about a frame a second, so it samples
# fewer frames; the CPU render time is real CPU work there too.
#
# Each count is its own Godot process, a fresh match; runs alternate the counts
# so a machine slowing down mid-sweep spreads over all of them. Every run gets a
# throwaway user data directory, so it measures the shipped defaults.
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
  echo "[measure-frame-cost] Godot not found. Set GODOT_BIN, or add 'godot' to PATH." >&2
  exit 1
fi

COUNTS="${1:-2,4,6,8,10}"
RUNS="${FRAME_COST_RUNS:-2}"
FRAMES="${FRAME_COST_FRAMES:-1200}"
OUT="${FRAME_COST_OUT:-$POSIX_DIR/.preview/frame_cost.md}"
mkdir -p "$(dirname "$OUT")"

USER_DATA="$(mktemp -d)"
trap 'rm -rf "$USER_DATA"' EXIT
export XDG_DATA_HOME="$USER_DATA"
export APPDATA="$USER_DATA"

LAUNCH=("$GODOT" --headless)
if [ "${FRAME_COST_RENDER:-0}" = "1" ]; then
  LAUNCH=("$GODOT" --rendering-driver vulkan --rendering-method forward_plus --resolution 1280x720)
  if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
    LAUNCH=(xvfb-run -a -s "-screen 0 1280x720x24" "${LAUNCH[@]}")
    export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
    FRAMES="${FRAME_COST_FRAMES:-40}"
  fi
fi

ROWS=()
IFS=',' read -ra LIST <<< "$COUNTS"
for ((r = 1; r <= RUNS; r++)); do
  for n in "${LIST[@]}"; do
    line="$("${LAUNCH[@]}" --path "$PROJECT_DIR" --audio-driver Dummy \
      -s res://tools/frame_cost.gd -- --skaters="$n" --frames="$FRAMES" 2>&1 \
      | grep '^\[frame-cost\] {' || true)"
    if [ -z "$line" ]; then
      echo "[measure-frame-cost] run $r, $n skaters: no result" >&2
      continue
    fi
    echo "[measure-frame-cost] run $r: ${line#\[frame-cost\] }"
    ROWS+=("${line#\[frame-cost\] }")
  done
done

python3 - "$OUT" "${ROWS[@]}" <<'EOF'
import json, sys
out, rows = sys.argv[1], [json.loads(r) for r in sys.argv[2:]]
by = {}
for r in rows:
    by.setdefault(r["skaters"], []).append(r)
lines = [
    "Headless, %s; per count, the mean of %d run(s)." % (rows[0]["native"] if rows else "?", max((len(v) for v in by.values()), default=0)),
    "process = every _process, once a frame; tick = one physics step, paid 120/fps times a frame.",
    "",
    "| skaters | process ms/frame (p95) | tick ms | main thread at 90 fps, ms | per added skater, ms | CPU render ms | draw calls |",
    "|---|---|---|---|---|---|---|",
]
prev = None
for n in sorted(by):
    v = by[n]
    m = lambda k: sum(x[k] for x in v) / len(v)
    at90 = m("at_90fps_ms")
    slope = "" if prev is None else "%.2f" % ((at90 - prev[1]) / (n - prev[0]))
    rend = m("cpu_render_ms") if all("cpu_render_ms" in x for x in v) else -1.0
    rcell = ("%.2f" % rend, "%.0f" % m("draw_calls")) if rend >= 0.0 else ("", "")
    lines.append("| %d | %.2f (%.2f) | %.2f | %.2f | %s | %s | %s |" % (n, m("process_ms"), m("process_p95_ms"), m("tick_ms"), at90, slope, rcell[0], rcell[1]))
    prev = (n, at90)
names = []
for r in rows:
    for k in r.get("probe_us", {}):
        if k not in names:
            names.append(k)
if names:
    counts = sorted(by)
    lines += ["", "Host tick by section (HostCostProbe, mean us per tick):", "",
              "| section | " + " | ".join("%d" % n for n in counts) + " |",
              "|---|" + "---|" * len(counts)]
    for k in names:
        cells = []
        for n in counts:
            vals = [x["probe_us"].get(k, 0.0) for x in by[n] if x.get("probe_us")]
            cells.append("%.0f" % (sum(vals) / len(vals)) if vals else "")
        lines.append("| %s | %s |" % (k, " | ".join(cells)))
open(out, "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
EOF
echo "[measure-frame-cost] wrote $OUT"
