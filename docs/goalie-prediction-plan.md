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

1. **The wire set on the wire.** `KeeperWire` (writer/reader, Q16 scales), each
   keeper class's `write_wire` / `read_wire`, the host snapping on broadcast
   ticks, the blobs appended after the snapshot body in `_broadcast_state`
   (inside the delta), `WirePacking.SNAPSHOT_MAX_RAW` raised, protocol bump.
   Clients decode and keep the newest state but still draw the interpolated
   pose. Tests: round trip; a client keeper rebuilt from the bytes steps
   identically to the snapped host through a scripted play; the field list
   matches the instrument's wire set; encode cost.
2. **The client predicts.** A predictor keeper per goalie on clients, re-seeded
   on each snapshot, stepped to the render instant every frame against a
   shadow world: a shadow puck placed from the client's own puck prediction at
   each stepped instant (never the real puck node — the keeper writes to the
   puck it holds), and skaters at the instant from the remote buffers' forward
   prediction and the local prediction history. Its pose and save boxes become
   the drawn goalie's, so the local skater's clamps and the predicted puck's
   goalie stop read him on the render clock. The interpolated path stays as the
   fallback (clock warm-up, no state yet, deep loss).
   **Re-step only on a mismatch.** The predictor is exact (deterministic
   keeper, snapped host), so when a snapshot for tick S arrives the client has
   usually already predicted S to the bit. It keeps its own state from tick S
   (the same wire encoding), compares it with the snapshot's, and re-seeds and
   re-steps the span only when they differ — a release it could not see, a
   contact it did not predict. Otherwise it keeps running, one step per tick
   like the host. Re-stepping the span on every snapshot is what made the
   measured cost 3.8–9.9× the host's; this is the rollback netcode pattern.
   Intermediate steps skip seating his 22 save boxes on their nodes (~80 µs of
   a ~200 µs step) unless the keeper's own logic reads them mid-step; only the
   render instant is drawn and tested. A native port of the save choice (~2 ms a
   choosing tick) comes after, only if the measured per-frame cost on a release
   build / Steam Deck still asks for it — the keeper is still being tuned, and a
   port freezes it behind parity tests.
3. **Measure and tune.** F3: predicted-vs-host disagreement at the snapshot
   (the host state the client predicted, compared when it arrives) and the
   per-frame step cost. Networking `CLAUDE.md` rewritten for the goalie on the
   render clock.
4. **Shot field.** The keeper sources change, so `test_shot_field_is_current`
   needs a regeneration — on the user's machine: this container does not
   reproduce the committed field (199 rows move with or without the snap).
