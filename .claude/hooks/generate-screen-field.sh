#!/bin/bash
# Regenerates Scripts/domain/ai/generated/screen_field_data.gd — what a body in
# front of the live goalie does to a shot, the screen the bots' net-front reads
# price (docs/bot-net-front-offense-plan.md, step 2b). Run it whenever the goalie
# changes; test_screen_field_is_current.gd fails until you do. Shards the cells
# over SHARDS Godot processes (default: the core count), then merges.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARDS="${SHARDS:-$(nproc 2>/dev/null || echo 4)}"
GEN=(-gdir=res://tests/instruments/ai -gselect=test_generate_screen_field)

# One run first, alone: it refreshes the class cache if it is stale, which the
# parallel shards must not all race to do.
bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards >/dev/null 2>&1 || true

pids=()
for ((i = 0; i < SHARDS; i++)); do
  MITTS_SCREEN_SHARD=$i MITTS_SCREEN_SHARDS=$SHARDS \
    bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_measure_a_shard \
    > "${TMPDIR:-/tmp}/screen_field_shard_$i.log" 2>&1 &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"
done
MITTS_SCREEN_MERGE=1 MITTS_SCREEN_SHARDS=$SHARDS \
  bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards
