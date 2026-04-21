# Netcode Improvements Plan

Ordered by impact-to-effort ratio. Items 1–4 are bugs/correctness fixes; 5–9 are quality improvements.

---

## 1. Fix Board Collision During Reconcile Replay

**Why:** `LocalController.reconcile` replays inputs with `global_position += velocity * delta`, bypassing `move_and_slide()`. The server runs full Jolt physics. Any board bounce during an unacknowledged window produces a diverging replayed trajectory → another reconcile fires next packet → feedback loop of snaps during board play. This is the highest-impact correctness gap.

**Files:** `Scripts/controllers/local_controller.gd`

**Approach:**
- Add a helper `_apply_rink_bounds(position: Vector3, velocity: Vector3) -> Vector3` that checks the replayed position against the rink's axis-aligned wall planes (read from `GameRules` constants: rink half-width, half-length, corner radii) and reflects velocity on contact, returning the clamped position.
- Call this after each `global_position += velocity * delta` step inside the replay loop in `reconcile()`.
- Corner geometry: the four rink corners are circular arcs. Approximate each as a 45° diagonal wall for the replay check — close enough to eliminate the runaway divergence without needing full Jolt.
- Do not attempt to simulate other players during replay; only the static rink boundary matters here.

**Key constraint:** `GameRules` already has the rink geometry constants. Use those, don't hardcode.

---

## 2. Wire RTT into the Debug Overlay

**Why:** The F3 overlay currently shows "RTT placeholder". `ClockSync` already computes `latest_rtt_ms` and `avg_rtt_ms`. This is a one-liner fix and makes the overlay immediately useful for tuning all other timing constants.

**Files:**
- `Scripts/networking/network_telemetry.gd` — add `rtt_ms: float` field
- `Scripts/networking/clock_sync.gd` — already has `latest_rtt_ms`, `avg_rtt_ms`
- `Scripts/networking/network_manager.gd` — expose RTT via a getter (e.g. `get_avg_rtt_ms()`)
- `Scripts/ui/network_debug_overlay.gd` — replace the placeholder string

**Approach:**
- Add `var rtt_ms: float = 0.0` to `NetworkTelemetry`.
- In `NetworkManager._process` (where telemetry is ticked), set `NetworkTelemetry.instance.rtt_ms = _clock_sync.avg_rtt_ms` (use the smoothed average, not `latest_rtt_ms`, to avoid jitter in the display).
- In `NetworkDebugOverlay._process`, read `NetworkTelemetry.instance.rtt_ms` and render it as `"RTT: %.0f ms" % rtt_ms`.

---

## 3. Hermite Interpolation for Puck

**Why:** Skaters get cubic Hermite interpolation (smooth C1 arcs). The puck uses linear lerp despite `PuckNetworkState` carrying velocity. At 40 Hz with a 75 ms delay the puck visibly wobbles on curved paths post-deflection. Fix is identical to the skater Hermite already implemented.

**Files:** `Scripts/controllers/puck_controller.gd`, `Scripts/networking/buffered_state_interpolator.gd`

**Approach:**
- `BufferedStateInterpolator` already has `_hermite(p0, v0, p1, v1, t, dt)`. Confirm it's exported/accessible (it's a static helper in `remote_controller.gd` or a shared util — if private, move it to `BufferedStateInterpolator`).
- In `puck_controller._interpolate()`, replace:
  ```gdscript
  puck.global_position = from_state.position.lerp(to_state.position, t)
  ```
  with the Hermite call using `from_state.velocity` and `to_state.velocity` as tangents, scaled by the time interval `dt` between the two snapshots (same pattern as `remote_controller._interpolate`).
- Verify puck velocity is correctly populated in `PuckNetworkState` from the `RigidBody3D`'s `linear_velocity` at broadcast time — it should be, but confirm.

---

## 4. Session-Relative Timestamps

**Why:** `last_processed_host_timestamp` is encoded as a raw IEEE 754 float32. At 60+ minute sessions f32 precision degrades toward one physics tick (4.17 ms), causing reconcile cursor mismatches. Also applies to all `host_timestamp` fields in RPCs (pickup claims, shot releases, hit claims).

**Files:** `Scripts/networking/network_manager.gd`, `Scripts/game/world_state_codec.gd`, `Scripts/controllers/local_controller.gd`, `Scripts/controllers/remote_controller.gd`, `Scripts/input/input_state.gd`

**Approach:**
- In `NetworkManager`, record `_session_start_ms: int = Time.get_ticks_msec()` when the game scene initializes (`on_game_scene_ready`). Expose `get_session_relative_ms() -> int` returning `Time.get_ticks_msec() - _session_start_ms`.
- `InputState.host_timestamp`: change storage to `host_timestamp_ms: int` (session-relative milliseconds, u32 range = 49 days). Update `InputState.to_array()` / `from_array()` accordingly — update the array length sentinel test in `tests/unit/game/test_input_state.gd`.
- In `WorldStateCodec._encode_skater_quantized`, encode `last_processed_host_timestamp` as `encode_u32` (session-relative ms) instead of `encode_float`. Update `_decode_skater_quantized` to match. This changes the skater byte count from 35 → 35 (replaces 4-byte f32 with 4-byte u32, net zero change).
- All RPC calls that pass `host_timestamp` (pickup claim, shot release, hit claim): convert the float seconds value to `int` milliseconds at call site, convert back at receive site.
- `ClockSync.estimated_host_time()` already returns float seconds — keep internally, but convert to session-ms only at the RPC/wire boundary.

**Note:** This is a wire format change. Both host and client must update together (they always ship as the same binary, so no compatibility concern).

---

## 5. Faster Adaptive Interpolation Delay

**Why:** `move_toward(current_delay, target, 0.005 * delta)` at 240 Hz gives ~0.021 ms of movement per physics tick — about 5 seconds to shift delay by 25 ms. A sudden RTT spike leaves the system extrapolating for seconds while the delay slowly catches up.

**Files:** `Scripts/controllers/remote_controller.gd`, `Scripts/controllers/puck_controller.gd`, `Scripts/networking/network_telemetry.gd`, `Scripts/networking/network_manager.gd`

**Approach:**
- Replace the `move_toward` adaptation (which runs every physics tick at 240 Hz) with a per-packet adaptation (runs at 40 Hz when a world-state packet is received).
- On each received world-state packet, compute: `target = clamp(rtt_s / 2.0 + jitter_p95_s * 1.5, max(rtt_s / 2.0, 0.016), 0.150)` (this formula already exists in `get_target_interpolation_delay`).
- Apply: `interpolation_delay = lerp(interpolation_delay, target, 0.15)` — 15% blend per packet. At 40 Hz this settles in ~15 packets (~375 ms), fast enough to track RTT spikes without snapping.
- Cap maximum upward adaptation per packet at +5 ms (allow fast increase) and downward at −1 ms (slow decrease) to prevent thrashing on momentary spikes.
- Remove the per-physics-tick `move_toward` call from `_interpolate()`.

---

## 6. Fix Queue-Depth Clock Nudge Rate

**Why:** `apply_queue_depth_feedback` nudges `_offset` by `-(depth - 2) * 0.0005` per call. At 40 Hz with a 3-tick queue surplus the actual walk rate is 60 ms/s, not the 10 ms/s the comment states. During a lag spike this aggressively shifts the client clock, shrinking the lag-comp rewind window and invalidating pickup claims.

**Files:** `Scripts/networking/clock_sync.gd`

**Approach:**
- Add a `_clock_walk_budget: float` accumulator that caps the total offset change applied per second.
- Enforce `MAX_CLOCK_WALK_PER_SEC = 0.010` (10 ms/s — what the current comment intends).
- In `apply_queue_depth_feedback`, compute the desired nudge, add it to the budget accumulator, and only apply up to `MAX_CLOCK_WALK_PER_SEC / 40.0` per call (0.25 ms max per packet at 40 Hz).
- Reset the budget accumulator each second (or use a token-bucket pattern).
- Update the comment to match the actual enforced rate.

---

## 7. Increase Interpolation Buffer Capacity

**Why:** 10 entries at 40 Hz = 250 ms of buffer. With a 75 ms delay, headroom before forced extrapolation is only 175 ms — a 7-packet burst exhausts it. Memory cost of enlarging is negligible.

**Files:** `Scripts/controllers/remote_controller.gd`, `Scripts/controllers/puck_controller.gd`, `Scripts/controllers/goalie_controller.gd` (if it has its own buffer cap)

**Approach:**
- Raise the buffer cap constant from `10` to `30` entries in all three interpolating controllers.
- At 40 Hz, 30 entries = 750 ms of buffer. With 150 ms max interpolation delay there's 600 ms of headroom — sufficient for any practical burst.
- Confirm `BufferedStateInterpolator.drop_stale` still runs to prevent indefinite growth; the cap is a safety net, not the primary trim mechanism.

---

## 8. Goalie Rotation Quantization

**Why:** `GoalieNetworkState` encodes `rotation_y` as a raw f32 (4 bytes) while the skater's `upper_body_rotation_y` is quantized to s16 (2 bytes). Inconsistent and wastes 2 bytes per goalie per packet.

**Files:** `Scripts/game/world_state_codec.gd`, `Scripts/networking/goalie_network_state.gd`

**Approach:**
- In `_encode_goalie_quantized`: replace `b.encode_float(o, s.rotation_y)` with `b.encode_s16(o, roundi(s.rotation_y / PI * 32767.0))`. Update offset accordingly (saves 2 bytes → goalie now 8 bytes).
- In `_decode_goalie_quantized`: replace `decode_float` with `decode_s16(o) / 32767.0 * PI`.
- Update the `GOALIE_BYTE_SIZE` constant and any byte-size assertions/comments.
- Update tests if `WorldStateCodec` has a round-trip test covering goalie state.

---

## 9. Dead-Reckoning Friction for Puck Trajectory Prediction

**Why:** Client-side puck trajectory prediction relies on Jolt running free. If the client's ice friction constant doesn't exactly match the server's Jolt friction, trajectories diverge and trigger frequent hard snaps (>3 m threshold). Adding explicit friction to the prediction gives the client a better model.

**Files:** `Scripts/controllers/puck_controller.gd`, `Scripts/domain/config/game_rules.gd`

**Approach:**
- In `PuckController._physics_process`, during trajectory prediction mode (`_predicting_trajectory == true`), after Jolt has already stepped the puck, apply an additional velocity damping: `puck.linear_velocity *= pow(1.0 - GameRules.ICE_FRICTION, delta)` to bring the client model in line with whatever the server's physics constant is.
- Alternatively (cleaner): expose a `prediction_friction_scale: float` export on `PuckController` and tune it so client trajectories match server trajectories over a 2–3 second free-puck slide. Start at `ICE_FRICTION` and tune empirically.
- This won't fully fix spin/curl (which requires a Magnus force model), but eliminates the linear speed divergence that causes most hard snaps.

---

## Implementation Order

| # | Item | Effort | Impact |
|---|------|--------|--------|
| 1 | Board collision in replay | Medium | Critical |
| 2 | RTT in debug overlay | Trivial | High (observability) |
| 3 | Hermite puck interpolation | Small | High (visual) |
| 6 | Clock nudge rate cap | Small | High (correctness) |
| 4 | Session-relative timestamps | Medium | Medium (long sessions) |
| 5 | Faster delay adaptation | Small | Medium |
| 7 | Larger interpolation buffers | Trivial | Medium |
| 8 | Goalie rotation quantization | Trivial | Low (cleanup) |
| 9 | Puck friction dead-reckoning | Small | Medium |

Items 2, 7, and 8 can be done in a single sitting. Items 3 and 6 are a half-session each. Item 1 is the largest and should be done on its own with careful testing on a local two-machine session, focusing on board battles and corner bounces.
