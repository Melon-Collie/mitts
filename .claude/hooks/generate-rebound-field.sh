#!/bin/bash
# Regenerates Scripts/domain/ai/generated/rebound_field_data.gd — what the live
# goalie's save does with a shot, the rebound the bots' net-front reads price
# (docs/bot-net-front-offense-plan.md, step 2a). Run it whenever the goalie
# changes; test_rebound_field_is_current.gd fails until you do. Shards the shots
# over SHARDS Godot processes (default: the core count), then merges.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARDS="${SHARDS:-$(nproc 2>/dev/null || echo 4)}"
GEN=(-gdir=res://tests/instruments/ai -gselect=test_generate_rebound_field)

# One run first, alone: it refreshes the class cache if it is stale, which the
# parallel shards must not all race to do.
bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards >/dev/null 2>&1 || true

pids=()
for ((i = 0; i < SHARDS; i++)); do
  MITTS_REBOUND_SHARD=$i MITTS_REBOUND_SHARDS=$SHARDS \
    bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_measure_a_shard \
    > "${TMPDIR:-/tmp}/rebound_field_shard_$i.log" 2>&1 &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"
done
MITTS_REBOUND_MERGE=1 MITTS_REBOUND_SHARDS=$SHARDS \
  bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards
