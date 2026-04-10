# Architecture

Technical design document for HockeyGame. See `CLAUDE.md` for conventions and project context.

---

## Design Philosophy

Depth over breadth — few inputs with rich emergent behavior rather than many explicit mechanics.

The Rocket League freeplay ceiling is a guiding star: the stickhandling-to-shot pipeline should reward practice and feel satisfying to master.

**Key inspirations:** Omega Strikers / Rocket League (structure), Breakpoint (twin-stick melee blade feel), Mario Superstar Baseball (stylized characters, exaggerated tuning, pre-match draft). Slapshot: Rebound is a cautionary reference — pure physics shooting feels unintuitive; the blade proximity pickup system is explicitly designed to solve that accessibility gap.

---

## Scene Structure

- **Skater:** `CharacterBody3D` with UpperBody/LowerBody split (`Node3D`). Shoulder (`Marker3D`) under UpperBody, positioned by code based on handedness. Blade (`Marker3D`) and StickMesh under UpperBody. `set_blade_position` rotates the Blade node to face along the shaft (horizontal projection of shoulder→blade), so the BladeArea and mesh always track stick angle. `blade_world_velocity` and `is_elevated` are tracked each physics tick for server-side puck interaction queries. Collision layers set in `_ready()`: body on `LAYER_SKATER_BODIES` (16), mask `MASK_SKATER` (17), stick raycast mask `MASK_SKATER` so the blade is blocked by boards, goalie pads, and other skater bodies. A `BodyBlockArea` (sphere, `collision_mask = LAYER_PUCK`) is added as a child and wired to the `body_block_hit` signal.
- **Puck:** `RigidBody3D` with cylinder collision (radius 0.1m, height 0.05m). PickupZone (`Area3D`, `SphereShape3D` radius 0.5m) for blade proximity detection. Emits `puck_picked_up`, `puck_released`, and `puck_stripped` signals. Physics runs server-side only — frozen on clients. Per-skater cooldown timers (`_cooldown_timers: Dictionary`) replace the old global timer so two players can race a loose puck independently.
- **Rink:** `StaticBody3D` with procedurally generated walls, corners, and ice surface via `@tool` script. 60×26m, Z axis is the long axis.
- **Goals:** `StaticBody3D` with procedurally generated Art Ross net via `@tool` script. Two cubic Bézier curves (base at Y=0, top shelf at Y=1.22m) define the frame shape — the base flares wider than the posts, the top shelf curves inward. Frame tubes are box segments swept along the curves (base = white, top shelf + posts + crossbar = red). Netting is a ruled surface `ArrayMesh` connecting corresponding points on the two curves, with a `ConcavePolygonShape3D` for accurate puck collision. Posts and crossbar use `CylinderMesh` + `CylinderShape3D`. A solid `BoxShape3D` back wall sits at ~1.0m depth to cover seam gaps in the ConcavePolygonShape3D. The goal sensor `Area3D` validates entry direction — `puck.linear_velocity.dot(facing_z) > 0` — so only pucks entering from the rink side can score.
- **Goalie:** `Node3D` root (`goalie.gd`) with seven `StaticBody3D` body parts (LeftPad, RightPad, Body, Head, Glove, Blocker, Stick). A sibling `GoalieController` node drives positioning. Body part positions and rotations lerp between per-state configs (`GoalieBodyConfig`) each frame. Part sizes: pads 0.28×0.84×0.15, body 0.40×0.60×0.25, head 0.22×0.22×0.20, glove 0.25×0.25×0.15, blocker 0.20×0.30×0.10, stick 0.50×0.04×0.04. The Stick is disabled by default (`@export stick_enabled: bool = false`); `_ready()` zeroes its collision layer and hides it. In RVH the goalie root positions so the post pad outer edge is flush with the post (`net_half_width - 0.88`); left/right state selection uses goalie-local X (`direction_sign`) so both goalies behave correctly despite opposite world rotations.
- **Camera:** `Camera3D` per player. Weighted anchor system — player, puck, mouse, attacking goal. Zoom computed after position clamping.

---

## Collision Layers

All layer/mask values are defined as named constants in `constants.gd`.

| Constant | Value | Purpose |
|----------|-------|---------|
| `LAYER_WALLS` | 1 | Boards, ice surface, goalie body parts |
| `LAYER_BLADE_AREAS` | 2 | Skater blade `Area3D`s |
| `LAYER_PUCK` | 8 | Puck `RigidBody3D` — goal sensor `Area3D`s use `collision_mask = 8` to detect it |
| `LAYER_SKATER_BODIES` | 16 | Skater `CharacterBody3D` bodies |

Composed masks:

| Constant | Value | Used by |
|----------|-------|---------|
| `MASK_PUCK` | 1 | Puck bounces off walls + goalie bodies only — not skater bodies |
| `MASK_SKATER` | 17 | Skaters blocked by walls (1) + other skater bodies (16) |

The puck's pickup zone `Area3D` sits on `LAYER_WALLS \| LAYER_BLADE_AREAS` (3) with `collision_mask = LAYER_BLADE_AREAS` (2) so it detects blade `Area3D`s via `area_entered`.

---

## Networking

### Launch Modes

All paths go through `MainMenu.tscn`. `NetworkManager._ready()` is a no-op. The menu calls `start_offline()`, `start_host()`, or `start_client(ip)` — these configure ENet and set `is_host` but do not spawn the world. World spawn is deferred: `Hockey.tscn`'s root runs `game_scene.gd`, whose `_ready()` calls `NetworkManager.on_game_scene_ready()` → `GameManager.on_host_started()`. Clients spawn via `_on_connected_to_server()` as before.

Graceful shutdown: `_exit_tree` closes the ENet peer. Server disconnect on client side also triggers close.

### Model

Authoritative host. The host runs all physics. Clients predict locally and reconcile against server state. No dedicated server — one player hosts.

### Rates

| Channel | Rate | Transport |
|---------|------|-----------|
| Input (client → host) | 60 Hz | Unreliable |
| World state (host → clients) | 20 Hz | Unreliable |
| Events (pickup, spawn, sync) | On event | Reliable |

### Skater Networking

**LocalController** (local player on any machine):
- Runs full physics simulation locally every frame
- Stores input history (capped at 2 seconds)
- On world state receipt: filters confirmed inputs by `last_processed_sequence`, checks position/velocity error against threshold, resets to server state and replays unconfirmed inputs if correction is needed. Reset includes `position`, `velocity`, `facing`, `_facing` (controller copy), `_upper_body_angle`, and `skater.upper_body_rotation` — all must match server state before replay or blade position drifts during the replay.

**RemoteController** (other players):
- On the host: drives simulation from latest received input at 240 Hz
- On clients: buffers incoming `SkaterNetworkState` snapshots with timestamps, interpolates with a 100ms delay

### Puck Networking

**PuckController** manages three client-side modes:

1. **Local carrier** — when `_carrier_peer_id` matches local peer ID, the puck is pinned to the local blade position each frame. Zero lag, prediction only, no interpolation.
2. **Trajectory prediction** — after local release, the puck is unfrozen (`freeze = false`) and Jolt runs client-side physics, matching the server's simulation for static geometry (boards, goals). Each 20Hz server broadcast calls `_reconcile`: soft-corrects velocity toward server state via `velocity_correction_blend`; nudges position toward server only when `current_vel.dot(server_vel) > 0` (avoids fighting Jolt during bounces where velocities briefly oppose); hard-snaps both on extreme divergence (`prediction_reconcile_threshold`). Exits prediction when world state `carrier_peer_id != -1`, then refreezes and returns to interpolation.
3. **Interpolation** — buffer server snapshots and interpolate with the same 100ms delay as skaters. Position only — velocity is not applied to the frozen body (`_apply_state_to_puck` is position-only).

**Carrier transitions:**
- Pickup: server detects via physics signal → reliable RPC to the specific client who picked up the puck → `on_puck_picked_up_network()` on their LocalController
- Release: client predicts immediately (state machine transitions, trajectory prediction begins) → reliable RPC to server to execute physics
- Poke check (strip): server detects opposing blade contact while `carrier != null` → clears carrier, launches puck via `_poke_check()` → `puck_stripped` signal → reliable RPC to victim client (`notify_puck_stolen`) → victim calls `on_puck_released_network()` + `notify_local_puck_dropped()` to clear carry state and drop back to interpolation

`_carrier_peer_id` on clients is managed exclusively by `notify_local_pickup()` / `notify_local_release()` in `PuckController`. It is intentionally never updated from world state — unreliable packet ordering would cause it to conflict with locally-predicted transitions.

### Goalie Networking

**GoalieController** AI runs on the host only. Clients receive goalie state via the world state broadcast and interpolate with a 100ms delay using a `BufferedGoalieState` buffer — the same pattern as remote skaters.

Serialized per goalie: position (x/z), rotation_y, state enum, five_hole_openness (5 elements). Clients reconstruct body part configs locally from the state enum and five_hole_openness, then snap body parts to the interpolated config each frame.

RVH triggers when `_is_puck_in_defensive_zone()` — either the puck is behind the goal line, or it is within `zone_post_z` of the goal line and the horizontal angle to the puck exceeds `rvh_early_angle` (default 60°). This matches the Buckley depth chart's "Defensive" corner zones, which extend slightly in front of the goal line at sharp angles.

**Tracking lag:** `GoalieController` maintains `_tracked_puck_position` that lerps toward the real puck at `tracking_speed` (default 6.0) each frame. All positioning logic — lateral target, depth, facing, and state transitions — reads from this tracked position rather than the real puck. `_on_puck_released` (shot detection) reads the real puck position and velocity so butterfly reactions stay accurate. `tracking_speed` is the master difficulty export: lower = more positional lag.

### Puck Interactions (server-side)

All puck contact logic runs on the host via `Area3D.area_entered` on the PickupZone:

- **Catch vs deflect:** relative velocity `(puck_vel - blade_world_vel).length()` against `deflect_min_speed`. Moving your blade backward with the puck reduces relative velocity → catch. Stationary blade hit by fast puck → deflect. Below `pickup_max_speed` always catches.
- **Deflect direction:** contact normal = `(puck_pos - blade_world_pos).normalized()` (billiard ball style). Physical reflection blended toward incoming direction via `deflect_blend`. If `skater.is_elevated`, outgoing direction is tilted upward by `deflect_elevation_angle`.
- **Poke check:** when any blade enters PickupZone while `carrier != null`, `_poke_check` strips the puck (no team gate — teammates can strip each other). Strip direction = `checker_blade_vel + carrier_blade_vel * poke_carrier_vel_blend` (or spatial direction as fallback). Ex-carrier gets `reattach_cooldown`; checker gets brief `poke_checker_cooldown`.
- **Body check strip:** `SkaterController._on_body_checked_player` (server only) calls `puck.on_body_check(checker, victim, force, direction)`. If `force = weight × approach_speed ≥ body_check_strip_threshold` and `victim == carrier`, `_body_check_strip` clears the carrier and launches the puck in the hit direction. Emits `puck_stripped` + `puck_released` — same notification path as poke check.
- **Passive body block:** each `Skater` has a `BodyBlockArea` (`Area3D`, `collision_layer = 0`, `collision_mask = LAYER_PUCK`, sphere radius `body_block_radius`). On `body_entered`, Skater emits `body_block_hit`; `SkaterController._on_body_block_hit` (server only) calls `puck.on_body_block(blocker)`. Only fires on loose pucks (`carrier == null`). Reflects puck off body-center contact normal, multiplies speed by `body_block_dampen`, sets brief pickup cooldown on the blocker.
- **Per-skater cooldowns:** `_cooldown_timers: Dictionary` (Skater → float). Cooldown only applies to loose-puck pickups/deflects, not to poke checks. Lets two players race a loose puck — only the ex-carrier has a disadvantage.

### Why Not Predict Pickup?

Pickup is detected server-side via physics collision. Two players can contest the same puck — the server arbitrates who wins. Predicting pickup locally and rolling it back on a contested play would feel worse than the single round-trip delay. Pickup prediction is explicitly out of scope.

---

## Input Architecture

All input flows through an `InputState` data object populated by `LocalInputGatherer`. The abstraction supports swapping to network input or AI input without touching game logic.

`LocalInputGatherer` accumulates `just_pressed` events between physics ticks so no inputs are dropped. Mouse world position is computed via ray-plane intersection at y=0.

`InputState` fields: `sequence`, `delta`, `move_vector`, `mouse_world_pos`, `shoot_pressed`, `shoot_held`, `slap_pressed`, `slap_held`, `facing_held`, `brake`, `elevation_up`, `elevation_down`.

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

---

## Blade Control

The blade originates from the stick-hand shoulder. Mouse distance maps to reach — further away = more extended. Clamped to a forehand/backhand arc in upper-body local space.

Pushing past the arc limit rotates the player's facing smoothly (`facing_drag_speed`), so extended mouse movement naturally rotates the whole body.

Upper body rotates independently to express the angle between facing and blade direction (`upper_body_twist_ratio = 0.5`).

Wall clamping: blade reach is shortened near boards. If squeeze exceeds `wall_squeeze_threshold`, the puck releases along the wall normal.

---

## Shooting

**Quick shot:** Tap left click. Fires blade-direction at `quick_shot_power`. Low skill floor.

**Wrister:** Hold left click, sweep blade to charge (distance-based), release to fire. Direction variance check resets charge if blade changes direction > 45° — prevents charge farming.

**Slapshot (with puck):** Hold right click. Blade fixes forehand, skater glides, upper body aims within `slapper_aim_arc`. Time-based charge.

**One-timer:** Hold right click without puck. Full movement available. Puck arriving while charging auto-transitions to slapshot state with charge carried over.

**Elevation:** Scroll to toggle. Persists until changed.

---

## Physics

- **Engine:** Godot 4.6.2 with Jolt Physics
- 240 Hz physics tick (prevents tunneling at high puck speeds)
- CCD enabled on puck
- Puck mass 0.17 kg, radius 0.1 m
- `Constants.ICE_FRICTION = 0.01` — used in puck trajectory prediction. The rink ice surface is a child `StaticBody3D` with `physics_material_override` set directly, so friction applies correctly.
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
| `PLAYING` | Until goal | Normal gameplay |
| `GOAL_SCORED` | 2s (`GOAL_PAUSE_DURATION`) | Dead puck, celebration freeze |
| `FACEOFF_PREP` | 0.5s (`FACEOFF_PREP_DURATION`) | Players teleport to dots, puck resets, goalies reset to crease |
| `FACEOFF` | Until pickup or 10s timeout | Puck live at center dot, waiting for a player to pick it up |

### Dead-Puck Enforcement

`GameManager.movement_locked()` returns `true` during `GOAL_SCORED` and `FACEOFF_PREP`. Both controllers check this every frame:
- `LocalController._physics_process`: zeros velocity, drains `_input_history`, skips input gathering and processing
- `RemoteController._drive_from_input`: still advances `_last_processed_sequence` (keeps reconcile bookkeeping current) but zeros velocity and skips `_process_input`
- `LocalController.reconcile`: returns early during locked phases — `on_faceoff_positions` (reliable RPC) is the authoritative source of faceoff positions

### Controller API

`GameManager` describes *what* it wants; controllers implement *how*:
- `controller.teleport_to(pos)` — sets position, zeros velocity. `LocalController` override also clears `_input_history`.
- `controller.on_puck_released_network()` — idempotent; safe to call without checking `has_puck` first.

### Teams and Goals

Two `Team` objects created at startup. Each owns a `defended_goal` (`HockeyGoal` instance), a `goalie_controller`, and a `score`. Two `HockeyGoal` instances in the scene (`facing=+1` and `facing=-1`). Each has a shallow `Area3D` goal sensor at its mouth; the host connects `goal_scored` signals in `_connect_goal_signals()`.

### Planned

- No stoppages except goals and faceoffs
- Soft offsides: speed decays past blue line without puck
- Soft icing: iced puck placed behind net, defensive team only
- No formal penalty system — mechanical deterrents preferred

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
| 7 | Characters + abilities | Next |

---

## Open Questions

- Slapshot pre/post release buffer window for one-timer timing feel
- Middle-zone puck reception: blade readiness check
- Aim assist
- IK for arm/stick animation
- Procedural skating animations
- CharacterStats resource design (universal vs per-character exports)
- Camera goal anchor flip speed on turnovers
- Rink size tuning (possible 2/3 scale)
