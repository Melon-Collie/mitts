#!/bin/bash
# Derives the carry's envelope table (data/arm_envelope.json) from the arm
# anatomy model: one Godot process per part, a third of a build height and
# trunk state's bearings (tests/instruments/actors/test_derive_arm_envelope.gd),
# at most JOBS at once (default: the core count), then merged. A part already
# in .preview/arm_envelope_parts is kept, so a run cut short picks up where it
# stopped; FRESH=1 clears them first. Run whenever the model, the body or the
# carry posture changes; test_arm_envelope_is_current.gd fails until you do.
# Expect about an hour and a half on four cores.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
PARTS=18
PART_DIR="$(cd "$HOOKS/../.." && pwd)/.preview/arm_envelope_parts"
if [[ "${FRESH:-0}" == "1" ]]; then rm -rf "$PART_DIR"; fi
GEN=(-gdir=res://tests/instruments/actors -gselect=test_derive_arm_envelope)

# One run first, alone: it refreshes the class cache if it is stale, which the
# parallel parts must not all race to do.
bash "$HOOKS/run-gut.sh" "${GEN[@]}" -gunit_test_name=test_merge_the_parts >/dev/null 2>&1 || true

for ((i = 0; i < PARTS; i++)); do
  if [[ -f "$PART_DIR/part_$i.json" ]]; then
    continue
  fi
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
