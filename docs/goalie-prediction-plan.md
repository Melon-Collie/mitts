# Goalie prediction on the render clock — build plan (#903)

The agreed design for #903, after the measurements in
`docs/goalie-prediction-measurements.md` and the option in
`docs/goalie-rebuild-plan.md` → *Open: the client predicts the goalie on the
render clock*. The user chose the exact version, built in full.

## What it is

A client draws every entity at `estimated_host_time() + input_lead` except the
goalie, who is interpolated at `H − d`. Instead, each snapshot carries the
keeper's whole simulation state (his "wire set"); a client re-seeds a keeper of
its own from the newest one and steps the same keeper code forward to the
render instant, every frame. It never free-runs: every snapshot re-seeds it.
Client-side goalie AI with soft correction stays banned — this is a replay of
the host's keeper from the host's state, not an AI of the client's own.

## Decisions, and the measurement behind each

- **Q16, and the host snaps to it.** The wire set travels at Q16 (positions
  1 mm, angles π/32767, clocks 1 ms, fractions 1e-4, velocities 2.5 mm/s, ints
  s8, bools as bits, poses through `KeeperPoseCodec`). On its own Q16 drifts
  (up to 83 cm); with the host keeper setting his own wire set to its Q16 value
  on every broadcast tick, the client rebuilt from the bytes is exact, and on 97
  shots the host's play did not change. The snap runs only when the host
  broadcasts, so offline play — what the shot field and the shot-odds truth
  measure — is untouched by it.
- **The play read's history is sent, not rebuilt.** Rebuilding it from the
  client's 45 Hz centimetre snapshots saves ~67 B a keeper delta'd and breaks
  exactness at every one-way.
- **It rides the delta channel, outside the recorded frame.** The keeper blobs
  follow the world-state body inside `SnapshotDelta`'s delta (so they compress
  to ~+145 B a keeper against the previous acked snapshot) and never enter the
  replay recorders' frames, so replay files and their format are unchanged.
- **The codec is hand-written.** A generic reflective codec costs ~1.3 ms a
  keeper to encode; each keeper class writes and reads its own wire fields
  through a typed writer/reader instead.
- **Cost on the client is the risk.** Stepping two keepers the span costs a
  client ~3–8 ms a frame on a debug build (3.8–9.9× the host); the step is
  bounded and measured per frame in F3, and a release build / Steam Deck number
  is the first thing the playtest reads.

## Phases

1. **The wire set on the wire. Done (protocol v96).** `KeeperWire`
   (`Scripts/domain/keeper/keeper_wire.gd`) is one writer-or-reader, and each
   keeper class hands it its own fields in a fixed order through one method,
   `wire(w)`, so the write and the read walk one list; `KeeperController.wire`
   is the walk from the top. Writing snaps: each value is stored back as a
   reader decodes it, so writing his blob on a broadcast tick is the host's
   snap, his node and boxes re-placed on the snapped pose. A field whose range
   a 16-bit step count cannot hold is written in 32 bits at the same scale: the
   play read's and the shot read's places (the puck anywhere on the rink),
   every clock (some run on: `_out_of_reach_s`, `_spot_since`), every angle
   that can wind past π, the spot's and the motor's velocities. The blob rides
   behind the raw snapshot inside the delta (`KeeperWireTail`), split back off
   before any decoder on a client and kept per goalie with its host time
   (`GoalieController.receive_wire_state`); the recorders' frames never hold it,
   so replay FORMAT_VERSION is unchanged; `SNAPSHOT_MAX_RAW` 4096 → 8192.
   Measured (`benchmarks/test_keeper_wire_benchmark.gd`, the keeper facing a
   slot wrister and a carry across and a shot, this container's debug binary):
   **2,452 B raw a keeper**, fixed (2,457 since Phase 2's tier byte and
   discrete digest); zstd alone 565 B mean; **XOR against the
   blob 1 / 3 broadcasts back then zstd: 114 / 142 B mean, 200 / 268 B p95**,
   each with ~19 B of zstd frame a real snapshot shares. Host, per keeper per
   broadcast: the write ~220 µs p50 (~305 p95), the write and the re-placing
   ~330 µs p50 (~430 p95), ~110 µs of it seating his 22 boxes on the snapped
   pose; a client's read ~210 µs, read and placed ~310 µs. Exact:
   `tests/slow/controllers/test_keeper_wire_is_exact.gd` rebuilds a keeper from
   the host's blob every 12 ticks through both plays and steps it on in a world
   of its own, snapping on the host's ticks; 0.0 m box gap, the same save and
   the same puck on every tick, the same blob on every broadcast tick, and the
   host's first contact and its outcome the same with the snap as without.
   `tests/unit/controllers/test_keeper_wire_set.gd` holds the wire set against
   the instrument's: every reachable field not on its `NOT_ON_WIRE` round-trips.
2. **The client predicts. Done (protocol v97).** `KeeperPredictor`
   (`Scripts/controllers/keeper_predictor.gd`) is a client's own keeper per
   goalie — its own `KeeperController` on a shadow `Goalie`, a
   `KeeperShadowPuck` and `KeeperShadowSkater`s, hidden, never processed, in
   no group — re-seeded from a snapshot's blob at that snapshot's tick (ticks
   counted from the world state's sequence, which now rides with the blob) and
   stepped by `KeeperController.step_sim`, the host's own tick, to
   `estimated_host_time() + clamped lead`, snapping on the broadcast ticks. Its
   world is `GameKeeperWorld`: remote skaters from `sample_state_at`, the local
   one from `LocalController.predicted_at`, the puck on its drawn carrier or
   loose and stepped by the re-predict's own whole-tick step from where the
   client last knew it loose (`PuckController.loose_origin`,
   `step_loose_tick`), a carried→loose change heard as a release. The host
   keeper's reads are untouched: the seam is the keeper's own nodes (his
   goalie, his puck, his skater getter), which the predictor hands shadow ones;
   the offline keeper is bit-identical to Phase 1's (a digest of every box and
   the puck through both harness plays). The drawn goalie is the two stepped
   ticks around the render instant blended into a `GoalieNetworkState` and
   posed by `_apply_interpolated`, so his boxes are seated where he is drawn; a
   shadow keeper seats only the boxes that place a part body (his own reads go
   through the glove, the mask and the blocker). The fallback is the
   interpolated path (no blob, the clock not ready, the newest snapshot past
   `PUCK_PREDICT_MAX_S`, replays). The blob also carries his tier
   (`GoalieSkillProfile.tier`): a client never learned the host's goalie
   difficulty, and the tier's tuning is off the wire.
   **Re-step only on a mismatch.** The predictor keeps its own blob and drawn
   state at each broadcast tick. A snapshot confirms him when its blob equals
   his byte for byte, or when the host's drawn goalie in the same snapshot (its
   goalie block) sits within `KeeperPredictor.CONFIRM_GAP_M` (1 cm) of his,
   stands in the same stance and the two blobs' discrete digests agree (a u32
   FNV over every int and bool he wrote, the play read's flag runs left out,
   `KeeperWire.discrete_digest`); otherwise he re-seeds there and re-steps the
   span. Without the digest, a carry across confirmed a keeper a millimetre from
   the host's who had not committed to the move the host's had, and he was
   drawn 43 cm off until it showed in the boxes; the shot hidden from him was
   corrected a snapshot late.
   Bit-equality alone never confirmed in play — his play read keeps millimetres
   and a client's world is centimetre snapshots and its own predictions — so it
   re-stepped every snapshot, ~45 a second a goalie. Within the tolerance he
   runs on a state that is not the host's to the bit, and the next snapshot
   that parts by more re-seeds him. Measured
   (`benchmarks/test_keeper_predictor_benchmark.gd`, two predicted goalies per
   60 fps frame, the facing keeper twice, this container's debug build):

   | world fed | one-way | snapshots confirmed | re-steps a second (two goalies) | steady frame mean / p95 | re-step frame mean / p95 |
   |---|---|---|---|---|---|
   | the host's, exact | 15 / 50 / 100 ms | 100% | 0 | 1.1 / 1.7, 1.1 / 1.5, 1.2 / 1.5 ms | — |
   | on the snapshot's grid (1 cm, 0.02 m/s), byte equality only | 15 / 50 / 100 ms | 0% | ~90 | 0.6 / 0.6, 1.6 / 4.0, 1.3 / 1.7 ms | 5.2 / 6.9, 9.2 / 13.3, 14.2 / 20.9 ms |
   | on the snapshot's grid, the 1 cm tolerance only | 15 / 50 / 100 ms | 99% | 0.8–0.9 | 1.4 / 2.1, 1.4 / 2.0, 1.5 / 2.3 ms | 5.6 / 6.0, 9.7 / 11.1, 17.0 / 17.0 ms |
   | on the snapshot's grid, the tolerance and the digest | 15 / 50 / 100 ms | **97%** | **2.5–2.6** | 1.5 / 2.5, 1.7 / 3.7, 1.5 / 1.9 ms | 5.1 / 6.5, 11.3 / 15.2, 16.4 / 20.5 ms |

   The host's own two keepers cost 0.77 ms a frame on the same machine. A
   re-step frame still spikes by the span (a release the client could not see,
   a decision the grid tipped the other way), a few times a second a goalie; porting the save choice to native code is the
   lever for that spike if the playtest's release-build numbers ask for it.
3. **Measure and tune.** Started: F3 *Goalie predict* (snapshots confirmed,
   re-steps a second, the box gap at a re-step's snapshot) and *Goalie predict
   cost* (both predictors' time a physics frame, mean and p95), in the session
   row as `keeper_*` (`docs/telemetry_dictionary.md`); networking `CLAUDE.md`
   rewritten for the goalie on the render clock. Left: the playtest's numbers
   on a release build and a Steam Deck, and the rollback decision above.
4. **Shot field. Done.** The keeper sources changed, so the field was
   regenerated (`.claude/hooks/generate-shot-field.sh`). The snap runs only
   online, so the offline keeper the field measures is unchanged: 199 of 2,744
   cells moved, the same count a regeneration of the unchanged code moved on
   this container, 926 of ~198k outcomes flipped, symmetric (+27 goals net).
