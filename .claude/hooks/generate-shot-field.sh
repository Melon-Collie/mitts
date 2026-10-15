#!/bin/bash
# Regenerates Scripts/domain/ai/generated/shot_field_data.gd — the live goalie's
# open set the bots' shot odds are read from (docs/shot-currency-plan.md). Run it
# whenever the goalie changes; test_shot_field_is_current.gd fails until you do.
# Shards the cells over SHARDS Godot processes (default: the core count), then
# merges. Expect tens of minutes.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARDS="${SHARDS:-$(nproc 2>/dev/null || echo 4)}"
GEN=(-gdir=res://tests/instruments/ai -gselect=test_generate_shot_field)

# One run first, alone: it refreshes the class cache if it is stale, which the
# parallel shards must not all race to do.
bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards >/dev/null 2>&1 || true

pids=()
for ((i = 0; i < SHARDS; i++)); do
  MITTS_FIELD_SHARD=$i MITTS_FIELD_SHARDS=$SHARDS \
    bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_measure_a_shard \
    > "${TMPDIR:-/tmp}/shot_field_shard_$i.log" 2>&1 &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"
done
MITTS_FIELD_MERGE=1 MITTS_FIELD_SHARDS=$SHARDS \
  bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards
