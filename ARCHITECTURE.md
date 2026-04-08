# Architecture

Technical design document for HockeyGame. See `CLAUDE.md` for conventions and project context.

---

## Design Philosophy

Depth over breadth — few inputs with rich emergent behavior rather than many explicit mechanics.

The Rocket League freeplay ceiling is a guiding star: the stickhandling-to-shot pipeline should reward practice and feel satisfying to master.

**Key inspirations:** Omega Strikers / Rocket League (structure), Breakpoint (twin-stick melee blade feel), Mario Superstar Baseball (stylized characters, exaggerated tuning, pre-match draft). Slapshot: Rebound is a cautionary reference — pure physics shooting feels unintuitive; the blade proximity pickup system is explicitly designed to solve that accessibility gap.

---

## Scene Structure

- **Skater:** `CharacterBody3D` with UpperBody/LowerBody split (`Node3D`). Shoulder (`Marker3D`) under UpperBody, positioned by code based on handedness. Blade (`Marker3D`) and StickMesh under UpperBody. Reusable scene driven by controller.
- **Puck:** `RigidBody3D` with cylinder collision (radius 0.1m, height 0.05m). PickupZone (`Area3D`, `SphereShape3D` radius 0.5m) for blade proximity detection. Emits `puck_picked_up` and `puck_released` signals. Physics runs server-side only — frozen on clients.
- **Rink:** `StaticBody3D` with procedurally generated walls, corners, and ice surface via `@tool` script. 60×26m, Z axis is the long axis.
- **Goals:** `StaticBody3D` with procedurally generated posts, crossbar, and back wall via `@tool` script.
- **Goalie:** `Node3D` root (`goalie.gd`) with six `StaticBody3D` body parts (LeftPad, RightPad, Body, Glove, Blocker, Stick). A sibling `GoalieController` node drives positioning. Body part positions and rotations lerp between per-state configs each frame.
- **Camera:** `Camera3D` per player. Weighted anchor system — player, puck, mouse, attacking goal. Zoom computed after position clamping.

---

## Collision Layers

| Layer | Purpose |
|-------|---------|
| 1 | General physics (boards, goals, goalies, skaters) |
| 2 | Blades |
| 3 | Puck pickup zone |
| 4 | Ice surface |

The puck has no collision layer (mask = 1). It bounces off everything on layer 1 but doesn't push skaters.

---

## Networking

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
- On world state receipt: filters confirmed inputs by `last_processed_sequence`, checks position/velocity error against threshold, resets to server state and replays unconfirmed inputs if correction is needed

**RemoteController** (other players):
- On the host: drives simulation from latest received input at 240 Hz
- On clients: buffers incoming `SkaterNetworkState` snapshots with timestamps, interpolates with a 100ms delay

### Puck Networking

**PuckController** manages three client-side modes:

1. **Local carrier** — when `_carrier_peer_id` matches local peer ID, the puck is pinned to the local blade position each frame. Zero lag, prediction only, no interpolation.
2. **Trajectory prediction** — immediately after local release, integrate puck position using release direction/power and `Constants.ICE_FRICTION`. Reconcile against server state when it arrives: snap to server if error exceeds `prediction_reconcile_threshold`, otherwise transition smoothly to interpolation once the buffer has enough snapshots.
3. **Interpolation** — buffer server snapshots and interpolate with the same 100ms delay as skaters.

**Carrier transitions:**
- Pickup: server detects via physics signal → reliable RPC to the specific client who picked up the puck → `on_puck_picked_up_network()` on their LocalController
- Release: client predicts immediately (state machine transitions, trajectory prediction begins) → reliable RPC to server to execute physics

`_carrier_peer_id` on clients is managed exclusively by `notify_local_pickup()` / `notify_local_release()` in `PuckController`. It is intentionally never updated from world state — unreliable packet ordering would cause it to conflict with locally-predicted transitions.

### Goalie Networking

**GoalieController** AI runs on the host only. Clients receive goalie state via the world state broadcast and interpolate with a 100ms delay using a `BufferedGoalieState` buffer — the same pattern as remote skaters.

Serialized per goalie: position (x/z), rotation_y, state enum, five_hole_openness (5 elements). Clients reconstruct body part configs locally from the state enum and five_hole_openness, then snap body parts to the interpolated config each frame.

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
- `Constants.ICE_FRICTION = 0.01` — used in puck trajectory prediction, intended for rink physics material (not yet wired up correctly, see Known Issues)

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

- No stoppages except goals and faceoffs
- Soft offsides: speed decays past blue line without puck
- Soft icing: iced puck placed behind net, defensive team only
- No formal penalty system — mechanical deterrents preferred

---

## Known Issues

**Ice friction not applied:** `hockey_rink.gd` calls `col.set_meta("physics_material_override", phys_mat)` on a `CollisionShape3D`, which stores it as metadata rather than applying a physics material. The ice surface needs its own child `StaticBody3D` with `physics_material_override` set to a `PhysicsMaterial` using `Constants.ICE_FRICTION`.

---

## Build Status

| Stage | Description | Status |
|-------|-------------|--------|
| 1 | Skating feel | Done |
| 2 | Stick / puck interaction | Done |
| 3 | Basic goalie | Done |
| 4 | Networking (prediction, interpolation, reconciliation) | Done |
| 5 | Goalie AI rework + networking | Done |
| 6 | Characters + abilities | Next |
| 7 | Full game flow (goals, faceoffs, score) | Planned |

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
