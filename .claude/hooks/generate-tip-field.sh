#!/bin/bash
# Regenerates Scripts/domain/ai/generated/tip_field_data.gd — what a net-front
# stick held to deflect does to a shot at the live goalie, the tip the bots'
# net-front reads price (docs/bot-net-front-offense-plan.md, steps 2c and 5). Run
# it whenever the goalie or the tip changes; test_tip_field_is_current.gd fails
# until you do. Shards the cells
# over SHARDS Godot processes (default: the core count), then merges.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARDS="${SHARDS:-$(nproc 2>/dev/null || echo 4)}"
GEN=(-gdir=res://tests/instruments/ai -gselect=test_generate_tip_field)

# One run first, alone: it refreshes the class cache if it is stale, which the
# parallel shards must not all race to do.
bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards >/dev/null 2>&1 || true

pids=()
for ((i = 0; i < SHARDS; i++)); do
  MITTS_TIP_SHARD=$i MITTS_TIP_SHARDS=$SHARDS \
    bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_measure_a_shard \
    > "${TMPDIR:-/tmp}/tip_field_shard_$i.log" 2>&1 &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"
done
MITTS_TIP_MERGE=1 MITTS_TIP_SHARDS=$SHARDS \
  bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards
