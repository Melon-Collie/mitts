# Goalie 2.0 — Behavior Spec (Phase 1)

**Scope:** Lateral positioning, butterfly commitment + recovery, hand behavior.
**Out of scope (Phase 2):** Stick implementation, poke check, stick-based 5-hole seal, paddle-down, stick redirection.
**Non-goals:** Removing states, adding randomness to saves, realistic slow recovery, full biomechanical simulation.

---

## 1. Design principles (what we're aiming for)

1. **Earned goals from physics, not RNG.** Lateral speed caps, commit latency, and hand-reach envelopes are the vulnerability knobs. We never roll a die.
2. **Preserve the deterministic state machine.** Adding two sub-states (`BUTTERFLY_SLIDE_LEFT`, `BUTTERFLY_SLIDE_RIGHT`) is the only structural change. Networking cost stays within what `GoalieNetworkState` already carries.
3. **Client-simulatable.** Every new trigger must be computable from data the client already has (puck state, carrier state, skater transforms). No new broadcast fields.
4. **Arcade-realistic middle ground.** Strip slow recovery and physics fluff. Keep the vulnerability vectors: cross-crease, rebounds, low-to-high, RVH-fail, screens.
5. **Tunable over clever.** Every threshold is an `@export`. Values below are *starting points*, not gospel.

---

## 2. State machine changes

### Current
```
STANDING ⇄ BUTTERFLY
STANDING ⇄ RVH_LEFT ⇄ RVH_RIGHT
```

### Proposed
```
STANDING ⇄ BUTTERFLY ⇄ BUTTERFLY_SLIDE_LEFT
                   ⇄ BUTTERFLY_SLIDE_RIGHT
STANDING ⇄ RVH_LEFT ⇄ RVH_RIGHT
BUTTERFLY_SLIDE_* → BUTTERFLY         (on settle)
RVH_* → BUTTERFLY_SLIDE_*             (on cross-crease pass threat; new path)
```

**No direct `SLIDE_LEFT ⇄ SLIDE_RIGHT` edge.** To reverse direction, the goalie must pass through `BUTTERFLY` (settle → recommit). This is the **back-door vulnerability by design** — force the goalie to commit one way, then go the other.

### New enum
```gdscript
enum State { STANDING, BUTTERFLY, BUTTERFLY_SLIDE_LEFT, BUTTERFLY_SLIDE_RIGHT, RVH_LEFT, RVH_RIGHT }
```

### Why two slide states instead of one with a direction flag

The butterfly slide is inherently asymmetric — drive leg pushes, lead leg glides, hands take different jobs. Baking direction into the state (rather than mirroring at runtime) keeps each `GoalieBodyConfig` explicit and avoids compounding with the existing `catches_left` mirror pass in `_get_config`.

### Networking impact
- `state_enum: int` already exists in `GoalieNetworkState`. Two new enum values fit.
- No new per-frame fields. Slide direction is encoded in the state enum itself; target X is deterministic given current position + puck state.
- `state_transitioned` signal fires on every entry; reliable RPC guarantees client gets it.
- **Six states total** (was four). Still a small fixed set.

---

## 3. Lateral positioning (STANDING)

### 3.1 What changes vs. current

Current (`target_lateral_x`): pure angle bisector from puck to two posts, intersected with goalie's depth plane.

**Problems:**
- Depth plane is fixed — goalie moves in straight lines when puck cycles around the zone. Should arc.
- No short-side bias — goalie over-respects the long-side shot on sharp angles.
- No handedness awareness.

### 3.2 Arc-based positioning

Replace the depth-plane intersection with a point along a ray from goal center through the puck, at distance = `_current_depth`:

```gdscript
# Pseudocode — replaces target_lateral_x entirely
static func target_position_on_arc(
        puck_position: Vector3,
        goal_line_z: float,
        goal_center_x: float,
        current_depth: float,
        net_half_width: float,
        direction_sign: int) -> Vector2:   # returns (x, z)

    # Vector from goal center to puck in horizontal plane
    var gc := Vector2(goal_center_x, goal_line_z)
    var p  := Vector2(puck_position.x, puck_position.z)
    var dir := (p - gc)
    if dir.length() < 0.001:
        return Vector2(goal_center_x, goal_line_z + direction_sign * current_depth)
    dir = dir.normalized()

    # Position on arc: depth away from goal line, along the puck vector
    var arc_point := gc + dir * current_depth

    # Clamp X to within posts (goalie can't stand outside the pipes while standing)
    arc_point.x = clampf(arc_point.x, goal_center_x - net_half_width,
                                      goal_center_x + net_half_width)
    return arc_point
```

This means lateral X and Z both come from the same calculation. **The goalie's Z no longer equals `goal_line_z + direction_sign * _current_depth` on a flat plane — it arcs.** This is the single biggest realism gain for lateral feel.

### 3.3 Short-side bias

After computing the arc point, lerp toward the near post when the puck is at a sharp angle:

```gdscript
# After computing arc_point:
var puck_z_dist: float = abs(puck_position.z - goal_line_z)
var puck_x_dist: float = abs(puck_position.x - goal_center_x)
var is_sharp_angle: bool = puck_z_dist < zone_post_z * 2.5 and puck_x_dist > net_half_width

if is_sharp_angle:
    var near_post_x: float = goal_center_x + sign(puck_position.x - goal_center_x) * net_half_width
    # Near post is outside the arc clamp; bias slightly toward it
    arc_point.x = lerpf(arc_point.x, near_post_x, short_side_bias)  # 0.15 default
```

**Tuning exports:**
```gdscript
@export var short_side_bias: float = 0.15          # 0.0 = pure bisector, 0.3 = aggressive cheat
@export var sharp_angle_distance: float = 5.0      # z-distance below which we consider "sharp"
```

Skip handedness for Phase 1. It requires knowing which skater is the likely shooter and their hand, and the gain is marginal vs. the arc + short-side change. Revisit in playtest.

### 3.4 Movement speed caps by type

Current code uses `shuffle_speed` / `t_push_speed` based on `lateral_threshold`. Keep this but add an explicit speed differential:

```gdscript
@export var shuffle_speed: float = 1.0    # was 1.3 — tightened toward realism (~0.9 m/s)
@export var t_push_speed: float = 3.5     # was 3.0 — bumped toward upper realism (~3.7 m/s)
@export var lateral_threshold: float = 0.4  # was 0.3 — slightly larger shuffle window
```

The effect: cross-crease passes that exceed what T-push can cover within puck-travel-time become unsaveable **by physics**. This is the primary earned-goal knob.

### 3.5 Decision flowchart

```
Per frame in STANDING:
  if puck in defensive zone:
    → RVH (existing logic)
  elif _is_under_pressure() OR release cue triggered (§4):
    → BUTTERFLY or SLIDE_LEFT/SLIDE_RIGHT (see §5)
  else:
    target = target_position_on_arc(...)
    target = apply_short_side_bias(target, ...)
    dx = target.x - _current_x
    if |dx| > lateral_threshold:
      move with t_push_speed
    else:
      move with shuffle_speed
    # Depth comes from Buckley chart (unchanged), but position Z is now
    # derived from the arc point, not the depth plane directly.
```

### 3.6 Implementation notes

The arc approach means `_current_depth` and the goalie's actual Z position can drift apart during lateral movement. Two options:

**Option A (recommended):** Keep `_current_depth` as a scalar (horizontal distance from goal center). Compute position Z from the arc each frame. The "depth" conceptually becomes "radius."

**Option B:** Keep current Z decoupled from depth, and let the arc math resolve to an (x, z) pair each frame.

Option A is cleaner and matches how Buckley actually thinks about it (distance, not depth plane). **Networking note:** `GoalieNetworkState` already carries absolute `position_x` and `position_z`, so the on-wire format is unchanged regardless.

---

## 4. Release detection (medium version)

Goal: drop butterfly ~100–150 ms **before** the puck leaves the stick, when the shot is likely and in-range.

### 4.1 Data available

From existing systems:
- Puck carrier identity (via `puck.carrier` or signal state)
- Carrier position, velocity, facing angle
- Carrier stick angle / swing state (you mentioned skater has facing + velocity + stick)

### 4.2 Shot intent scoring

```gdscript
# Returns 0.0 (no shot intent) → 1.0 (imminent shot)
static func compute_shot_intent(
        carrier: Skater,
        puck_position: Vector3,
        goal_line_z: float,
        goal_center_x: float,
        direction_sign: int) -> float:

    # 1. Distance gate — no shot intent from the neutral zone
    var distance_to_net: float = abs(puck_position.z - goal_line_z)
    if distance_to_net > shot_intent_max_distance:       # 18.0
        return 0.0

    # 2. Facing — is the carrier pointed at the net?
    var to_net := Vector2(goal_center_x - carrier.global_position.x,
                          goal_line_z - carrier.global_position.z).normalized()
    var facing := Vector2(-sin(carrier.rotation_y), -cos(carrier.rotation_y))
    var facing_dot: float = facing.dot(to_net)           # 1.0 = pointed at net
    if facing_dot < 0.3:                                 # more than ~70° off-net
        return 0.0
    var facing_score := smoothstep(0.3, 0.85, facing_dot)

    # 3. Stick loading — if skater has a wind-up or shot-prep state
    var stick_score: float = carrier.stick_load_progress  # 0.0–1.0, assume exists
    # Fallback if no stick load data: use carrier velocity direction
    if stick_score < 0.0:  # sentinel for "not available"
        var vel_dot := carrier.linear_velocity.normalized().dot(Vector3(to_net.x, 0, to_net.y))
        stick_score = clampf(vel_dot, 0.0, 1.0)

    # 4. Distance weighting — closer = higher baseline intent
    var distance_score := 1.0 - smoothstep(6.0, shot_intent_max_distance, distance_to_net)

    # Blend
    return facing_score * 0.4 + stick_score * 0.4 + distance_score * 0.2
```

### 4.3 Butterfly trigger thresholds

Distance-gated commit, per the research:

```gdscript
# In _update_state(), STANDING branch:
var intent: float = compute_shot_intent(...)
var puck_z_dist: float = abs(_tracked_puck_position.z - _goal_line_z)

var commit_threshold: float
if puck_z_dist < 6.0:                     # high-danger slot
    commit_threshold = 0.55               # drop easily
elif puck_z_dist < 9.0:                   # hashmarks to tops
    commit_threshold = 0.75               # drop on clear loading
else:                                     # outside
    commit_threshold = 0.90               # rarely drop preemptively

if intent >= commit_threshold:
    _state = State.BUTTERFLY
```

### 4.4 Existing pressure trigger stays

`_is_under_pressure()` covers the "skater charges the net without winding up" case (dekes, drive-to-net). Keep it. The release detection adds a **second** path into butterfly that fires earlier for shot-heavy plays.

### 4.5 Existing shot detection stays

`_on_puck_released` + `detect_shot` still run. They handle the case where the goalie *didn't* anticipate (intent below threshold) and a shot is incoming. Elevated-shot reaction (hand raise) still triggers from there. The release-detection system is purely **pre-release anticipation**; post-release reaction is unchanged.

### 4.6 Tuning exports

```gdscript
@export var shot_intent_enabled: bool = true           # kill switch
@export var shot_intent_max_distance: float = 18.0     # beyond this, don't bother computing
@export var shot_intent_commit_close: float = 0.55     # puck < 6m
@export var shot_intent_commit_mid: float = 0.75       # puck 6-9m
@export var shot_intent_commit_far: float = 0.90       # puck > 9m
```

### 4.7 Fallback (if stick_load_progress isn't available)

The scoring blend uses `stick_score` as a fallback. If your skater doesn't expose load progress at all, set its weight to 0 in the blend and use velocity-toward-net as a full substitute:

```gdscript
# Simple fallback: skater moving toward net at speed = intent to shoot soon
return facing_score * 0.5 + distance_score * 0.3 + velocity_toward_net_score * 0.2
```

**Disabling the feature** entirely (`shot_intent_enabled = false`) reverts to current behavior: butterfly fires only from `_is_under_pressure()` or `_on_puck_released` trajectory projection.

---

## 5. Butterfly and Butterfly Slide

### 5.1 When to use SLIDE vs. BUTTERFLY

`BUTTERFLY_SLIDE_*` is entered when **lateral coverage is needed after the goalie is already committed down** (or must commit while moving). The canonical case is a cross-crease pass to a loaded one-timer.

Decision logic at state entry:

```gdscript
# Transitioning from STANDING (or RVH) to a down-state:
var needs_lateral: bool = false
var target = target_position_on_arc(...)
var lateral_delta: float = abs(target.x - _current_x)

# Cross-crease detection: puck velocity has large lateral component
var puck_lateral_speed: float = abs(puck.linear_velocity.x)
var puck_approaching: bool = _puck_approach_velocity > 2.0

if lateral_delta > slide_trigger_distance:       # 0.6 m default
    needs_lateral = true
if puck_lateral_speed > slide_trigger_speed and puck_approaching:  # 8 m/s
    needs_lateral = true

if needs_lateral:
    # Direction is determined in goalie-local space. -_direction_sign flips
    # to match the goalie's facing — same convention as puck_local_x elsewhere.
    var slide_dir_local: float = (target.x - _current_x) * -_direction_sign
    _state = (State.BUTTERFLY_SLIDE_LEFT if slide_dir_local < 0.0
              else State.BUTTERFLY_SLIDE_RIGHT)
else:
    _state = State.BUTTERFLY
```

**Direction is latched at state entry and does not change mid-slide.** If the puck reverses direction during a slide, the goalie finishes the current push, settles into `BUTTERFLY`, then re-commits the opposite way on the next frame's evaluation. This is the back-door vulnerability window (§5.5).

### 5.2 BUTTERFLY_SLIDE_* behavior

Both slide states share identical movement logic; only the body-part config differs (drive leg / lead leg / hand positions are mirrored).

```gdscript
State.BUTTERFLY_SLIDE_LEFT, State.BUTTERFLY_SLIDE_RIGHT:
    # Speed cap — this is an earned-goal lever. If the pass crosses faster than
    # this, the slide physically cannot cover it.
    var slide_speed_cur: float = butterfly_slide_speed   # 4.0 peak
    # Decelerate as we approach target
    var dist_remaining: float = abs(_target_x - _current_x)
    if dist_remaining < slide_decel_distance:            # 0.5
        slide_speed_cur *= smoothstep(0.0, slide_decel_distance, dist_remaining)

    _current_x = move_toward(_current_x, _target_x, slide_speed_cur * delta)

    # Slide blocks pop-up: recovery_timer only counts while SETTLED
    var settled: bool = dist_remaining < slide_settle_distance  # 0.1
    if settled:
        _state = State.BUTTERFLY  # now normal butterfly recovery applies
        _recovery_timer = 0.0
        _slide_recommit_timer = slide_recommit_delay   # see §5.5

    # Five-hole is open slightly during slide (pads separated for push)
    if is_server:
        _five_hole_openness = lerpf(_five_hole_openness,
                                    five_hole_slide_max,       # 0.22
                                    part_lerp_speed * delta)
```

**Direction reversal is impossible mid-slide.** There is no path from `SLIDE_LEFT` to `SLIDE_RIGHT` (or vice versa) — the state machine must pass through `BUTTERFLY`. This is the back-door exploit by design.

### 5.3 Speed caps (summary)

| State               | Lateral speed (m/s) | Notes |
|---------------------|---------------------|-------|
| STANDING shuffle    | 1.0                 | Small movements, square-to-puck |
| STANDING T-push     | 3.5                 | Long laterals |
| BUTTERFLY           | 1.0                 | Already-down corrections |
| BUTTERFLY_SLIDE_*   | 4.0                 | Peak; decelerates on approach |
| RVH→STANDING        | 6.0                 | Explosion off post (existing) |

Real NHL goalies hit ~3.0–4.5 m/s peak in a slide. Setting the cap at 4.0 is the arcade-realistic middle ground that leaves cross-crease Royal Road passes un-coverable when puck lateral velocity × time-to-net exceeds what the slide can cover.

### 5.4 Recovery (BUTTERFLY → STANDING)

Current logic (`_update_state()`, `State.BUTTERFLY` branch) has a `butterfly_recovery_time` accumulator gated by `speed_low OR moving_away`. Keep this. Refinements:

```gdscript
State.BUTTERFLY:
    # Tick down the post-slide recommit cooldown (see §5.5)
    if _slide_recommit_timer > 0.0:
        _slide_recommit_timer -= delta

    if _is_under_pressure() OR shot_intent_still_high():
        _recovery_timer = 0.0              # don't pop while threatened
    elif puck_is_clearly_safe():           # away, slow, or cleared
        _recovery_timer += delta
        if _recovery_timer >= butterfly_recovery_time:
            _state = State.STANDING
            _recovering_from_butterfly = true
    else:
        _recovery_timer = 0.0

    # Still handle mid-butterfly target tracking
    if not _reacting_to_shot:
        _update_target_x()
    # ... existing facing/slide-speed-lerp logic ...

    # NEW: if puck now requires lateral coverage > threshold, transition to slide.
    # Respect recommit cooldown so we don't rapid-fire LEFT → BUTTERFLY → RIGHT
    # on noisy puck data.
    if _slide_recommit_timer <= 0.0:
        var lateral_delta: float = abs(_target_x - _current_x)
        if lateral_delta > slide_trigger_distance:
            var slide_dir_local: float = (_target_x - _current_x) * -_direction_sign
            _state = (State.BUTTERFLY_SLIDE_LEFT if slide_dir_local < 0.0
                      else State.BUTTERFLY_SLIDE_RIGHT)
```

### 5.5 Back-door vulnerability and pop-up lock

Two properties compose to create the back-door vulnerability:

1. **`BUTTERFLY_SLIDE_*` blocks pop-up.** `_recovery_timer` only runs in `BUTTERFLY`, not in slide states. The goalie cannot return to `STANDING` until it re-enters `BUTTERFLY` by settling.

2. **Slide reversal must pass through BUTTERFLY.** With no direct `SLIDE_LEFT ⇄ SLIDE_RIGHT` edge, reversing requires: finish current push → settle → enter `BUTTERFLY` → evaluate new target → trigger new slide. The window during settle + `slide_recommit_delay` is when the far side is open.

**The `slide_recommit_delay` knob** prevents rapid-fire oscillation on noisy puck data and gives a direct tuning parameter for "how punishing is the back-door":

- `slide_recommit_delay = 0.0` — maximum reactivity; back-door is only limited by slide speed.
- `slide_recommit_delay = 0.15` (default) — moderate vulnerability; a well-timed back-door pass scores.
- `slide_recommit_delay = 0.30+` — severe vulnerability; back-door is a core offensive tool.

Start at 0.15 and tune from playtest feel.

```gdscript
# Controller state (new)
var _slide_recommit_timer: float = 0.0   # gates re-triggering a slide after settle
```

### 5.6 Tuning exports (new)

```gdscript
@export var slide_trigger_distance: float = 0.6       # lateral delta that triggers SLIDE over BUTTERFLY
@export var slide_trigger_speed: float = 8.0          # puck lateral speed that triggers SLIDE
@export var butterfly_slide_speed: float = 4.0        # peak slide speed (was 3.5)
@export var slide_decel_distance: float = 0.5         # start slowing down this close to target
@export var slide_settle_distance: float = 0.1        # close enough to transition back to BUTTERFLY
@export var slide_recommit_delay: float = 0.15        # min time in BUTTERFLY before new slide can fire (back-door window)
@export var five_hole_slide_max: float = 0.22         # 5-hole opens during slide push
```

---

## 6. Hand behavior

### 6.1 Quiet hands principle

Hands ride with the torso. They do **not** continuously track the puck. They move only on:
- State transitions (stance pose change)
- Shot reaction (elevated shot → raise glove/blocker toward impact)

Your current `_apply_elevated_shot_reaction` already does the right thing for elevated shots. Keep it.

### 6.2 Reaction vs. Blocking butterfly blend

Add a distance-gated pose blend within `BUTTERFLY`:

```gdscript
# In _get_config, BUTTERFLY branch:
var puck_dist: float = _tracked_puck_position.distance_to(goalie.global_position)
# t=0: reaction butterfly (hands up, out — current positions)
# t=1: blocking butterfly (hands low, tucked on pads)
var blocking_blend: float = 1.0 - smoothstep(butterfly_blocking_dist_min,  # 1.5
                                              butterfly_blocking_dist_max, # 3.0
                                              puck_dist)

# Reaction pose (current values)
var reaction_blocker_pos := Vector3( 0.46, 0.49, -0.18)
var reaction_glove_pos   := Vector3(-0.42, 0.44, -0.18)

# Blocking pose — hands low on pads, tucked
var blocking_blocker_pos := Vector3( 0.28, 0.22, -0.10)
var blocking_glove_pos   := Vector3(-0.28, 0.22, -0.10)

c.blocker_pos = reaction_blocker_pos.lerp(blocking_blocker_pos, blocking_blend)
c.glove_pos   = reaction_glove_pos.lerp(blocking_glove_pos,     blocking_blend)
```

**Effect:** far-away shots → reaction butterfly (hands up for high-shot reach). In-tight shots → blocking butterfly (hands low, sealing over-the-pad).

### 6.3 Rotation lag

Hands lag torso rotation slightly to avoid a robotic snap:

```gdscript
# In the controller, track previous rotation y
var _prev_rotation_y: float = 0.0
var _hand_rotation_y: float = 0.0

# After setting goalie rotation:
_hand_rotation_y = lerp_angle(_hand_rotation_y, goalie.get_goalie_rotation_y(),
                              hand_rotation_lag_speed * delta)  # 10.0
```

This is a visual-only refinement. Drive hand world position with `_hand_rotation_y` instead of current rotation. Skip if the turning speeds already look fine in playtest — it's a nice-to-have.

### 6.4 Tuning exports (new)

```gdscript
@export var butterfly_blocking_dist_min: float = 1.5   # below this: full blocking pose
@export var butterfly_blocking_dist_max: float = 3.0   # above this: full reaction pose
@export var hand_rotation_lag_speed: float = 10.0      # hand rotation tracking speed
```

---

## 7. Per-frame flowchart

```
_physics_process(delta):
  _update_tracking(delta)
    └── update _tracked_puck_position, _puck_approach_velocity

  _update_shot_timer(delta)
    └── if timer expired AND STANDING → BUTTERFLY

  _update_state(delta):
    STANDING:
      if defensive_zone → RVH_*
      elif intent_score >= commit_threshold (§4) → BUTTERFLY or SLIDE_L/R (§5.1)
      elif _is_under_pressure → BUTTERFLY or SLIDE_L/R (§5.1)
    BUTTERFLY:
      tick down _slide_recommit_timer
      if _is_under_pressure → reset recovery timer
      elif lateral_delta > slide_trigger AND recommit_timer <= 0 → SLIDE_L or SLIDE_R
      elif puck safe → accumulate recovery → STANDING
    BUTTERFLY_SLIDE_LEFT, BUTTERFLY_SLIDE_RIGHT:
      if settled → BUTTERFLY (sets _slide_recommit_timer = slide_recommit_delay)
      else stay; no pop-up, no direction change
    RVH_*:
      (unchanged)

  _update_depth(delta)
    └── Buckley chart (unchanged math)

  _update_position(delta):
    STANDING → arc point + short-side bias + shuffle/T-push speed cap
    BUTTERFLY → move toward target at butterfly base speed (1.0)
    BUTTERFLY_SLIDE_* → move toward target at slide speed with decel
    RVH_* → post anchor (unchanged)

  _update_facing(delta)  (unchanged)

  _update_body_parts(delta):
    SLIDE_LEFT and SLIDE_RIGHT use distinct GoalieBodyConfigs (asymmetric)
    hand pose in BUTTERFLY = reaction/blocking blend (§6.2)
    elevated shot reaction applied on top (unchanged)
```

---

## 8. Vulnerability vectors — how each earned goal happens

This is a QA/design reference for playtest, not code.

| Goal type          | Mechanism                                                                 |
|--------------------|---------------------------------------------------------------------------|
| Cross-crease       | Puck lateral speed × time-to-net > `butterfly_slide_speed` × available time |
| Back-door reversal | Force goalie to commit `SLIDE_LEFT`, then pass opposite direction. Reversal requires `SLIDE_LEFT → BUTTERFLY → SLIDE_RIGHT`; the settle + `slide_recommit_delay` window exposes the far side |
| Rebound            | First shot redirects; goalie committed to butterfly; recovery time > second shot release |
| Top-shelf          | Elevated shot, hand not in position; reach envelope exceeded              |
| Short-side RVH-fail| Shot goes over shoulder/post; RVH stance exposes this by design           |
| Screen             | Low `shot_intent` → no preemptive drop; reaction delay eats the save window |
| Low-to-high        | Blocking butterfly after in-tight play; puck raised over pad              |
| Late release       | Goalie commits at intent ≥ 0.75; shooter delays release past 200 ms commit; top-shelf opens |

None of these require randomness. All are geometric/temporal consequences of the constraints above.

---

## 9. Networking checklist

- ✅ No new fields in `GoalieNetworkState`.
- ✅ Two new enum values (`BUTTERFLY_SLIDE_LEFT`, `BUTTERFLY_SLIDE_RIGHT`) fit in existing `state_enum: int`. Six states total.
- ✅ `state_transitioned` signal already broadcasts reliably on every state change. Client sees slide direction from the state enum itself.
- ✅ Slide target X is deterministic from puck state + current position; client re-derives.
- ✅ `_slide_recommit_timer` is server-side state only — client doesn't need it because state transitions come via reliable RPC and the client just mirrors.
- ✅ `shot_intent` is deterministic from skater state + puck state; client re-derives each frame.
- ✅ Five-hole changes stay in existing `five_hole_openness` field.
- ⚠️ `shot_intent` is sensitive to carrier transform interpolation lag on the client. Acceptable for Phase 1 — correction broadcast at 40 Hz dampens drift. Monitor in playtest.

---

## 10. Phase 1 implementation order

Suggested so playtest feedback lands on one change at a time:

1. **Arc positioning** (§3.2). Biggest visual improvement, most self-contained.
2. **Speed cap tightening** (§3.4). Tune `shuffle_speed`, `t_push_speed`, `butterfly_slide_speed` based on feel.
3. **BUTTERFLY_SLIDE_LEFT / BUTTERFLY_SLIDE_RIGHT sub-states** (§5). Requires state machine edit, new entry paths from STANDING/RVH/BUTTERFLY, direction latching, and two distinct body-part configs (offsets to be specced against the scene once the states exist — see §11).
4. **Short-side bias** (§3.3). Small code change; easy to toggle with export.
5. **Hand pose blend** (§6.2). Visual only; no state implications.
6. **Release detection** (§4). Most behaviorally impactful but most dependent on skater-side data. Ship with `shot_intent_enabled = false` initially; toggle on after other changes prove stable.
7. **Hand rotation lag** (§6.3). Polish pass, last.

---

## 11. Slide body-part configs (TBD during implementation)

The two slide states need distinct `GoalieBodyConfig` values because the slide is physically asymmetric — drive leg pushes, lead leg glides, hands do different jobs. These numbers are deliberately **not** specified here; they should be tuned against the actual scene during step 3 of §10, the same way the existing BUTTERFLY and RVH poses were tuned.

Structural rules for whoever writes the configs:

- **Drive leg** (the leg doing the push): slightly raised, angled. For `SLIDE_LEFT`, drive leg is the right pad. For `SLIDE_RIGHT`, drive leg is the left pad.
- **Lead leg** (the leg gliding toward puck): flat, extended, sealing the shot lane. Same pad as the slide direction.
- **Hands:** blocker stays in reaction-butterfly zone (hands are not tucked during slide — goalie is actively reading the shot). Glove can lead slightly toward the shot lane.
- **Five-hole:** opens per `five_hole_slide_max` (0.22) — the drive push naturally separates the pads.

### `catches_left` interaction

The existing `_get_config` mirror at the bottom (that swaps glove/blocker when `catches_left == false`) is for left-handed catching. The slide's drive-leg / lead-leg designation is tied to slide *direction*, not catching hand. Cleanest approach: write the two slide configs explicitly for `catches_left = true`, then at config lookup time swap which state is served to right-catching goalies:

```gdscript
func _get_config(state: State) -> GoalieBodyConfig:
    var effective_state := state
    if not catches_left:
        match state:
            State.BUTTERFLY_SLIDE_LEFT:  effective_state = State.BUTTERFLY_SLIDE_RIGHT
            State.BUTTERFLY_SLIDE_RIGHT: effective_state = State.BUTTERFLY_SLIDE_LEFT
    match effective_state:
        # ... existing pose branches, including new SLIDE_LEFT/SLIDE_RIGHT ...

    # Then skip the glove/blocker xpos swap for slide states (they're already
    # handled by the effective_state mapping above). Keep the swap for other states.
```

This keeps the asymmetric hand-job logic intact while letting left- and right-catching goalies share the same two slide configs.

---

## 12. Out-of-scope reminder (Phase 2)

These are called out in the research but deferred to the stick spec:

- Stick attachment to blocker hand
- 5-hole seal as a geometric property of stick blade height (currently approximated by `_five_hole_openness`)
- Poke check state and extended collider
- Paddle-down wraparound pose
- Stick-based rebound redirection
- RVH stick pose differences glove-side vs. blocker-side

Phase 1's hand-position system is designed so stick attachment in Phase 2 is purely additive — hand world positions don't change when a stick gets parented to the blocker.
