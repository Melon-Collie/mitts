#!/bin/bash
# Writes tests/unit/ai/data/threat_truth.txt — the measured threat of staged
# possessions across the ice (docs/xt-plan.md, Step 1), which
# test_threat_vs_truth.gd scores the bots' models against. Shards the cells over
# SHARDS Godot processes (default: the core count), then merges. Expect hours.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARDS="${SHARDS:-$(nproc 2>/dev/null || echo 4)}"
GEN=(-gdir=res://tests/instruments/ai -gselect=test_threat_truth)

# One run first, alone: it refreshes the class cache if it is stale, which the
# parallel shards must not all race to do.
bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards >/dev/null 2>&1 || true

pids=()
for ((i = 0; i < SHARDS; i++)); do
  MITTS_THREAT_SHARD=$i MITTS_THREAT_SHARDS=$SHARDS \
    bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_measure_a_shard \
    > "${TMPDIR:-/tmp}/threat_truth_shard_$i.log" 2>&1 &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"
done
MITTS_THREAT_MERGE=1 MITTS_THREAT_SHARDS=$SHARDS \
  bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_shards
