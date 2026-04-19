# Architecture

Technical design document for HockeyGame. See `CLAUDE.md` for conventions and project context.

---

## Design Philosophy

Depth over breadth — few inputs with rich emergent behavior rather than many explicit mechanics.

The Rocket League freeplay ceiling is a guiding star: the stickhandling-to-shot pipeline should reward practice and feel satisfying to master.

**Key inspirations:** Omega Strikers / Rocket League (structure), Breakpoint (twin-stick melee blade feel), Mario Superstar Baseball (stylized characters, exaggerated tuning, pre-match draft). Slapshot: Rebound is a cautionary reference — pure physics shooting feels unintuitive; the blade proximity pickup system is explicitly designed to solve that accessibility gap.

---

## Layers

The codebase is organized into three layers with downward dependency flow.

**Domain** (`Scripts/domain/`) — pure GDScript, zero engine references. Comprises:
- Rule classes as `class_name` files with static methods (`PhaseRules`, `PlayerRules`, `InfractionRules`, `PuckCollisionRules`, `SkaterMovementRules`, `ShotMechanics`, `GoalieBehaviorRules`, `ChargeTracking`, `ReconciliationRules`)
- `GameStateMachine` — a `RefCounted` owning phase/timer, scores, period number, period clock (`time_remaining`), player slot registry, icing state, ghost computation. Lives on both host and client; the host drives it via `tick()`, clients sync via `apply_remote_state()`.
- `GameRules` const class for timings/geometry/thresholds
- `GamePhase` enum

All of this is unit-tested with GUT. ~130 tests under `tests/unit/rules/` and `tests/unit/state/`.

**Application** — `GameManager` (autoload), controllers, `ActorSpawner`, plus five focused collaborators that `GameManager` wires together at world-spawn time:

- `PlayerRegistry` — owns the runtime `players` dict; spawns/despawns via `ActorSpawner`; resolves skater ↔ peer_id ↔ team.
- `WorldStateCodec` — encodes/decodes the flat RPC wire format for world state and stats. Keeps serialization in one place.
- `ShotOnGoalTracker` — host-only pending-shot state machine. Confirms SOG on goalie-touch or goal; credits up to two same-team assists from the recent-carrier list.
- `PhaseCoordinator` — phase-entry side effects (puck lock/unlock, goalie reset, faceoff teleport) and the goal scoring pipeline.
- `SlotSwapCoordinator` — validates mid-game slot swaps and packages confirmation payloads.

`GameManager` stays as the thin orchestrator: owns the `GameStateMachine`, runs `_process` / `_physics_process`, and re-emits the collaborators' signals to HUD/Camera/Scoreboard so the external API is unchanged. Controllers receive a `game_state: Node` (GameManager itself, duck-typed) via `setup()` rather than reaching for `GameManager.*` statically. The collaborators themselves are plain `RefCounted` classes with dependencies injected through `setup()` — nothing reaches the `NetworkManager` autoload directly; instead `GameManager` wires signals onto `NetworkManager` send methods, so the collaborators stay independently testable.

**Infrastructure** — actor nodes (Skater, Puck, Goalie), `NetworkManager`, UI. Engine integration. Lower layers never reach up:
- `Puck` accepts a `team_resolver: Callable` via `set_team_resolver()` — used by the poke-check eligibility gate without referencing `GameManager`.
- `PuckController` accepts a `peer_id_resolver: Callable` and emits `puck_picked_up_by(peer_id)` / `puck_released_by_carrier(peer_id)` / `puck_stripped_from(peer_id)` signals that `GameManager` listens to for player-registry lookups and RPC sends.
- Controllers take a `game_state: Node` with `is_host() -> bool` and `is_movement_locked() -> bool`.

Adding a new rule: put pure math in a `domain/rules/` file, write a GUT test for it, call it from the controller/GameManager.

---

## Scene Structure

- **Skater:** `CharacterBody3D` with UpperBody/LowerBody split (`Node3D`). Shoulder (`Marker3D`) under UpperBody, positioned by code based on handedness. Blade (`Marker3D`) and StickMesh under UpperBody. `set_blade_position` rotates the Blade node to face along the shaft (horizontal projection of shoulder→blade), so the BladeArea and mesh always track stick angle. `blade_world_velocity` and `is_elevated` are tracked each physics tick for server-side puck interaction queries. Collision layers set in `_ready()`: body on `LAYER_SKATER_BODIES` (16), mask `MASK_SKATER` (17), stick raycast mask `MASK_SKATER` so the blade is blocked by boards, goalie pads, and other skater bodies. A `BodyBlockArea` (sphere, `collision_mask = LAYER_PUCK`) is added as a child and wired to the `body_block_hit` signal. A flat procedural ring mesh (gray, 50% alpha) is created in `_ready()` and pinned to global Y=0.05 each physics tick; only shown on the local player via `set_player_color(..., is_local=true)`.
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

All paths go through `MainMenu.tscn`. `NetworkManager._ready()` is a no-op. The menu calls `start_offline()`, `start_host()`, or `start_client(ip)` — these configure ENet and set `is_host` but do not spawn the world. World spawn is deferred: `Hockey.tscn`'s root runs `game_scene.gd`, whose `_ready()` calls `NetworkManager.on_game_scene_ready()` which emits `host_ready` (hosts only); `GameManager` has connected that signal to `on_host_started` in `_ready()` and handles the spawn. Clients spawn via the `client_connected` signal emitted from `_on_connected_to_server()`.

Graceful shutdown: `_exit_tree` closes the ENet peer. Server disconnect on client side also triggers close.

### Model

Authoritative host. The host runs all physics. Clients predict locally and reconcile against server state. No dedicated server — one player hosts.

### Rates

| Channel | Rate | Transport |
|---------|------|-----------|
| Input (client → host) | 60 Hz | Unreliable |
| World state (host → clients) | 20 Hz | Unreliable |
| Events (pickup, spawn, sync) | On event | Reliable |
| Stats sync (host → clients) | On change | Reliable |

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
- Goal scored: server captures carrier peer_id before `puck.drop()` → sends `notify_goal` (reliable, all peers) and `notify_puck_dropped` (reliable, carrier only) as separate RPCs → carrier client clears state in `on_carrier_puck_dropped()`; other clients are unaffected. Decoupled so `notify_goal` isn't responsible for carrier cleanup.

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

### Teams and Goals

Two `Team` objects created at startup. Each owns a `defended_goal` (`HockeyGoal` instance), a `goalie_controller`, and a `score`. Two `HockeyGoal` instances in the scene (`facing=+1` and `facing=-1`). Each has a shallow `Area3D` goal sensor at its mouth; the host connects `goal_scored` signals in `_connect_goal_signals()`.

### Player Colors

Each player's UI badge uses `PlayerRules.generate_primary_color(team_id)`; skater meshes are painted via `generate_jersey_color` / `generate_helmet_color` / `generate_pants_color`. Colors are fixed per team — all teammates match:

- **Team 0 (home):** primary = Pittsburgh Penguins Vegas Gold (#FFB81C); secondary = Penguins Black.
- **Team 1 (away):** primary = Toronto Maple Leafs Blue (#003E7E); secondary = Leafs White.

Both colors are sent to joining clients via the `assign_player_slot` and `spawn_remote_skater` RPCs, and embedded in the `sync_existing_players` array. Stored in `PlayerRecord.color` (primary) and `PlayerRecord.secondary_color`; applied via `skater.set_player_color(primary, secondary)` which sets a `material_override` on every mesh (jersey, blade, arms, legs, helmet, stick shaft). Explicit overrides on all meshes prevent the ghost-mode gray-override bug — `_apply_ghost_visual` never needs to create a new material, just modifies existing alpha.

### Host Reset

`GameManager.reset_game()` (host-only): calls `_state_machine.reset_all()` which zeroes both scores, resets `current_period` to 1, and restores `time_remaining` to `PERIOD_DURATION`. Emits `score_changed`, `period_changed`, and `clock_updated` on the host, sends a `notify_game_reset` reliable RPC to all clients (they call `reset_all()` and emit the same signals), then calls `_begin_faceoff_prep()` which handles puck/player/goalie reset and sends faceoff positions via the existing `notify_faceoff_positions` RPC. The HUD builds a "Reset" button in the top-right corner only when `NetworkManager.is_host`.

### Ghost Mechanic (Offsides + Icing)

Instead of stoppages, offsides and icing are enforced via a **ghost mode** — offending players become semi-transparent and lose all puck/player interaction (collision layers zeroed) while retaining full movement. This keeps play flowing without dead time.

**Offsides:** checked every physics tick on the host via `InfractionRules.is_offside(skater_z, team_id, puck_z, is_carrier)`. A skater is offside if they are in their team's offensive zone (past the attacking blue line at ±7.62m) while the puck has not yet entered that zone. The puck carrier can never be offside. Ghost clears the instant the skater retreats behind the blue line or the puck enters the zone. Blue line constant: `GameRules.BLUE_LINE_Z = 7.62`. Team 0 attacks toward -Z (offensive zone: z < -7.62); team 1 attacks toward +Z (offensive zone: z > 7.62).

**Icing:** `GameStateMachine` tracks the last carrier's team and Z position each tick. When the puck is free and crosses the opponent's goal line (|z| > `GameRules.GOAL_LINE_Z`), and the last carrier released from their own half (own side of center ice), icing triggers via `InfractionRules.check_icing`. The entire offending team is ghosted for `GameRules.ICING_GHOST_DURATION` (3s) or until the non-offending team picks up the puck. Icing state resets on faceoff prep.

**Network sync:** `is_ghost` is serialized in `SkaterNetworkState` (index 7). Host computes authoritatively: `GameStateMachine.compute_ghost_state(positions, carrier_peer_id, puck_position)` returns per-peer ghost flags, applied by `GameManager._apply_ghost_state()`. Clients predict offsides locally in `LocalController._predict_offside()` for instant feedback; icing ghost arrives via the 20Hz world state broadcast. `RemoteController._apply_state_to_skater()` applies ghost visual/collision from network state.

**Ghost implementation on `Skater`:** `set_ghost(bool)` toggles collision layers (blade area, body block area, skater body) and material transparency (alpha 0.3). Collision layer changes prevent all physics interaction — `move_and_slide` won't generate collisions with ghosts, blade areas won't trigger puck pickup, body block areas won't detect pucks. Safety guards in `Puck._on_blade_entered`, `on_body_block`, and `on_body_check` provide defense-in-depth against frame-ordering edge cases.

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

## Distribution

Playtester builds ship through GitHub Releases (`latest` tag, Windows + Linux zips). `deploy.yml` bakes `VERSION=0.1.<commit count>` into `Scripts/game/build_info.gd` before each export and publishes it as the release name. On startup, the main menu's `UpdateChecker` (`Scripts/ui/update_checker.gd`) fetches the release metadata via the GitHub API and shows an "update available" label when the running build is stale. No in-game downloading — players re-download the zip manually. Editor runs carry `VERSION == "dev"` and skip the network check. When the game moves to Steam, SteamPipe (binary-delta patching) takes over and this plumbing comes out.

---

## Open Questions

- Slapshot pre/post release buffer window for one-timer timing feel
- Middle-zone puck reception: blade readiness check
- Aim assist
- Phase 2 IK: full arm/body rigging (variable hand Y and bottom-hand solving are now live — see Blade Control)
- Procedural skating animations
- CharacterStats resource design (universal vs per-character exports)
- Camera goal anchor flip speed on turnovers
- Rink size tuning (possible 2/3 scale)
