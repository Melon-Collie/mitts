# Goalie AI Implementation Spec

Design spec for the goalie AI rework (Stage 5). Produced in design mode — intended as a reference for Claude Code implementation.

> **Implementation notes** are marked with `> ℹ️` throughout where the actual implementation diverged from the original design.

---

## Overview

Replace the current basic goalie (`StaticBody3D` with angle tracking and fixed butterfly collision shapes) with a full behavioral AI. The new goalie uses a three-state state machine, repositions six collision-shape body parts per state, and tracks the puck using the Buckley positioning system for depth and angle-based lateral movement.

**Core philosophy:** The goalie always makes the correct decision. No randomness, no dice rolls. Players beat the goalie through speed — reaction delays, movement speed limits, and coverage gaps during transitions. Both teams should always feel that goals were earned, never that their goalie got unlucky.

---

## Scene Tree

```
Goalie (StaticBody3D)
│   goalie_controller.gd
│   Collision Layer: 1
│   Collision Mask: 0
│
├── LeftPad (Node3D)
│   ├── CollisionShape3D (BoxShape3D)
│   └── MeshInstance3D (BoxMesh)
│
├── RightPad (Node3D)
│   ├── CollisionShape3D (BoxShape3D)
│   └── MeshInstance3D (BoxMesh)
│
├── Body (Node3D)
│   ├── CollisionShape3D (BoxShape3D)
│   └── MeshInstance3D (BoxMesh)
│
├── Glove (Node3D)
│   ├── CollisionShape3D (BoxShape3D)
│   └── MeshInstance3D (BoxMesh)
│
├── Blocker (Node3D)
│   ├── CollisionShape3D (BoxShape3D)
│   └── MeshInstance3D (BoxMesh)
│
└── Stick (Node3D)
    ├── CollisionShape3D (BoxShape3D)
    └── MeshInstance3D (BoxMesh)
```

Each body part is a `Node3D` parent with a `CollisionShape3D` and `MeshInstance3D` child. The script moves and rotates the parent `Node3D`; collision and mesh follow automatically. Give each part a distinct debug color material so coverage is visually obvious during testing.

Collision layer 1 means the puck (mask = 1) bounces off all body parts. The goalie doesn't need to mask anything — it reads puck position from a node reference, not from collision detection.

> ℹ️ **Scene structure changed.** Godot requires `CollisionShape3D` to be a child of a `StaticBody3D`, not a plain `Node3D`. The actual structure is:
> - Root: `Node3D` (not `StaticBody3D`) — `goalie.gd` attached here, handles body API only
> - Body parts: `StaticBody3D` directly (not `Node3D` wrappers) — each has `CollisionShape3D` and `MeshInstance3D` as children
> - AI logic lives in `goalie_controller.gd` on a **separate sibling node**, spawned by `GameManager` — same split as `Puck`/`PuckController`

---

## State Machine

Three states: `STANDING`, `BUTTERFLY`, `RVH`.

> ℹ️ **RVH split into two states.** The implementation uses four states: `STANDING`, `BUTTERFLY`, `RVH_LEFT`, `RVH_RIGHT`. Splitting RVH by post makes transition logic and body configs cleaner than selecting a config within a single RVH state.

### STANDING (default)

The goalie's primary state. Full mobility. Two systems run simultaneously:

**Depth (Buckley ABCD):**
- Puck Z distance from goal line determines a target depth (how far out from the goal line the goalie positions).
- Four zones, smoothly lerped between (no snapping):
  - Aggressive: puck within ~8m of goal line → depth ~1.2m out
  - Base: puck within ~12m → depth ~0.6m out (skates at top of crease)
  - Conservative: puck within ~20m → depth ~0.3m out
  - Defensive: puck beyond ~20m → depth ~0.1m out (near post)
- These are Z-component distances only (not straight-line). A puck in the corner at the same Z as a puck in the slot produces the same depth.
- Depth lerps smoothly toward the target each frame. No C-cut simulation needed — depth movement doesn't create exploitable openings.
- All zone boundaries and depth values should be `@export` for tuning.

> ℹ️ **Added inner post zone.** When the puck is within `zone_post_z` (~2.0m) of the goal line, depth lerps back down from `depth_aggressive` toward `depth_defensive`. Without this, the goalie stays out at full challenge depth when the puck is right on the line, which looks wrong and causes the facing angle to swing wildly. Creates a depth curve that rises then falls as the puck approaches the goal line.

**Lateral positioning (angle-based):**
- The goalie positions itself on the line between the puck and the center of the net, at whatever depth the Buckley system dictates.
- `target_x = goal_center_x + (puck_x - goal_center_x) * (depth / puck_z_distance)`
- Clamped to the post boundaries.
- Movement selection based on how far the goalie needs to move:
  - `abs(delta_x) > lateral_threshold` → **T-push** (fast, ~5.0 m/s, opens five-hole more)
  - Otherwise → **Shuffle** (slower, ~2.0 m/s, tighter coverage)
- `lateral_threshold` should be `@export`, starting value ~0.3m.

**Five-hole vulnerability:**
- Five-hole openness is proportional to lateral movement speed.
- T-push opens it more than shuffle. Sealed when the goalie is set and square.
- Implemented by offsetting the left and right pad X positions apart from their config positions by `five_hole_openness`.
- `five_hole_openness` lerps toward a target based on current movement type:
  - Set and square: ~0.02m (tiny base gap)
  - Shuffling: ~0.06m
  - T-pushing: ~0.15m
- All values `@export`.

**Facing:**
- Goalie rotates on Y axis to stay square to the puck (chest facing shooter).
- Smooth rotation via `lerp_angle` with a `rotation_speed` parameter (~8.0).
- Not instant — a fast cross-crease pass means the goalie is briefly turned, creating a window.

> ℹ️ **Facing clamped near the goal line.** Added `max_facing_angle` export (default 70°). When the puck is very close to the goal line in front, `dz` approaches zero and the angle swings to nearly 90°. The facing deviation from the goalie's outward-facing base angle is now clamped to `±max_facing_angle`. Uses `angle_difference(base_angle, target_y)` to handle angle wrap-around correctly.

> ℹ️ **Facing frozen during shot.** Once `_shot_timer > 0` (reaction delay running) or the goalie is in BUTTERFLY, facing updates are skipped. This prevents the goalie from rotating away from the shot during its own reaction delay.

### BUTTERFLY

Triggered by shot detection. Seals the low net, limited mobility, top corners open up.

**Entry:** Shot detected → reaction delay timer → drop to butterfly (body parts lerp to butterfly config).

**In-state behavior:**
- Butterfly slide: tracks puck lateral position via the same `_update_target_x()` call as STANDING, then moves at ~50% of shuffle speed. Covers backdoor passes and cross-crease redirects while down.
- No depth movement — locked where the goalie dropped.
- Five-hole sealed (lerps toward 0).
- Glove and blocker still provide some high coverage.

> ℹ️ **Butterfly slide was initially missing.** `_target_x` was only updated in `_update_lateral_standing` (STANDING only), so in butterfly the goalie finished sliding to its pre-drop position and stopped. Fixed by extracting target calculation into `_update_target_x()` called by both states.

**Recovery:** When the puck is no longer a threat (speed below threshold OR moving away from goal), a recovery timer starts. When it expires, the goalie returns to STANDING. Recovery time ~0.4s — another beatable window.

### RVH (RVH_LEFT / RVH_RIGHT)

Triggered when puck goes behind the goal line. Post-sealed blocking position.

**Entry:** Puck Z crosses behind the goal line → immediately enter RVH_LEFT or RVH_RIGHT based on puck X relative to goal center. Goalie slides to the post within the state (does not wait to arrive before entering).

> ℹ️ **Entry differs from spec.** The spec called for transitioning to RVH only after the goalie arrives at the post. The implementation transitions immediately and slides to the post within the RVH state. Simpler and feels responsive enough in practice.

**In-state behavior:**
- Hugs the post. Post pad flat on ice sealed to post, back leg nearly vertical tilted into post.
- Facing locked outward (toward center ice) — does not track the puck behind the net.
- Depth lerps toward 0 (right at the goal line) within the state.
- If puck carrier crosses center X behind the net, goalie transitions between RVH_LEFT and RVH_RIGHT.

**Exit:** Puck moves back above the goal line → return to STANDING.

---

## Transitions Summary

| From | To | Condition |
|------|-----|-----------|
| STANDING | BUTTERFLY | `puck_released` signal + velocity > threshold + heading toward this goal + projected to hit near net → reaction delay → drop |
| STANDING | RVH_LEFT | Puck Z crosses behind goal line, puck X < goal_center_x |
| STANDING | RVH_RIGHT | Puck Z crosses behind goal line, puck X >= goal_center_x |
| BUTTERFLY | STANDING | Puck controlled / no shot threat → recovery timer → stand up |
| BUTTERFLY | BUTTERFLY | Lateral pass while down → butterfly slide (stay in state) |
| RVH_LEFT | STANDING | Puck moves above goal line |
| RVH_LEFT | RVH_RIGHT | Puck crosses center X behind net |
| RVH_RIGHT | STANDING | Puck moves above goal line |
| RVH_RIGHT | RVH_LEFT | Puck crosses center X behind net |

---

## Shot Detection

Connects to the `puck_released` signal on the puck node. On signal:

1. **State check:** Only trigger from STANDING.
2. **Speed check:** `puck.linear_velocity.length() > shot_speed_threshold` (~5.0 m/s). Ignore slow dump-ins.
3. **Direction check:** Puck must be moving toward this goal (velocity Z component moving in the correct direction based on `direction_sign`).
4. **Projection check:** Project puck trajectory to the goal line. `projected_x = puck_x + puck_vx * (z_distance / abs(puck_vz))`. If `abs(projected_x - goal_center_x) > net_half_width + net_margin`, ignore (wide of net). `net_margin` ~1.0m for buffer.
5. If all checks pass: `shot_detected = true`, start `shot_timer = reaction_delay` (~0.15s).
6. When timer expires: enter BUTTERFLY.

The reaction delay is the primary window where fast shots beat the goalie.

---

## Body Part Configuration

### Fixed Sizes (constant across all states)

| Part | Width (X) | Height (Y) | Depth (Z) |
|------|-----------|------------|-----------|
| Pad (x2) | 0.28 | 0.50 | 0.08 |
| Body | 0.48 | 0.55 | 0.20 |
| Glove | 0.25 | 0.25 | 0.10 |
| Blocker | 0.20 | 0.30 | 0.10 |
| Stick | 0.50 | 0.04 | 0.04 |

Sizes do not change between states. Only position and rotation change.

### Per-State Configs (catches left)

Positions are local to goalie root (y=0 is ice). Rotations are in degrees on the Z axis (front view). Blocker is on the goalie's left hand (screen-left from shooter view), glove on right hand (screen-right).

**STANDING:**

| Part | Position (x, y, z) | Rotation |
|------|---------------------|----------|
| Left pad | (-0.22, 0.0, 0.0) | 12° |
| Right pad | (0.22, 0.0, 0.0) | -12° |
| Body | (0.0, 0.50, 0.0) | 0° |
| Blocker | (-0.35, 0.43, 0.0) | 0° |
| Glove | (0.40, 0.48, 0.0) | 0° |
| Stick | (0.0, 0.02, -0.25) | 0° |

Pads angled inward at top — knees together, feet apart. Stick covers five-hole in front of goalie (negative Z is forward in Godot local space).

> ℹ️ **Stick Z is negative.** The original spec listed `z=0.25` but Godot's local -Z is the forward direction. Positive Z placed the stick behind the goalie. All stick Z values are negated in the implementation: `-0.25` (standing), `-0.30` (butterfly), `-0.20` (RVH).

**BUTTERFLY:**

| Part | Position (x, y, z) | Rotation |
|------|---------------------|----------|
| Left pad | (-0.33, 0.0, 0.0) | 90° |
| Right pad | (0.33, 0.0, 0.0) | -90° |
| Body | (0.0, 0.28, 0.0) | 0° |
| Blocker | (-0.40, 0.30, 0.0) | 0° |
| Glove | (0.45, 0.35, 0.0) | 0° |
| Stick | (0.0, 0.02, -0.30) | 0° |

Pads rotated flat on ice. Body drops. Top corners open — main vulnerability.

**RVH RIGHT POST (blocker side):**

| Part | Position (x, y, z) | Rotation |
|------|---------------------|----------|
| Right pad (post) | (0.50, 0.0, 0.0) | -90° |
| Left pad (back leg) | (0.18, 0.0, 0.0) | 5° |
| Body | (0.30, 0.42, 0.0) | 0° |
| Blocker | (0.48, 0.45, 0.0) | 0° |
| Glove | (0.0, 0.40, 0.0) | 0° |
| Stick | (0.25, 0.02, -0.20) | 0° |

Post pad flat sealed to post. Back leg vertical, tilted into post. Blocker seals post side.

**RVH LEFT POST (glove side):**

| Part | Position (x, y, z) | Rotation |
|------|---------------------|----------|
| Left pad (post) | (-0.50, 0.0, 0.0) | 90° |
| Right pad (back leg) | (-0.18, 0.0, 0.0) | -5° |
| Body | (-0.30, 0.42, 0.0) | 0° |
| Glove | (-0.48, 0.45, 0.0) | 0° |
| Blocker | (0.0, 0.40, 0.0) | 0° |
| Stick | (-0.25, 0.02, -0.20) | 0° |

Mirror of RVH right. Glove seals the post with trapper.

### Catches Right

If `catches_left = false`, mirror all glove and blocker X positions across center. The RVH post selection also flips — which arm is on which post changes.

### Body Part Transitions

Body parts lerp from current position/rotation to target config using a lerp rate (~12.0 * delta). This creates visible transitions — the goalie doesn't snap between states, it morphs. The transition time is part of the "beatable" design.

---

## Goal Assignment

> ℹ️ **Goal assignment changed.** The spec called for `@export var goal_node: Node3D` with geometry read on `_ready()`. In practice, the rink has a single `HockeyGoal` node that generates both goals procedurally — there are no separate goal nodes to reference. Instead, `GoalieController` is spawned by `ActorSpawner` (called from `GameManager`) and assigned via `setup(goalie: Goalie, puck: Puck, goal_line_z: float, is_server: bool)`. `ActorSpawner` passes `±GameRules.GOAL_LINE_Z` directly.

All depth and lateral math uses `_direction_sign = sign(-goal_line_z)` to handle both ends of the rink with the same code.

---

## Networking

The goalie must be **server-authoritative**. Currently both clients simulate goalies independently, which diverges under prediction.

**Plan:**
- Goalie AI runs on the host only (in `_physics_process`, gated by `multiplayer.is_server()` or equivalent).
- Goalie state is serialized into the world state broadcast: position (x, z), current state enum, body part positions/rotations (or just the state enum + lerp progress, and clients reconstruct configs locally).
- Clients interpolate goalie state using the same buffered interpolation pattern as remote skaters (100ms delay, `BufferedGoalieState`).
- Compact serialization: the state enum + goalie position + facing angle may be enough — clients can derive body part positions from the state enum and lerp locally.

This matches the existing pattern in the codebase: server runs physics, clients interpolate snapshots.

---

## Tuning Parameters

All of these should be `@export` for inspector tuning:

**Depth:**
- `depth_aggressive`, `depth_base`, `depth_conservative`, `depth_defensive`
- `zone_post_z`, `zone_aggressive_z`, `zone_base_z`, `zone_conservative_z`
- `depth_speed`

**Movement:**
- `shuffle_speed`, `t_push_speed`
- `lateral_threshold`
- `max_facing_angle`
- `rotation_speed`
- `rvh_transition_speed`

**Timing:**
- `reaction_delay`
- `butterfly_recovery_time`

**Shot detection:**
- `shot_speed_threshold`
- `net_half_width`, `net_margin`

**Five-hole:**
- `five_hole_base`, `five_hole_shuffle_max`, `five_hole_t_push_max`

---

## What NOT to Build

- Reactive glove/blocker saves (glove reaching for high shots) — future work
- Puck handling / clearing — future work
- Animations beyond the block-robot repositioning — future work
- Any randomness in decision-making — by design, never
- Desperation saves / "down" state — handled by physical constraints, not explicit states

---

## How the Goalie Gets Beaten

For reference during tuning — the three categories of "beatable":

1. **Reaction delays:** The goalie reads the shot correctly but the reaction timer means the butterfly drops a few frames after the puck is already past. Fast releases and quick shots exploit this.

2. **Physical movement speed:** The goalie makes the right read on a cross-crease pass but the T-push can't cross the crease faster than the pass-to-shot sequence. Playmaking and passing exploit this.

3. **Coverage gaps during transitions:** The five-hole opens during lateral movement. Top corners open in butterfly. Short-side high corner opens in RVH. Shot placement exploits this.

All three are tunable via the exported parameters. No randomness needed.
