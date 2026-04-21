# Netcode Improvement Plan

Priority order is based on impact-to-effort ratio and dependencies between changes.
Changes within a tier can be done in any order unless noted.

---

## Tier 1 — Quick Wins (low effort, meaningful payoff)

### 1. Fix pickup lag compensation rewind depth ✓ already implemented

**File:** `Scripts/game/game_manager.gd` (or wherever `pickup_claim_received` is handled)

The pickup claim already sends `interp_delay_ms` but the host rewind only goes back `rtt/2`.
When the puck is in interpolating mode the client is responding to a position that's
`rtt/2 + interp_delay` old — not just `rtt/2`. A fast-moving puck introduces a ~3 cm
error at 75 ms delay that either grants bad claims or rejects good ones.

**Change:** When validating a pickup claim, compute rewind depth as:
```
rewind_depth = rtt_ms / 2000.0 + interp_delay_ms / 1000.0
```
Use this when reading the puck position from `StateBufferManager` instead of `rtt/2` alone.
Only apply the full depth when the puck's current mode is interpolating; during trajectory
prediction the client is at present time and `rtt/2` is correct.

---

### 2. Clock sync rate increase ✓ done

**File:** `Scripts/networking/clock_sync.gd`

The ongoing ping fires every 5 seconds. Through an 8-sample window that means a network
change (WiFi drop, congestion) takes 40+ seconds to fully propagate into the offset estimate.
At 80–100 ms RTT a stale clock means pickup claim timestamps can be off enough to fail
host validation.

**Change:** Reduce ongoing ping interval from `5.0` to `2.0` seconds. Also consider dropping
both the 2 highest AND 2 lowest RTT outliers instead of only the 2 highest — it's more robust
against occasional scheduler gifts that produce anomalously fast round-trips.

---

### 3. Input queue target depth ✓ done

**File:** `Scripts/networking/clock_sync.gd` — `apply_queue_depth_feedback`

Target depth is `2`. At 240 Hz physics / 60 Hz input, a batch of 12 inputs drains to 0
between arrivals under normal conditions. Any jitter spike empties the queue and triggers
repeated-input fallback. A target of 5–6 gives a comfortable cushion without adding
meaningful latency (6 extra inputs at 240 Hz = 25 ms).

**Change:** Change the target queue depth constant from `2` to `5` (or expose it as a tunable).

---

### 4. Velocity quantization resolution ✓ done

**File:** `Scripts/game/world_state_codec.gd`

Skater and puck velocities are encoded at `0.1 m/s` resolution. A puck rolling at `0.15 m/s`
encodes as `0.2`, a 33% relative error. This shows up as subtle Hermite interpolation artifacts
on slow movements and slightly wrong soft-reconcile blends during trajectory prediction.

**Change:** Re-encode velocity as `s16 @ 0.02 m/s` (range ±655 m/s, well above any shot speed).
Update encode/decode in `WorldStateCodec` only — all typed state objects stay unchanged.
Packet size increases by ~6 bytes per skater and ~6 bytes for the puck; negligible.

---

### 5. Reduce wall-contact reconcile dead zone ✓ done (0.1→0.05; tune to 0.03 after playtesting)

**File:** `Scripts/controllers/local_controller.gd` — reconcile guard

The wall-jitter suppression skips reconcile when `is_on_wall() and distance < 0.1 m`.
10 cm is too generous. At 240 Hz physics, wall contact noise should be well under 2–3 cm.
The current threshold can mask real desync when a player is pinned against boards after a
body check.

**Change:** Tighten the threshold from `0.1` to `0.03`. Monitor reconcile rate in the telemetry
overlay after changing — if wall reconcile rate spikes visibly, settle at `0.05`.

---

## Tier 2 — Medium Lifts (architectural but self-contained)

### 6. Remote player input extrapolation ✓ done

**Files:** `Scripts/controllers/remote_controller.gd`, `Scripts/networking/buffered_state_interpolator.gd`

Currently remote players are rendered from `interpolation_delay` seconds ago (25–80 ms
depending on RTT/jitter). Every body check and pass is reacting to a stale ghost. Extrapolating
remote players forward from their latest buffered state to present time using last known
velocity and facing halves the perceived staleness at 40 ms RTT and is essential at 80–100 ms.

**Approach:**
- After normal interpolation/extrapolation produces a `render_state`, apply a forward
  prediction step: `predicted_position = render_position + render_velocity * interp_delay`
- Gate this on connection quality: only apply when `extrapolation_dt` is below a threshold
  (don't double-extrapolate during a packet gap)
- The rejoin blend already handles the position correction when a fresher state arrives —
  let it absorb the prediction error on re-entry
- Facing can be extrapolated with the last known angular velocity (or just held; facing
  changes slowly enough that holding is acceptable)

**Risk:** Over-prediction when a remote player reverses direction sharply. Mitigate with a
per-frame cap on how far ahead you're willing to extrapolate (suggest starting at `interp_delay * 0.5`
and tuning up).

---

### 7. Goalie client-side prediction ✓ done

**Files:** `Scripts/controllers/goalie_controller.gd`, `Scripts/domain/rules/goalie_behavior_rules.gd`

At 80–100 ms RTT, a goalie responding to a shot 100 ms late is very visible. `GoalieBehaviorRules`
is already pure domain code with no engine dependencies — it can run on clients against the
locally-known puck state.

**Approach:**
- Client maintains a `GoaliePredictedState` that runs `GoalieBehaviorRules` each physics
  tick using local puck position and local shot state as input
- Blend between interpolated (authoritative) and predicted state: use predicted when the
  interpolation buffer is in extrapolation or when RTT > threshold; use interpolated when
  fresh state is available
- The authoritative interpolated state should win on re-entry (use the existing rejoin blend
  or a similar mechanism)

**Risk:** Goalie AI produces slightly different results on client vs host (floating point, state
divergence). Keep the blend weight tunable so you can fade prediction influence down if visible
snapping occurs.

---

### 8. Deterministic puck prediction model

**Files:** `Scripts/controllers/puck_controller.gd`, `Scripts/actors/puck.gd`

After shot release, the client runs Jolt locally to predict puck trajectory. The host advances
the puck kinematically by `velocity * rtt_half` before starting its Jolt sim. These two
simulations start from slightly different positions and diverge over time. A simple explicit
kinematic model on the client would match the host's initial advance exactly and produce fewer
soft-reconcile artifacts for straight shots.

**Approach:**
- Replace the Jolt-run prediction with explicit integration:
  `velocity *= pow(1.0 - PREDICTION_FRICTION, delta)`
  `position += velocity * delta`
  Wall bounces use `velocity = velocity.reflect(wall_normal) * PREDICTION_RESTITUTION`
- Constants `PREDICTION_FRICTION` and `PREDICTION_RESTITUTION` are exports that need
  calibration against actual Jolt output (test tool: shoot straight at a wall and check that
  client prediction and host outcome agree on the bounce position)
- Jolt is still used for everything else (skater movement, body checks, host puck physics)

**Tradeoff:** Complex multi-bounce trajectories will diverge more from the host than Jolt
would. For most shots (straight or slight curve) the explicit model is more accurate because
it matches the host's own kinematic advance. Accept the tradeoff; multi-bounce trajectories
are rare and short enough that the first soft-reconcile corrects them.

---

## Tier 3 — Larger Efforts (touch multiple systems)

### 9. Input delay

**Files:** `Scripts/controllers/local_controller.gd`, `Scripts/networking/clock_sync.gd`,
`Scripts/input/local_input_gatherer.gd`

Adding 2 physics frames (8 ms at 240 Hz) of input delay means inputs arrive at the host
before their scheduled physics frame, eliminating fallback-input firing on clean low-latency
connections. Imperceptible at 240 Hz but requires careful implementation.

**Approach:**
- Add a `_pending_input_queue: Array[InputState]` in `LocalController` holding inputs
  waiting to be applied
- Each tick: push current gathered input to the queue with a scheduled apply time of
  `now + INPUT_DELAY_FRAMES * physics_delta`; pop and apply any inputs whose scheduled
  time has passed
- Visual feedback (shot charge glow, aim direction) continues to use the gathered input
  immediately — only the physics application (movement, shot state) is delayed
- `estimated_host_time` stamp on each input must reflect the *scheduled apply time*, not
  the gather time, so the host applies it to the right frame
- Reconcile history trim still uses `last_processed_host_timestamp` — no change needed there

**Risk:** The split between "visual now" and "physics later" adds complexity to shot state.
Specifically: the charge/aim display must read from the pending input, not the applied input.
Get reconciliation working correctly before adding input delay on top — it will surface any
timestamp accounting bugs.

**Note:** Input delay helps most at RTT < ~30 ms (LAN / same-city connections). At 100 ms RTT
it has minimal effect on reconciliation frequency. Implement after remote extrapolation.

---

### 10. Comprehensive body check lag compensation

**Files:** `Scripts/game/hit_tracker.gd`, `Scripts/game/game_manager.gd`,
`Scripts/networking/network_manager.gd`

Hit crediting is already lag-compensated via `send_hit_claim` RPC. What's missing is that the
*visual contact* happens against an interpolated (stale) representation of the opponent.
At 80–100 ms RTT players are hitting ghosts from 70–80 ms ago. With remote extrapolation
(change 6) this shrinks significantly, but comprehensive lag compensation for all body contact
would make contested collisions feel consistent.

**Approach:**
- The `send_hit_claim` RPC already carries `host_timestamp` and `rtt_ms`. The host currently
  checks distance at rewind time for crediting. Extend this so the host also echoes back the
  *authoritative contact position* to all clients, letting them play a contact VFX at the
  correct position rather than the locally-predicted one
- This is a visual fix layered on top of the existing crediting system — the game logic
  is already correct, this closes the visual gap
- Requires a new reliable RPC: `notify_hit_contact(hitter_peer_id, victim_peer_id, contact_pos)`
  broadcast from host to all clients on a confirmed hit

---

## Deferred / Post-Playtesting

These are architecturally sound improvements but require a stable, well-tested base first:

- **Adaptive broadcast rate:** increase `STATE_RATE` dynamically under packet loss (currently
  fixed at 40 Hz). Useful above 15% loss but adds complexity.
- **Priority-based state updates:** skaters near the puck carrier get state updates every
  broadcast; skaters far away can be sampled at half rate. Reduces bandwidth ~15% at full
  lobby with no perceptible quality loss for far-away players.
- **Host migration:** if host drops, promote lowest-ping client to host and resume. Large
  effort; deferred until the game has enough players to make it necessary.

---

## Docs to Update After Each Change

Per `CLAUDE.md`, before every commit update:
- `CLAUDE.md` — move completed items out of Known Issues; update Networking Architecture
  section rates/descriptions if they changed
- `README.md` — What's In / Planned sections
- `ARCHITECTURE.md` — Build Status table

`CLAUDE.md` currently documents world state as 20 Hz — it's actually 40 Hz (`Constants.STATE_RATE`).
Fix this in the first commit regardless of which change is done first.
