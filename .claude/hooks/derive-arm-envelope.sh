#!/bin/bash
# Derives the carry's envelope table (data/arm_envelope.json) from the arm
# anatomy model: one Godot process per build height and trunk state
# (tests/instruments/actors/test_derive_arm_envelope.gd), at most JOBS at once
# (default: the core count), then merged. Run whenever the model, the body or
# the carry posture changes; test_arm_envelope_is_current.gd fails until you
# do. Expect about an hour on four cores.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
PARTS=6
GEN=(-gdir=res://tests/instruments/actors -gselect=test_derive_arm_envelope)

# One run first, alone: it refreshes the class cache if it is stale, which the
# parallel parts must not all race to do.
bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_parts >/dev/null 2>&1 || true

for ((i = 0; i < PARTS; i++)); do
  while (( $(jobs -rp | wc -l) >= JOBS )); do
    wait -n
  done
  MITTS_ENVELOPE_PART=$i \
    bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_derive_a_part \
    > "${TMPDIR:-/tmp}/arm_envelope_part_$i.log" 2>&1 &
done
wait
grep -h "held" "${TMPDIR:-/tmp}"/arm_envelope_part_*.log || true
MITTS_ENVELOPE_MERGE=1 \
  bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_parts
