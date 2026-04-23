# Architecture

Technical decisions and reference tables for Mitts. Layer model, code conventions, and development workflow are in `CLAUDE.md`.

---

## Design Philosophy

Depth over breadth — few inputs with rich emergent behavior rather than many explicit mechanics.

The Rocket League freeplay ceiling is a guiding star: the stickhandling-to-shot pipeline should reward practice and feel satisfying to master.

**Key inspirations:** Omega Strikers / Rocket League (structure), Breakpoint (twin-stick melee blade feel), Mario Superstar Baseball (stylized characters, exaggerated tuning, pre-match draft). Slapshot: Rebound is a cautionary reference — pure physics shooting feels unintuitive; the blade proximity pickup system is explicitly designed to solve that accessibility gap.

---

## Reference

### Network Rates

| Channel | Rate | Transport |
|---------|------|-----------|
| Input (client → host) | 60 Hz | Unreliable, last 12 frames per packet |
| World state (host → clients) | 40 Hz | Unreliable, ~279 bytes at 6 players (single flat PackedByteArray, well under ENet MTU) |
| Events (pickup, spawn, goal, goalie transitions) | On event | Reliable |
| Stats sync | On change | Reliable |

Interpolation delay: 75ms baseline, adapts per-packet via `lerp(0.15)`, capped at +5ms / −1ms per packet.

Wire format: Skater 35B · Puck 13B · Goalie 8B. ~62% reduction vs unquantized.

### Collision Layers

| Constant | Value | Purpose |
|----------|-------|---------|
| `LAYER_WALLS` | 1 | Boards, ice surface, goalie body parts |
| `LAYER_BLADE_AREAS` | 2 | Skater blade `Area3D`s |
| `LAYER_PUCK` | 8 | Puck `RigidBody3D` |
| `LAYER_SKATER_BODIES` | 16 | Skater `CharacterBody3D` bodies |

Composed masks: `MASK_PUCK = 1` (walls + goalie only, not skater bodies), `MASK_SKATER = 17` (walls + other skater bodies).

The puck's pickup zone `Area3D` sits on `LAYER_WALLS | LAYER_BLADE_AREAS` (3) with `collision_mask = LAYER_BLADE_AREAS` (2) so it detects blade `Area3D`s via `area_entered`.

### Game Phases

| Phase | Duration | Movement |
|-------|----------|----------|
| `PLAYING` | Until goal or clock expires | Full |
| `GOAL_SCORED` | 2s | Locked |
| `FACEOFF_PREP` | 0.5s | Locked |
| `FACEOFF` | Until pickup or 10s timeout | Full |
| `END_OF_PERIOD` | 3s | Locked |
| `GAME_OVER` | Indefinite | Locked |

Period clock ticks only during `PLAYING`. On expiry: if periods remain → `END_OF_PERIOD` → `FACEOFF_PREP` (period increments, clock resets); if last period → `GAME_OVER`.

---

## Decisions

**Authoritative host, no dedicated server.** One player hosts; the host runs all physics. Eliminates server costs and NAT complexity at the expense of host-advantage. Acceptable for a small-scale arcade game.

**No pickup prediction.** Two players can contest the same puck — the server arbitrates who wins. Predicting pickup locally and rolling it back on a contested play feels worse than the single round-trip delay. Pickup is detected server-side via lag-compensated rewind; only the grant confirmation travels to the client.

**Ghost mode over stoppages for offsides and icing.** Stoppages interrupt flow; ghost mode keeps the puck live and lets offending players correct their position. Downside: slightly less legible than a whistle. Acceptable for an arcade game that prioritizes momentum.

**`_carrier_peer_id` managed by reliable RPCs, never world state.** Unreliable packets can arrive out of order relative to pickup/release RPCs, causing the puck to flicker between carried and loose. Reliable RPCs guarantee ordering; world state is ignored for carrier identity.

**Immediate reconcile snap, no gradual position correction.** Gradual blending toward the server state introduces a window where the client is in a known-wrong position. Immediate snap + input replay is always convergent within one reconcile cycle. A visual-only offset blend can be layered on top without affecting physics correctness — tracked as a future improvement (see `docs/specs/NETCODE_AUDIT_2026.md` #3).

**Trajectory prediction exits on physics contact, not only carrier RPCs.** When the predicted puck hits a post or the goalie, host and client diverge immediately — the host's Jolt sees the collision but the client doesn't know to stop predicting. Ending prediction on local post/goalie contact lets the client fall back to interpolation before the divergence compounds.

**Goalie state transitions and shot reactions via reliable RPCs.** Interpolation gives smooth position but can't guarantee reaction timing — a butterfly during a rapid shot sequence may arrive in the wrong bracket order. Reliable RPCs deliver exact state changes; clients play a local reaction timer from the RPC payload for immediate visual feedback.

**Trajectory prediction uses hard-snap only, no soft blend.** Each broadcast computes `latency_corrected.position = state.position + state.velocity * rtt_s` (full-RTT forward correction) and hard-snaps only when divergence exceeds `trajectory_hard_snap_threshold` (1.5m). Soft-blending toward a noisy position target (RTT jitter ±20ms at 20m/s = ±0.4m) causes visible snapback every broadcast tick; Jolt is trusted otherwise.
3. **Interpolation** — buffer server snapshots and interpolate with the same 100ms delay as skaters. Position only — velocity is not applied to the frozen body (`_apply_state_to_puck` is position-only).

**Carrier transitions:**
- Pickup: client sends a reliable `receive_pickup_claim` RPC with `host_timestamp` and `rtt_ms` (raw unaveraged latest sample so rewind depth tracks the current round-trip). Host rewinds `StateBufferManager` to `host_timestamp − rtt/2`, reads `blade_contact_world` (world-space mid-blade, host-only non-serialized field on `SkaterNetworkState`) from the rewound snapshot, runs the segment-segment distance test against the rewound puck path, and either grants the pickup, squirts the puck on a contested claim (two claims within 50ms, contest timer in `_physics_process`), or drops it as stale/invalid. On grant: reliable `notify_puck_picked_up` RPC to the carrier → `on_puck_picked_up_network()` on their LocalController + `notify_local_pickup(skater)` pins puck to blade. Simultaneously, reliable `notify_carrier_changed(peer_id)` broadcast to **all** peers so non-carrier clients exit trajectory-prediction mode regardless of unreliable world-state delivery.
- Release: client predicts immediately (state machine transitions, trajectory prediction begins) → reliable RPC to server to execute physics. Server fires `notify_carrier_changed(-1)` to all peers; carrier's own handler ignores it (guards against killing its own trajectory prediction).
- Poke check (strip): server detects opposing blade contact while `carrier != null` → clears carrier, launches puck via `_poke_check()` → `puck_stripped` signal → reliable RPC to victim client (`notify_puck_stolen`) → victim calls `on_puck_released_network()` + `notify_local_puck_dropped()` to clear carry state and drop back to interpolation.
- Goal scored: server captures carrier peer_id before `puck.drop()` → sends `notify_goal` (reliable, all peers) and `notify_puck_dropped` (reliable, carrier only) as separate RPCs → carrier client clears state in `on_carrier_puck_dropped()`; `puck.drop()` also fires `puck_released` → `notify_carrier_changed(-1)` broadcast. Decoupled so `notify_goal` isn't responsible for carrier cleanup.

`_carrier_peer_id` on clients is managed exclusively by `notify_local_pickup()` / `notify_local_release()` in `PuckController`. It is intentionally never updated from world state — unreliable packet ordering would cause it to conflict with locally-predicted transitions.

### Goalie Networking

**GoalieController** AI runs on both host and client. Clients do not interpolate server snapshots — they run the full goalie state machine every physics tick using their local puck position. This eliminates interpolation delay and keeps goalie reactions immediate. Server broadcasts (40 Hz) soft-correct position only, keeping client and host in sync despite the client tracking a slightly stale puck.

Serialized per goalie: position (x/z), rotation_y, state_enum, five_hole_openness, velocity (x/z) — 7 fields, 8 B quantized. `apply_state` forward-predicts the server position using `velocity * elapsed` (elapsed ≈ RTT/2 at call time), then blends at 40% per broadcast. `five_hole_openness` is computed only on the server; clients adopt it at 80% blend per broadcast so the visual pad gap matches server physics within ~50 ms. The client AI does not recompute `five_hole_openness`, so nothing fights the correction. Body part configs are rebuilt from the running AI state each frame.

State changes (STANDING ↔ BUTTERFLY ↔ RVH) and shot reactions are delivered via reliable RPCs (`apply_state_transition`, `apply_shot_reaction`). `apply_state_transition` directly sets the client state machine. `apply_shot_reaction` seeds `_shot_timer` on the client so the butterfly drop cadence matches the server.

RVH triggers when `_is_puck_in_defensive_zone()` — either the puck is behind the goal line, or it is within `zone_post_z` of the goal line and the horizontal angle to the puck exceeds `rvh_early_angle` (default 60°). This matches the Buckley depth chart's "Defensive" corner zones, which extend slightly in front of the goal line at sharp angles.

**Tracking lag:** `GoalieController` maintains `_tracked_puck_position` that lerps toward the real puck at `tracking_speed` (default 6.0) each frame. All positioning logic — lateral target, depth, facing, and state transitions — reads from this tracked position rather than the real puck. `_on_puck_released` (shot detection, server only) reads the real puck position and velocity so butterfly reactions stay accurate. `tracking_speed` is the master difficulty export: lower = more positional lag.

### Puck Interactions (server-side)

All puck contact logic runs on the host via `PuckController._check_interactions` each physics tick using swept-segment distance tests in `PuckInteractionRules`:

- **Segment-segment detection:** both `check_pickup` and `check_poke` use an Eberly analytical segment-segment minimum distance test. The puck is swept `puck_prev → puck_curr`; the blade is swept `blade_prev → blade_curr` (previous position stored at the top of `Skater._physics_process`). This catches fast blade swings through the pickup zone even when the puck is nearly stationary — the old static-blade test would miss those.
- **Catch vs deflect:** relative velocity `(puck_vel - blade_world_vel).length()` against `deflect_min_speed`. Moving your blade backward with the puck reduces relative velocity → catch. Stationary blade hit by fast puck → deflect. Below `pickup_max_speed` always catches.
- **Deflect direction:** contact normal = `(puck_pos - blade_world_pos).normalized()` (billiard ball style). Physical reflection blended toward incoming direction via `deflect_blend`. If `skater.is_elevated`, outgoing direction is tilted upward by `deflect_elevation_angle`.
- **Poke check:** when any blade's sweep path passes within radius of the puck while `carrier != null`, `_poke_check` strips the puck (no team gate — teammates can strip each other). Strip direction = `checker_blade_vel + carrier_blade_vel * poke_carrier_vel_blend` (or spatial direction as fallback). Ex-carrier gets `reattach_cooldown`; checker gets brief `poke_checker_cooldown`.
- **Body check strip:** `SkaterController._on_body_checked_player` (server only) calls `puck.on_body_check(checker, victim, force, direction)`. If `force = weight × approach_speed ≥ body_check_strip_threshold` and `victim == carrier`, `_body_check_strip` clears the carrier and launches the puck in the hit direction. Emits `puck_stripped` + `puck_released` — same notification path as poke check. `Skater` also emits `body_check_impulse_applied(impulse)` with the total velocity delta from `_resolve_player_collisions()` each tick (attacker rebound + victim transfer from remote's check both included). `LocalController` connects to this signal and injects the complete delta into kinematic reconcile replay at the matching `host_timestamp`; the old `body_checked_player` approach captured only the attacker rebound, causing consistent under-correction and jitter. Body check VFX fires client-side from the sim — `SkaterVFX` connects to `body_checked_player` on every skater; no RPC needed.
- **Passive body block:** each `Skater` has a `BodyBlockArea` (`Area3D`, `collision_layer = 0`, `collision_mask = LAYER_PUCK`, sphere radius `body_block_radius`). On `body_entered`, Skater emits `body_block_hit`; `SkaterController._on_body_block_hit` (server only) calls `puck.on_body_block(blocker)`. Only fires on loose pucks (`carrier == null`). Reflects puck off body-center contact normal, multiplies speed by `body_block_dampen`, sets brief pickup cooldown on the blocker.
- **Per-skater cooldowns:** `_cooldown_timers: Dictionary` (Skater → float). Cooldown only applies to loose-puck pickups/deflects, not to poke checks. Lets two players race a loose puck — only the ex-carrier has a disadvantage.

### Why Not Predict Pickup?

Pickup is detected server-side via physics collision. Two players can contest the same puck — the server arbitrates who wins. Predicting pickup locally and rolling it back on a contested play would feel worse than the single round-trip delay. Pickup prediction is explicitly out of scope.

---

## Input Architecture

All input flows through an `InputState` data object populated by `LocalInputGatherer`. The abstraction supports swapping to network input or AI input without touching game logic.

`LocalInputGatherer` accumulates `just_pressed` events between physics ticks so no inputs are dropped. Mouse world position is computed via ray-plane intersection at y=0.

`InputState` fields: `sequence`, `delta`, `move_vector`, `mouse_world_pos`, `shoot_pressed`, `shoot_held`, `slap_pressed`, `slap_held`, `facing_held`, `brake`, `elevation_up`, `elevation_down`, `block_held`.

---

## Skater State Machine

| State | Blade | Movement | Facing |
|-------|-------|----------|--------|
| `SKATING_WITHOUT_PUCK` | Follows mouse | Full | Follows movement |
| `SKATING_WITH_PUCK` | Follows mouse | Full | Follows movement |
| `WRISTER_AIM` | Follows mouse | Full | Locked |
| `SLAPPER_CHARGE_WITH_PUCK` | Fixed forehand | Glide only | Locked (upper body aims) |
| `SLAPPER_CHARGE_WITHOUT_PUCK` | Fixed forehand | Full | Continuous toward mouse |
| `FOLLOW_THROUGH` | Stored relative angle | Full | Follows movement |
| `SHOT_BLOCKING` | Faces puck | Slowed | Continuous toward puck |

---

## Blade Control

Blade placement goes through a custom top-hand inverse-kinematics solver (`TopHandIK.solve` in `domain/rules/top_hand_ik.gd`). The stick is a rigid rod of fixed length (`stick_length`, baseline 1.30 m). The `shoulder` marker anchors the top hand on the opposite side of the body from the blade (right shoulder for a left-handed shooter). The `top_hand` marker is the moving IK output.

**Blade-first feel:** The mouse world position is the desired blade target. The solver works backwards from the target: place the hand where it needs to be so the stick reaches, clamp the hand to an asymmetric ROM, then recompute the blade from the clamped hand along the aim line at `stick_horiz`. Whenever the target is reachable, blade lands exactly on it. When not, blade clips along the same aim line — angular aim is preserved, only distance drops.

**Asymmetric top-hand ROM (relative to shoulder):**
- Forehand (cross-body) side: tight — `rom_forehand_reach_max ≈ 0.45 m`, `rom_forehand_angle_max ≈ 90°`. Hand stays near the body.
- Backhand (same-side as shoulder) side: open — `rom_backhand_reach_max ≈ 0.70 m` (≈ full arm length), `rom_backhand_angle_max ≈ 120°`. Supports one-handed backhand reaches.

**Vertical:** Blade Y stays locked at `blade_height`. Hand Y adapts: in the FAR regime (target past rest stick reach) it sits at `hand_rest_y`; in the CLOSE regime (target inside rest stick reach) it rises so `stick_horiz` matches the target distance and the blade lands on the target exactly. Capped by `hand_y_max` — past that the stick's min horizontal projection causes the blade to overshoot along the aim line.

**Arm rendering:** The shoulder and hand drive a 2-bone IK (`TwoBoneIK.solve_elbow`) that places the elbow on the plane perpendicular to the shoulder-hand axis in the pole direction (`arm_pole_local`). Two BoxMesh segments (`UpperArmMesh` / `ForearmMesh`) are scaled per-tick to the bone lengths and `look_at` their endpoints, following the same pattern as `StickMesh`. Arm meshes are auto-created if absent from the scene and included in ghost-mode transparency.

**Bottom hand (reactive):** A second hand grips the shaft a short way below the top hand. It is purely reactive — it never influences blade placement. After each top-hand solve, the controller computes the grip target as `top_hand.lerp(blade, bottom_hand_grip_fraction)` (default 0.25, ≈0.33 m down a 1.30 m shaft) and runs `BottomHandIK.solve` against an anchor at the `bottom_shoulder` marker (blade side of the body). The solver places the hand on the grip target unless the blade has swung into extreme backhand. Release is angle-based: the controller measures the blade's world direction in the skater's body frame, normalizes it so positive = backhand, and drives a smoothstep from `bh_release_angle_deg` (67°, matching the upper-body rotation clamp) to `+bh_release_angle_band_deg` (15°) — so the hand stays on the stick throughout any swing the upper body can track, and only blends to a shoulder rest pose when the blade genuinely passes the body's rotation limit. Rendered via the same `TwoBoneIK.solve_elbow` path with a mirrored pole. No network state is added — clients recompute the bottom hand locally from the interpolated top-hand + blade positions.

**Wall-clamp hand retraction:** When `clamp_blade_to_walls` pulls the blade back (boards in the way), the controller applies the same horizontal offset to `top_hand` so the stick keeps its rigid length. The arm re-solves on the retracted hand, so the stick looks like it's being pulled back rather than compressing. Wall-pin puck auto-release fires on squeeze magnitude, independent of the retraction.

**Facing drag:** Aiming past the angular ROM rotates the body's facing (`facing_drag_speed`) to bring the target back in range.

**Upper body twist:** Rotates independently to express the angle between facing and blade direction (`upper_body_twist_ratio = 0.8`).

**Wall clamping:** The solved blade is shortened by `RayCast3D` before being written. If squeeze exceeds `wall_squeeze_threshold`, the puck releases along the wall normal.

**Network:** Both `blade_position` and `top_hand_position` are broadcast per world-state tick and interpolated on clients so remote players show a consistent stick pose.

---

## Shooting

**Puck carry speed penalty:** While carrying the puck, `effective_max_speed = max_speed * puck_carry_speed_multiplier` (default 0.85). The speed cap only applies to the cap check, not to thrust — so the skater still accelerates normally but is capped lower, preserving feel while making skating with the puck meaningfully slower than without it.

**Pulse dash:** Hold Space + direction to fire a quick velocity impulse (crossover step push-off) instead of braking. Without direction, Space still brakes normally. The impulse is additive and capped at `effective_max` — at full speed a same-direction dash has no effect (no free acceleration), and an opposite-direction dash barely changes direction (it's a micro-adjustment, not a reversal tool). Cooldown 1.0s. VFX: ice spray in the anti-dash direction. Blocked during slapper charge and block stance. `_dash_cooldown_timer` is controller-local (consistent with other timers); any divergence between client and server is corrected by the 20Hz reconcile.

**Quick shot:** Tap left click. Fires blade-direction at `quick_shot_power`. Low skill floor.

**Wrister:** Hold left click, sweep blade to charge (distance-based), release to fire. Direction variance check resets charge if blade changes direction > 55° — prevents charge farming.

**Slapshot (with puck):** Hold right click. Blade fixes forehand, skater glides, upper body aims within `slapper_aim_arc`. Time-based charge.

**One-timer:** Hold right click without puck. Full movement available. Puck arriving while charging auto-transitions to slapshot state with charge carried over.

**Elevation:** Scroll to toggle. Persists until changed.

---

## Physics

- **Engine:** Godot 4.6.2 with Jolt Physics
- 240 Hz physics tick (prevents tunneling at high puck speeds)
- CCD enabled on puck
- Puck mass 0.17 kg, radius 0.1 m
- `GameRules.ICE_FRICTION = 0.01` — used in puck trajectory prediction. The rink ice surface is a child `StaticBody3D` with `physics_material_override` set directly, so friction applies correctly.
- Puck velocity is clamped in `_integrate_forces()` (runs on all peers) so CCD always receives a sane speed. The `_physics_process()` cap is kept as a secondary check.

---

## Camera

One camera per player. Weighted anchor:

| Anchor | Weight |
|--------|--------|
| Player | 1.0 (non-negotiable) |
| Puck | 1.0 |
| Mouse world pos | 0.5 |
| Attacking goal | 0.3 |

Player-first guarantee: weighted target is clamped so player never exceeds `player_margin` from frame edge. Zoom computed after position clamping to prevent fighting. Soft rink clamp applied last.

---

## Game Flow

### Phase FSM

`GamePhase` is host-driven. Clients receive phase via reliable RPC on goal events and as a correction channel in every world state broadcast.

| Phase | Duration | Description |
|-------|----------|-------------|
| `PLAYING` | Until goal or clock expires | Normal gameplay; period clock counts down |
| `GOAL_SCORED` | 2s (`GOAL_PAUSE_DURATION`) | Dead puck, celebration freeze |
| `FACEOFF_PREP` | 0.5s (`FACEOFF_PREP_DURATION`) | Players teleport to dots, puck resets, goalies reset to crease |
| `FACEOFF` | Until pickup or 10s timeout | Puck live at center dot, waiting for a player to pick it up |
| `END_OF_PERIOD` | 3s (`END_OF_PERIOD_PAUSE`) | Period clock hit zero; brief pause before next-period faceoff prep |
| `GAME_OVER` | Indefinite | All periods exhausted; movement locked until host resets |

Period clock (`GameRules.PERIOD_DURATION = 240s`, `NUM_PERIODS = 3`) ticks down only during `PLAYING`. When it expires: if periods remain → `END_OF_PERIOD` → `FACEOFF_PREP` (period increments, clock resets); if last period → `GAME_OVER`. `END_OF_PERIOD` and `GAME_OVER` are dead-puck phases.

### Dead-Puck Enforcement

The `GameStateMachine` exposes `is_movement_locked()` — true during `GOAL_SCORED`, `FACEOFF_PREP`, `END_OF_PERIOD`, and `GAME_OVER`. `GameManager` re-exposes this as an instance method and is passed into each controller at `setup()` as the `game_state` dependency. Controllers call `_game_state.is_movement_locked()` every frame:
- `LocalController._physics_process`: zeros velocity, drains `_input_history`, skips input gathering and processing
- `RemoteController._drive_from_input`: still advances `last_processed_sequence` (keeps reconcile bookkeeping current) but zeros velocity and skips `_process_input`
- `LocalController.reconcile`: returns early during locked phases — `on_faceoff_positions` (reliable RPC) is the authoritative source of faceoff positions

### Controller API

`GameManager` describes *what* it wants; controllers implement *how*:
- `controller.teleport_to(pos)` — sets position, zeros velocity. `LocalController` override also clears `_input_history`.
- `controller.on_puck_released_network()` — idempotent; safe to call without checking `has_puck` first.

---

## Build Status

| Stage | Description | Status |
|-------|-------------|--------|
| 1 | Skating feel | Done |
| 2 | Stick / puck interaction | Done |
| 3 | Basic goalie | Done |
| 4 | Networking (prediction, interpolation, reconciliation) | Done |
| 5 | Goalie AI rework + networking | Done |
| 6 | Full game flow (goals, faceoffs, score) | Done |
| 7 | Testable domain layer (rules extraction, state machine, GUT tests, CI) | Done |
| 8 | Period-based game loop (clock, period transitions, game over) | Done |
| 9 | Visual polish (puck trail, ice spray, skate trails, goal burst, wall impact, body check, shot charge glow, speed lines) | Done |
| 10 | Playtester distribution (auto-versioned GitHub Releases + in-game update notifier) | Done |
| 11 | In-game team/position swap | Done |
| 12 | Pre-game lobby (slot picking + rule config) + in-game "Return to Lobby" | Done |
| 13 | Characters + abilities | Deferred — revisit when game feel is right |
| 14 | Networking refactor Phase 1 (bug fixes + reconcile smoothing) | Done |
| 15 | Networking refactor Phase 2 (telemetry pull model, puck buffer fix) | Done |
| 16 | Networking refactor Phase 3 (simulated lag — NetworkSim autoload, presets 0–5) | Done |
| 17 | Networking refactor Phase 4 (host clock sync — NTP-style RTT, input host_timestamp) | Done |
| 18 | Networking refactor Phase 5 (StateBufferManager host-side ring buffers; goalie keyed by team_id) | Done |
| 19 | Networking refactor Phase 6 (swept sphere interaction detection; puck pickup/poke/deflect moved to domain layer) | Done |
| 20 | Networking refactor Phase 7 (input redundancy, lag-compensated pickup claims, state-machine save/restore in reconcile, blade telemetry, remove gradual correction) | Done |
| 21 | Netcode fixes (segment-segment pickup/poke detection, blade_contact_world lag-comp path, reconcile mouse-seed + server shot authority, physics-thread contest window, latest_rtt_ms for rewind, blade/hand extrapolation, input queue depth cap) | Done |
| 22 | Netcode improvements I6–I8 (PackedByteArray quantized world state ~60% bandwidth reduction; rewind-based body check hit crediting + body check impulse replay in reconcile; lag-compensated shot release using latest blade position + kinematic RTT/2 advance) | Done |
| 23 | Netcode improvements I2–I5 + puck reconcile fix (clock sync 2s interval + symmetric outlier drop; input queue target depth 5; velocity quantization @0.02m/s; wall reconcile dead zone 0.05m; puck reconcile full-RTT correction; world state as single flat PackedByteArray fixing 1940→279 byte MTU issue; ENet peer timeout null-guard) | Done |
| 24 | MTU fix for input batch (PackedByteArray 23B/input, 279B at 12 inputs vs 1780B; InputState.to_bytes/from_bytes); puck release pos from current blade not stale pin (fixes 1-frame lag in snapback) | Done |
| 25 | Netcode audit (40 Hz world state, 75ms interpolation, board collision in replay, goalie reliable RPCs, trajectory prediction exits on contact, pickup timestamp fix, adaptive delay, Hermite puck interpolation, goalie quantization 10→8B) | Done |
| 26 | Netcode improvements (2-frame client input delay; hard-snap-only puck trajectory reconcile; full body check velocity delta capture via `body_check_impulse_applied`; input queue drain on locked/blocked phases) | Done |
| 27 | Goalie reactive saves (glove, body, stick poke) | Planned |

---

## Open Questions

- Slapshot pre/post release buffer window for one-timer timing feel
- Middle-zone puck reception: blade readiness check
- Aim assist
- Procedural skating animations
- CharacterStats resource design (universal vs per-character exports)
- Camera goal anchor flip speed on turnovers
- Rink size tuning (possible 2/3 scale)
- Reconcile position blend (NETCODE_AUDIT_2026.md #3) — visual smoothing without physics compromise
- Session-relative timestamps for long-session f32 precision (netcode-improvements-plan.md #4)
