# Hockey Game — Design Document v6.0

A 3v3 arcade hockey game built in **Godot 4.4.1** (3D, GDScript). Online multiplayer — one player per machine, each with their own camera.

**Design philosophy:** Depth over breadth — few inputs with rich emergent behavior rather than many explicit mechanics.

**Key inspirations:** Omega Strikers / Rocket League (structure), Breakpoint (twin-stick melee blade feel), Mario Superstar Baseball (stylized characters, exaggerated arcadey tuning, unique abilities, pre-match draft). Slapshot: Rebound is a cautionary reference — its pure physics shooting feels unintuitive; the blade proximity pickup system is explicitly designed to solve that accessibility gap.

---

## 1. Vision & Direction

The game targets a stylized arcade experience with four character categories: **Power, Balanced, Technique, and Speed**. Positional assignment (C/W/D) during drafting determines faceoff lineups and default defensive assignments.

The Rocket League freeplay ceiling is a guiding star — the stickhandling-to-shot pipeline should reward practice and feel satisfying to master. Players should want to spend time in free play practicing moves and scoring on the goalie.

---

## 2. Architecture

### 2.1 Scene Structure

- **Skater:** CharacterBody3D with UpperBody/LowerBody split (Node3D). Shoulder (Marker3D) under UpperBody, positioned by code based on handedness. Blade (Marker3D) and StickMesh under UpperBody. Reusable scene — one scene per skater, driven by CharacterStats resource.
- **Puck:** RigidBody3D with cylinder collision (radius 0.1m, height 0.05m). PickupZone (Area3D, SphereShape3D radius 0.5m) for blade proximity detection. Emits `puck_picked_up` and `puck_released` signals.
- **Rink:** StaticBody3D with procedurally generated walls, corners, and ice surface via @tool script.
- **Goals:** StaticBody3D with procedurally generated posts, crossbar, and back wall via @tool script.
- **Goalie:** StaticBody3D with butterfly-stance collision shapes (two leg pads + body block with five hole gap).

### 2.2 Collision Layers

| Layer | Purpose |
|-------|---------|
| 1 | General physics (boards, goals, goalies, skaters) |
| 2 | Blades (BladeArea on each skater) |
| 3 | Puck pickup zone (PickupZone on puck) |
| 4 | Ice surface |

The puck has **no layer** (mask = 1). It bounces off everything on layer 1 but doesn't push skaters.

### 2.3 Input Architecture

All input flows through an **InputState** data object populated by a **LocalInputGatherer**. This abstraction layer supports future swap to network input or AI input without touching game logic.

The gatherer requires a `Camera3D` reference to compute mouse world position via ray-plane intersection at y=0 (ice surface).

InputState fields: `move_vector`, `mouse_world_pos`, `shoot_pressed`, `shoot_held`, `slap_pressed`, `slap_held`, `facing_pressed`, `facing_held`, `brake`, `self_pass`, `self_shot`, `elevation_up`, `elevation_down`, `reset`.

### 2.4 Physics

240 FPS physics tick rate to prevent tunneling. CCD enabled on puck. Puck mass 0.17kg, radius 0.1m.

---

## 3. Controls

### 3.1 Mouse & Keyboard Layout

| Input | Action |
|-------|--------|
| **WASD** | Movement (screen-relative) |
| **Mouse position** | Blade position (always active) |
| **Left click (tap)** | Quick shot / pass |
| **Left click (hold + move)** | Wrister — charge by sweeping blade, release to fire |
| **Right click (hold)** | Slapshot charge — release to fire |
| **Shift (tap)** | Snap facing to mouse direction |
| **Shift (hold)** | Continuous facing toward mouse |
| **Scroll up** | Set elevated shot mode |
| **Scroll down** | Set flat shot mode |
| **Space** | Brake (increased friction) |
| **Q** | Self-pass (feed puck toward player — practice tool) |
| **E** | Self-shot (fire puck toward player — practice tool) |

### 3.2 Control Philosophy

The blade is **always mouse-controlled** — there is no mode toggle. The mouse drives the blade at all times. Facing is a separate, explicit action controlled by shift.

This inversion from traditional top-down controls means:
- Your attention is always on the blade and the puck
- Facing changes are deliberate, not automatic
- Moving the mouse past the blade arc limit will smoothly rotate your facing to follow, so you can never get fully stuck

---

## 4. Blade Control

The blade follows the mouse cursor at all times, originating from the stick-hand shoulder. The blade position is computed in screen space and converted to the player's local coordinate system.

### 4.1 Arc Limits

The blade is clamped to a reachable arc around the player, measured from the player's forward direction in upper-body local space:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `blade_forehand_limit` | 90° | Max arc on forehand side |
| `blade_backhand_limit` | 80° | Max arc on backhand side |

When the mouse pushes past the arc limit, the player's **facing rotates smoothly** to follow at `facing_drag_speed`, keeping the blade pinned at the limit. This means extended mouse movement in one direction naturally rotates the whole player.

### 4.2 Player-Relative Storage

When the blade is not actively following the mouse (e.g. during follow through), the blade's **player-relative angle** is stored and replayed. This means if you rotate your facing, the blade stays in the same relative position to your body — it doesn't drift in world space.

### 4.3 Upper Body Twist

The UpperBody node rotates independently of the CharacterBody3D to express the angle between facing and blade direction. The upper body rotates to `blade_angle * upper_body_twist_ratio` (default 0.5), so if the blade is 60° to the right of your facing, the upper body twists 30°. This gives the skater a natural hockey stance when reaching for the puck.

### 4.4 Handedness

Each character has an `is_left_handed` flag. This determines which side is forehand, where the shoulder pivot sits, and how the arc limits are oriented. Backhand shots are less powerful than forehand shots (`backhand_power_coefficient`, default 0.75).

### 4.5 Wall Clamping

The blade's StickRaycast detects nearby walls and shortens the blade reach accordingly. If the wall squeezes the blade significantly beyond `wall_squeeze_threshold`, the puck is released along the wall normal.

---

## 5. Facing

Facing is **locked by default**. The skater holds whatever direction they were last facing. To change facing:

- **Shift tap:** Snaps facing toward the mouse direction (fast lerp at `facing_snap_speed`)
- **Shift hold:** Continuously lerps facing toward mouse at `rotation_speed`
- **Blade drag:** Pushing the mouse past the arc limit rotates facing smoothly at `facing_drag_speed`

Shift is disabled during `WRISTER_AIM`, `SLAPPER_CHARGE_WITH_PUCK`, and `SLAPPER_CHARGE_WITHOUT_PUCK`.

---

## 6. Shooting

### 6.1 Quick Shot / Pass

**Tap left click.** If the wrister charge distance is below `quick_shot_threshold`, the puck fires in the blade's current direction at `quick_shot_power`. No aiming required — what you see is what you get. This is the low-skill-floor path: new players can click to pass, experienced players can wind up for precision shots.

### 6.2 Wrister

**Hold left click and sweep the blade, release to fire.** Power is determined by how far the blade travels during the hold, mapped from `min_wrister_power` to `max_wrister_power` over `max_wrister_charge_distance`.

**Direction variance check:** If the blade changes direction by more than `max_charge_direction_variance` (45°) in a single frame, the charge resets to zero. This prevents earning charge by wiggling the mouse back and forth.

**Backhand penalty:** If the blade is on the backhand side at release, power is multiplied by `backhand_power_coefficient` (0.75).

**Entering wrister aim without the puck:** Entering wrister aim without possession is allowed. If the puck arrives on the blade while left click is held, the shot fires on release — enabling one-touch finishes and tip-ins.

### 6.3 Slapshot — With Puck

**Hold right click while carrying the puck.** The blade fixes to a forehand position relative to the shoulder. The skater glides forward on existing momentum (no thrust, natural friction). The upper body rotates toward the mouse within `slapper_aim_arc` (45° either side) to aim. Release to fire.

Power scales from `min_slapper_power` to `max_slapper_power` over `max_slapper_charge_time`.

### 6.4 Slapshot — Without Puck (One-Timer)

**Hold right click without the puck.** Full movement and full facing rotation remain active — skate into position while charging. The blade fixes to the forehand position. If the puck is on the blade when right click is released, it fires at full charge power.

The skill expression is skating into position so the puck arrives on your blade at the right moment. If the puck is not on the blade on release, the shot cancels cleanly.

**Puck pickup during charge:** If the puck arrives on the blade while charging a slapshot, the state automatically transitions to `SLAPPER_CHARGE_WITH_PUCK`. Charge time carries over.

### 6.5 Elevation

Scroll up sets elevated shot mode. Scroll down returns to flat. The state persists until changed — no holding required.

When elevated, a Y component is added to the shot direction vector before firing:

| Shot type | Elevation amount |
|-----------|-----------------|
| Wrister / quick shot | `wrister_elevation` (0.3) |
| Slapshot | `slapper_elevation` (0.15) |

---

## 7. Puck

### 7.1 Pickup

Automatic on blade proximity via Area3D overlap. The puck freezes and follows the blade each frame. Single authority managed by the puck node — the puck tracks its own carrier.

### 7.2 Pickup vs Deflection

When the puck contacts a blade, **speed determines the outcome**:

| Puck Speed | Result |
|-----------|--------|
| Below `pickup_max_speed` (8.0) | Clean pickup — puck attaches |
| Between thresholds | Middle zone — currently picks up |
| Above `deflect_min_speed` (20.0) | Deflection — puck redirects off blade |

**Deflection direction:** The puck's velocity is blended toward the blade's outward-facing direction. `deflect_blend` (0.5) controls redirection vs continuation. `deflect_speed_retain` (0.7) controls speed retention. A `deflect_cooldown` (0.3s) prevents immediate re-attachment after a tip.

### 7.3 Puck Signals

- `puck_picked_up(carrier)` — emitted when a skater gains possession
- `puck_released()` — emitted when the puck is released for any reason

### 7.4 Puck Physics

No collision layer (mask = 1). Bounces off everything on layer 1. Reattach cooldown of 0.5s after any release.

---

## 8. Skating & Movement

### 8.1 Movement

Screen-relative WASD movement. Thrust applies up to `max_speed`. Friction naturally brings speed back down.

| Parameter | Default |
|-----------|---------|
| `thrust` | 20.0 |
| `friction` | 5.0 |
| `max_speed` | 10.0 |
| `brake_multiplier` | 5.0 |

### 8.2 Wall Squeeze

If the boards clamp the blade significantly from its intended position (exceeding `wall_squeeze_threshold`), the puck is released along the wall normal. Prevents carrying the puck through the boards.

---

## 9. Skater State Machine

| State | Blade | Movement | Facing |
|-------|-------|----------|--------|
| `SKATING_WITHOUT_PUCK` | Follows mouse | Full | Locked (shift to change) |
| `SKATING_WITH_PUCK` | Follows mouse | Full | Locked (shift to change) |
| `WRISTER_AIM` | Follows mouse | Full | Locked |
| `SLAPPER_CHARGE_WITH_PUCK` | Fixed forehand | Glide only | Locked (upper body aims within arc) |
| `SLAPPER_CHARGE_WITHOUT_PUCK` | Fixed forehand | Full | Continuous toward mouse |
| `FOLLOW_THROUGH` | Stored relative angle | Full | Locked (shift to change) |

Transitions between `SKATING_WITH_PUCK` and `SKATING_WITHOUT_PUCK` are driven by puck signals, not polled.

---

## 10. Characters & Abilities

Four character categories: **Power, Balanced, Technique, Speed**. Each character has individually tuned parameters (no rigid tier system) and a unique ability.

Positional assignment (C/W/D) during drafting determines faceoff lineups and default defensive assignments. Position doesn't change character stats — it's purely organizational.

### 10.1 Ability Design Principles

- Abilities modify physics or movement in interesting ways — never "puck goes in net"
- Simple to execute (one button press), but when and where you use it is the skill expression
- Balance is compositional: a character can be strong in isolation if they have a clear weakness that team composition can exploit

### 10.2 Draft Format

Teams take turns selecting characters from the full roster. Draft order and format TBD.

*Character roster design is far-horizon work. The core systems must feel right first.*

---

## 11. Game Flow & Rules

### 11.1 No Stoppages

The game never stops except for goals and faceoffs. All rule enforcement uses soft mechanical deterrents rather than whistles.

### 11.2 Faceoffs

Faceoffs occur after goals. The puck is dropped between two players and they battle for it using existing stick control mechanics. No minigame — just a contested puck drop.

### 11.3 Soft Offsides

Player speed decays the further they are past the blue line without the puck. Prevents cherry-picking without stopping play.

### 11.4 Soft Icing

An iced puck is placed behind the net where only the defensive team can pick it up. Punishes clearing without breaking flow.

### 11.5 Defensive Assignment Indicator

Optional visual indicator showing each player which opponent to cover (man-to-man). Purely visual, togglable per player.

- Assignments initialize from faceoff positions
- Dynamic reassignment when a significant gap develops
- Brief delay (~0.5s) before confirming reassignment to prevent flickering
- Learning aid for newer players

### 11.6 Penalties

Most penalties self-regulate in 3v3 or don't need implementation. If interference becomes a problem, lean toward mechanical solutions rather than a formal penalty system.

---

## 12. AI Goalie

The goalie is a distinct entity, not a retuned skater. Detailed behavior is deferred until core systems are playable.

**Minimal goalie contract:**
- Goalie occupies the crease
- Goalie blocks shots
- Puck stays live off the goalie (no freezing — keeps flow)
- Puck cannot leave the rink

Current implementation: StaticBody3D with butterfly-stance collision shapes, angle-tracking with reaction lag.

---

## 13. Rink

60×26m (may reduce to 2/3 scale), corner radius 8.5m. Procedurally generated via @tool script. Ice texture with NHL lines. Board bounce 0.4. Goals at both ends, 3.4m from boards.

---

## 14. Build Order

| Stage | Description | Status |
|-------|-------------|--------|
| 1 | Skating feel | ✅ Complete |
| 2 | Stick/puck interaction | ✅ Complete |
| 3 | Basic goalie | ✅ Complete |
| 4 | Second skater + collisions | Next |
| 5 | Networking test (early validation) | Planned |
| 6 | Characters + abilities | Planned |

**Architecture targets:** Skater as reusable scene, CharacterStats resource per character, game manager for authority, input abstraction for multiplayer.

---

## 15. Open Questions

*Parked for playtesting to reveal real gaps:*

- Slapshot pre/post release buffer window for one-timer timing
- Middle-zone puck reception: blade readiness check for speeds between pickup and deflect thresholds
- Elevation further refinement (additional elevation states, angles)
- Variable slapshot aim arc tuning
- Quick shot direction feel (currently fires in blade direction — may need refinement)
- Aim assist
- Camera improvements
- Goalie body parts and detailed save mechanics
- Goal detection
- Stick checks / poke checks
- Rink size tuning
- IK for arm/stick animation (will make upper body twist and blade height read correctly)
- Procedural skating animations
- Facing auto-rotation toward mouse when skating in that direction (quality of life)
- Slapshot charge direction variance check (prevent charge farming while stationary)
