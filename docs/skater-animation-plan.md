# Skater animation rebuild — plan

Status: **agreed; Phases 1–3 landed.** The §9 decisions were taken as proposed.
Deviating from this version means asking first, per CLAUDE.md. §11–§13
record what each phase changed from the design and what it found.

## Why rebuild instead of tune

The skating physics rework (skate-heading model, tight turns, power-limited
stride) made the skating feel right and made the animation's problems visible.
Two symptoms were reproduced and measured with the `wiggle_*` poses in
`tools/pose_capture_runner.gd` (`trace` prints where head, pelvis, hip joints
and skates sit across the line of travel):

| Input, skating forward at ~9 m/s | What the body does |
|---|---|
| Cursor swung side to side | facing yaws ±45°, the hips counter-yaw up to 46° to stay on travel, the torso twists ~20° more toward the blade — and the head swings **±0.18 m across the travel line** while the pelvis stays put. The torso is tipping sideways off the hips. |
| A/D tapped every quarter second | the trunk bank swings **+24° → −14°** each tap and the skates kick 0.3–0.4 m sideways. |

Neither is a bad number. Both are the structure:

1. **The hierarchy is in an order no body is built in.** The skater root yaws
   to the cursor. Under it, `UpperBody` and `LowerBody` are *siblings*, each
   yawed by its own writers — five of them on the lower body alone (turn lag,
   hip-to-travel alignment, pivot, hockey stop, shot coil), twist toward the
   blade on the upper. Nothing ties the two together, and they run on
   different clocks and smoothing rates.
2. **Lean is applied in the wrong frame.** Godot's YXZ Euler order pitches a
   node about its *own, already-yawed* X axis. The forward lean is computed in
   the facing frame and applied to an `UpperBody` twisted up to 67° further,
   so with the cursor off to one side "lean forward" is mostly "lean
   sideways". A spine flexes at the hips, about the *pelvis's* axis, and the
   shoulders twist on top of that — lean first, then twist.
3. **The pelvis is on the wrong side of the seam.** The shorts are a bone in
   the UPPER skeleton, so they yaw with the shoulders while the thighs yaw with
   the hips. `Scripts/actors/CLAUDE.md` records why it went there: it "can
   belong to neither" the torso nor a leg. That was true with two sibling
   skeletons. In a chain, the pelvis is the parent of both.
4. **Gameplay geometry and the visible torso are one node.** `Blade`,
   `TopHand` and `Shoulder` hang under `UpperBody`. Every rotation of the
   visible torso moves gameplay geometry, so the torso's real motion is faked
   as a *texture* on the torso bones — a second torso pose on a second clock.
   For the same reason, the render-rate crouch drop (which writes
   `UpperBody.position.y`) moves the blade marker on a clock that depends on
   frame rate and visibility.
5. **The gait is a sum of ~30 channels, not a set of states.** Dig-in,
   reversal, shuffle, backpedal, glide, sprint, carve curvature, carve intent,
   pivot, stop and tight turn each add angles to shared rolls and pitches, and
   fade factors (`rock_fade`, `gait_scale`, `carve_fwd_gate`, the pivot and
   stop fades…) try to stop them fighting. The trunk texture alone sums 16
   channels. Every feature adds a fade, and combinations nobody looked at
   produce the flail.
6. **Nothing has mass.** Every channel is a first-order ease toward a target
   that can jump, so the body answers input as fast as the player can wiggle
   it. The bank is the worst case: it tracks the smoothed turn rate with about
   0.2 s of lag, so steering corrections throw the whole body.

## Goals

- The body reads as **one connected figure** in every state: no segment slides
  off the one below it, by construction rather than by tuning.
- Posture comes from a **small set of physical drivers** — velocity,
  acceleration, the locomotion state the physics already decided, the stick
  target — through models with inertia.
- **Zero gameplay change from the visual rebuild.** Blade, hands, reach and
  everything on the wire keep their exact numbers (with the one deliberate
  exception in §3).
- Every invariant the rebuild relies on is **a test**, and the wiggle trace
  becomes one.

### Non-goals

- No change to the skating physics, the stick IK's gameplay solve, or the
  network state.
- No keyframed animation clips. The rig stays procedural, derived from
  replicated state, and costs zero network bytes, as it does today.
- The goalie is out of scope.

## §1 Split the gameplay frame from the visible body

`UpperBody` becomes what it already is in practice: the **gameplay frame**. It
keeps its exact transform math — facing, twist, reach lean, velocity lean — and
its markers. It stops carrying anything drawn.

The visible body is a separate chain, built in code (the skeletons are already
code-generated, so no `.tscn` editing is needed), placed at
`Skater.render_transform()` and opted out of physics interpolation, per the
render-clock rule in CLAUDE.md. Its arms **reach** for the gameplay hands with
the existing `TopHandIK` and two-bone arm solve, so the stick is where gameplay
says it is and the body adapts to it, never the reverse.

That removes the reason the trunk texture exists, and it puts every visible
segment on one clock. Today node rotations are drawn physics-interpolated while
bone poses are written at render rate, and the two disagree by the
interpolation fraction.

**The one gameplay change:** the crouch drop stops moving `UpperBody.position.y`.
The gameplay frame's height becomes a physics-rate quantity, or a constant (§9,
Q5). The IK already corrects the blade's ice height through the lean, so the
expected effect is nil. This is the only step in the plan that must be checked
against gameplay tests rather than renders alone.

**Arm-reach budget.** The visible shoulders will no longer sit exactly where
the gameplay `Shoulder` marker does, because lean-then-twist and the bank put
them elsewhere. The arms absorb the difference. That gap needs a measured
ceiling, and a test that holds it, so an overstretched arm fails a build rather
than showing up on screen.

## §2 One chain, built up from the ice

One `Skeleton3D` with a real bone hierarchy replaces the two sibling skeletons,
consistent with `docs/skinned-skater-plan.md` ("how an articulated character is
supposed to be built"):

```
ROOT      at the skates, on the ice; yaw = skate heading (= travel, the
          movement model's own definition), except in backward / pivot / stop
  BANK    whole-body roll and fore-aft lean about the blades (§4)
    PELVIS  hip yaw relative to the skates, hip flexion; carries the shorts
      LEG_L / LEG_R → shin → skate        (the existing leg chain, unchanged)
      SPINE   forward lean in the PELVIS frame, then twist toward the stick
        CHEST   shoulder caps, stride sway
          HEAD  stabilised: eyes level, tracking the cursor / puck
          ARM_TOP / ARM_BOTTOM → IK to the gameplay hands
```

Properties that fall out of the order rather than being enforced:

- The shorts and the thighs share the PELVIS frame, so they cannot separate.
- Lean is applied before twist, so swinging the cursor rotates a leaned
  torso about its own spine instead of tipping it sideways.
- A bank pivots the whole figure about the blades. The current split (legs
  roll about the hips, the trunk texture rolls about the waist) is what lets
  the two halves part.
- **Twist has a joint limit.** Shoulders against hips is capped at a real
  range (§9, Q1). Past it the hips have to follow, which is what a pivot is —
  so the pivot stops being a separate yaw writer fighting the alignment, and
  becomes what happens when the twist runs out.

What carries over unchanged: the mesh builder, the sizing seam, the leg chain's
geometry, `TopHandIK` and the arm solve, the stick rig, and the VFX reads
(`mark_position`, edge loads) — which become reads off the one skeleton.

## §3 Gameplay frame cleanup

Separate from the visual work, and decided independently (§9, Q5):

- The crouch drop leaves the gameplay frame (§1).
- `UpperBody`'s velocity lean is a pitch about the twisted axis — the same
  frame bug as point 2 of "Why rebuild", but on *gameplay* geometry: it
  decides where the blade sits. Fixing it is a gameplay change (blade reach
  while the torso is twisted), so it is listed rather than assumed.
- The reach lean is a real mechanic ("leaning toward the target genuinely
  extends world reach") and stays.

## §4 Posture from balance, with mass

Replace the hand-authored lean channels with what balances the body:

- **Bank** = atan(a_lat / g), the angle that balances a turn.
- **Fore-aft lean** = a posture floor (the skating crouch) plus
  atan(a_tan / g): forward driving, back stopping. Dig-in, sprint drive,
  reversal and the stop lean-back fall out of this, rather than being four
  channels.

Both targets drive the BANK bone through a **critically damped second-order
spring**, the response of a body that has to move its centre of mass over its
edges. The natural frequency is chosen from rise time: a real skater sets a
turn lean in roughly 0.3–0.5 s. Worked at ω_n = 7 rad/s:

| Input | Response |
|---|---|
| sustained turn (step) | 90% of the balancing angle in ≈ 0.55 s |
| steering wiggle at 2 Hz | ≈ 25% amplitude (30° → 7°) |
| steering wiggle at 4 Hz | ≈ 7% amplitude (30° → 2°) |

That is the tap-steering flail gone by the model, not by a dead-zone. The
existing soft knee (`carve_bank_knee_accel`) can probably be deleted once this
lands; measure it.

The inputs come from velocity history, which every machine has (remotes,
replays and bots alike), so no new network state is needed.

## §5 Locomotion states, from the physics' own decision

Each tick `SkaterMovementRules.apply_movement` already classifies the input:
stride, skid, edge turn, tight turn, stop, free push below grip speed. The gait
re-guesses the same thing from finite-differenced velocity. Instead, expose the
classification as a pure function of (velocity, move intent, brake, facing) —
all already replicated — and animate from it:

| State | Physics condition | Leg cycle |
|---|---|---|
| GLIDE | no input above grip speed | both blades down, weight on edges |
| STRIDE | input along travel | the existing stroke cycle |
| CROSSOVER (L/R) | sustained edge turn while striding | outside over, inside under |
| TIGHT_TURN | brake, stick off travel | dug edges, inside lead, no stride |
| STOP | brake, stick in line or behind | hips across travel, scrape |
| SKID | input against travel | blades planted, fighting momentum |
| BACKWARD | travel behind facing | C-cuts |
| BACKWARD_CROSSOVER | backward with a sustained turn | backward crossovers |
| SHUFFLE | below grip speed, lateral intent | side-steps |
| PIVOT | twist limit reached in the band | the mohawk transit |

States crossfade with weights that **sum to 1**. A state owns its legs outright
while it holds weight, so nothing needs a fade against anything else.

The stroke mathematics in the current gait — stroke skew, abduction, knee
fore-aft compensation, cadence gears — is good and gets ported into the states
that use it, not rewritten. What gets deleted is the intent-channel layer on
top of it.

## §6 Overlays as layers with priority

Shots (load, kick, hip coil), the check commit, the block, the faceoff stance
and address, knockdown, stagger and celebration become **layers**. Each layer
has a body mask (legs / spine / arms), a priority and its own blend, composed
over the locomotion pose in a fixed order.

Their authored content mostly survives; what changes is that they stop being
additive offsets on shared channels. Two existing physics-rate pieces stay
where they are, because gameplay reads them: `CheckStanceRules` (the loaded
shoulder moves the blade) and the block's gameplay pose.

## §7 Invariants, as tests

On the live rig, in the style of `test_check_stance_rig.gd`:

- PELVIS and thigh roots share one frame (structural — the test pins the
  hierarchy).
- **Cursor sweep:** head excursion across the travel line, measured relative
  to the pelvis, stays under a bound, across the full twist range at speed.
- **Steering wiggle:** bank amplitude at 2 Hz and 4 Hz stays under a bound.
- **Reach budget:** visible shoulder to gameplay hand never exceeds arm
  length plus a small slack.
- Every joint stays inside its range of motion across the pose set.
- Determinism: the gait reads nothing that is not replicated, and the
  gameplay frame reads nothing from the visual chain.

`render-poses.sh` keeps the visual side honest; the wiggle poses gain a
mid-wiggle tile.

## §8 Phases

Each phase is its own commit series, pushed for local testing at the end. The
pose capture baseline is recorded from the pre-change tree at the start of each
phase.

| Phase | Work | Visible result |
|---|---|---|
| 1 | §1 + §2: the gameplay/visual split, one skeleton, the chain, lean-then-twist, twist limit | The cursor tilt and the hip slide are gone |
| 2 | §4: balance-and-inertia posture | The steering-tap flail is gone; turns, stops and starts lean from physics |
| 3 | §5: locomotion states replace the channel layer | Coherent legs in every gait and every transition |
| 4 | §6: overlays move onto the new rig | Shots, checks, block, faceoff, knockdown on one model |
| 5 | Native port with a new parity fuzz; the old coordinator and its native mirror deleted; CLAUDE.md sections rewritten | Performance back; the old system gone |

The C++ gait mirror doubles every iteration, so during phases 1–4 the new gait
runs in GDScript only. The render-rate gait cost is real: measure it with the
benchmarks at each phase, and if GDScript alone is over budget with ten
skaters, bring the port forward rather than letting it slide to the end.

## §9 Decisions needed

1. **Twist limit** — shoulders against hips before the hips must follow. The
   current cap is 67°; a real skater's comfortable range is closer to 45–60°.
   Proposal: 55°.
2. **Fore-aft lean** — purely balance-derived, or balance plus an authored
   skating-posture floor? Proposal: posture floor plus balance (a coasting
   skater still crouches).
3. **Head** — fully level (counter-rolls the whole bank) or partially
   stabilised? Proposal: counter-roll about two thirds of it, so the head
   still reads the lean.
4. **Bank cap** — keep 30°?
5. **Gameplay frame (§3)** — do the crouch-drop removal in Phase 1 (proposed),
   and leave the velocity lean's frame bug for its own gameplay decision?
6. **One skeleton** — merge the two now (proposed), or keep two skeletons
   reparented into the chain and merge later?

## §10 Bugs found along the way

Fixed after Phase 5:

- **The crouch drop left the gameplay frame** (§1, §3). The gait computes it at
  render rate, so the skating crouch and its stride bob now lower only the
  visible body (`Skater.body_drop_below_frame`, applied at the HIPS bone) and
  the hands and blade hang from a frame that holds its height at any frame rate.
  A gameplay change, chosen: the top hand sits at standing height while
  skating, up to ~7 cm higher than when it rode the crouch, which moves the
  carry pin, the pickup claims and the stick-lift test by as much. The held
  poses — block, faceoff set, knockdown — still take the frame down with the
  body by their weight (`GaitPose.frame_share`), because their hands are posed
  for it; they are steady poses and interactions are mostly gated in them.
  The "visibility-gated" half of the old note did not hold: the gate is
  `is_visible_in_tree`, which only hidden skaters fail.
  `test_crouch_leaves_the_gameplay_frame.gd`.

- **The knockdown fall pivoted at the hips.** `MeshRoot` tipped about the
  skater origin, which rides 1 m up, so a body lying on the ice lay there at
  hip height — measured 0.93 m for the pelvis. It now tips about the ice under
  the origin (`Skater.set_knockdown_fall`); `test_knockdown_lies_on_the_ice.gd`
  holds it, and the pose set has three knockdown tiles.
- **The knockdown put the skates through the ice** — 0.20–0.28 m at worst,
  measured on the skate mesh, from the hit to the get-up. Three causes, three
  fixes. The buckle held a level boot but solved the shin as a straight
  segment, so the foot's 0.10 m forward offset swung down under it
  (`buckle_angles` now pays `GaitPose.FOOT_FWD`'s share); the ankles did not
  give the buckle back, so a 48° shin fold drove the toes in (the overlay now
  levels the boots); and the get-up scaled the solved angles rather than
  re-solving for the drop still applied (`SkaterController
  .knockdown_pose_weight` is now the one share both read). What tipping does is
  a constraint, not a pivot choice: a leg whose skate ends up below the ice
  swings about its hip until the skate rests on it
  (`SkaterLegRig._rest_on_ice`), so the leg the body tips over stays planted
  and the legs it lies on lie on the ice. Tipping over the skates' edge instead
  was tried and rejected — it holds the lying body up by the edge's distance,
  0.2–0.3 m. Left: on the hardest sideways hit the pinned leg folds its skate in
  by a hip joint that itself lies at the ice, ~3 cm under, beneath the body.
  `test_knockdown_lies_on_the_ice.gd`.
- **The bottom arm was drawn stretched** — 1.06× its length at rest, 1.40×
  with the stick out in front, 1.75× in a cross-body reach. Not the trunk work
  (visible and gameplay shoulders agreed within 0.07 of an arm): the bottom
  hand sat a fixed quarter of the way down the shaft, 0.69 m under a 0.66 m
  arm, and `_pose_bone` scales the forearm to whatever span it is given. The
  grip now slides up the shaft to stay within reach of the shoulder the arm
  hangs from (`BottomHandIK.reachable_grip`), lets go of the stick when none of
  it is in reach, and the shoulder girdle gives up to `Skater.shoulder_reach_m`
  toward a reaching hand, cap and all (`TwoBoneIK.reach_root`). This is the
  §1 reach budget: `test_arms_reach_their_hands.gd` fails any pose that draws
  an arm bone longer than it is (2.47× without the fix).
- **Reconcile squared the hips.** It wrote the facing lag alone to the lower
  body, dropping the gait's yaw channels (up to 40° of hip alignment at a
  stride off the facing) until the next tick; it now publishes through
  `apply_lower_body_yaw`. `test_reconcile_keeps_the_gait_yaw.gd`.
- **The slapper wind-up dropped its posture.** It skipped `_apply_lean`, so the
  shooter's torso sat at the zero written on entry while a remote re-derived a
  skating lean plus a reach lean off the authored wind-up hand — about 24° apart
  measured. Both sides now keep the posture (skating lean, stagger reel) with
  no reach lean. The puck is pinned to the body during the wind-up, so it reads
  none of this. `test_slapper_wind_up_lean.gd`.

## §11 Phase 1 as built

- **One skeleton, three joining bones.** HIPS (legs), WAIST (the pelvis/shorts)
  and SPINE (the shell), posed by `SkaterSpineRig`; arms are root bones solved
  in skeleton space. See `Scripts/actors/CLAUDE.md`.
- **WAIST was not in the design.** With the pelvis on the hips and the jersey on
  the spine, the whole twist showed as one seam at the hem, and the pelvis's
  wide flanks poked out through the jersey. The waist takes half the twist, and
  the pelvis rings above the hem were narrowed so their wide axis fits the
  jersey's deep one at the remaining angle (`test_pelvis_fills_the_seat.gd`).
- **Measured.** Cursor swept at 9 m/s: head drift across the travel line off the
  pelvis ±0.18 m → ±0.05 m (`test_body_chain.gd`). Arm stretch from the visible
  shoulders matches stretch from the gameplay frame's within 0.03 of arm length
  in every pose of the capture set, so the reach budget is not a constraint.
- **The crouch drop stays in the gameplay frame** (§3, Q5). Taking it out is
  not gameplay-neutral — the top hand's world height feeds the stick-lift shaft
  test and the pickup reception normal — and the worry behind it was measured
  and does not hold: across 60, 120 and 240 fps the gameplay frame's height
  differs by at most 2.9 mm (of a 72 mm crouch) with physics bit-identical.

## §12 Phase 2 as built

- **One lean, from acceleration.** `BalanceRules` gives atan(|a|/g) toward the
  horizontal acceleration and an exactly-solved critically damped spring
  (ω 7 rad/s). It replaced the gait's turn bank (legs, drop and trunk) and its
  acceleration-driven trunk pitches — effort dig, dig-in, reversal, the stop's
  trunk roll. Sprint's forward lean stays: it is posture, held after the
  acceleration is gone.
- **No BANK bone.** §2 put the pivot at the blades. The skater's origin is the
  centre of mass, which carries the collision body, so pivoting at the ice
  would carry the visible pelvis half a metre off it in a hard turn. The lean
  goes on HIPS, about the hips, with the drop that keeps the blades on the ice.
- **Angulation.** The trunk keeps 60% of the lean, which keeps the shoulders
  near the stick — reach from the visible shoulders stays at or under the
  gameplay frame's in every pose — and NECK takes back two thirds of that.
- **Measured.** Steering taps a quarter second apart at 9 m/s: the trunk
  swung +24° / -14° before; the balance lean now stays under 10° once the
  first tap's step has passed, and a held hard turn reaches its balancing
  angle. `test_body_chain.gd` holds both and the head's share.

## §13 Phase 3 as built

- **`LocomotionRules.classify`** splits the stick against travel exactly as the
  movement model resolves it — cos² along (stride), sin² across (crossover),
  cos² against (skid); brake by the tight-turn weight (tight turn / stop);
  below grip speed against facing (start, side-step, backward push); travel
  behind the facing is backward skating. Weights sum to one by construction.
- **`SkaterLocomotion`** owns the states: their easing, the shared stride
  phase (cadence is each state's own rate, weighted), and each state's stroke,
  ported from the old gait's stroke maths. The coordinator went from 1628 to
  916 lines; the dig-in, reversal, shuffle, backpedal, carve-intent and glide
  channels, the effort-hysteresis stop latch, and their fade factors are gone.
- **Not in the design: the signed crossover commit.** The split makes a
  steering tap at speed a crossover — the physics does turn the travel — but a
  skater corrects on the edges and crosses over only through a held turn. The
  crossover eases in slower than the other states and with its side as the
  sign, so taps alternating sides cancel; the uncommitted share is skated as a
  glide. Measured: taps a quarter second apart commit under 0.3 (they swung the
  skates ±0.3 m on alternating crossovers before); a held arc commits past 0.6.
- **Native gait retired early.** `NativeSkaterGait` mirrored the gait this
  phase replaces, so it and its parity fuzz are deleted rather than left
  pinned to dead code; its benchmark was already broken. Measured GDScript
  cost: ~46–56 µs per skater per frame skating (native was ~20), about 0.5 ms
  a frame for ten skaters until the Phase 5 port.

## §14 Phase 4 as built

- **`GaitLayer`** (`Scripts/controllers/gait/`): one class per overlay — faceoff,
  shot, check (commit and drive), stick lift, celebration, stagger, block,
  knockdown — each owning its clock, its blend and its reset, advanced from
  replicated state. The coordinator runs them lowest priority first through
  five stages (hold, floor, legs, trunk, override) over a scratch `GaitPose`,
  which owns the stance and knee solve. Each layer declares its stages once,
  and `advance` reports whether it contributes this pass, so an idle layer's
  stages are never called. The coordinator went from 916 to 455 lines and
  keeps the alignment, the pivot and publishing.
- **The masks are the overrides.** An additive layer lays offsets on what is
  beneath it; an override lerps the channels it owns toward its own pose, which
  takes everything beneath with them. That replaced the hand-written
  `(1 − kd_t)` factors scattered through the old pass with one rule.
- **One behaviour change, on purpose:** the knockdown now owns the trunk
  texture too. Before, a downed skater sliding at speed kept the stroke's trunk
  sway, and the check drive's and stick lift's leans, under the fall; only the
  commit was suppressed by hand. `test_gait_layers.gd` fails without it.
- **Not moved:** the upper-body overlays (the shot coil, the follow-through
  blade, the celebration's raised stick, the block's torso lean) and
  `CheckStanceRules`. They move the gameplay frame or the blade, so they stay in
  the pose coordinators at physics rate, as §6 planned.
- Verified by a pose render against the Phase 3 baseline: all 27 poses
  identical.
- **Cost:** the micro-benchmark's skating row went from ~41–45 µs to ~46–48 µs
  per skater per frame, and the settled row from 1.7 to 3.3 µs (eight quiet
  checks where there was one inline expression). No allocation; the Phase 5
  port takes this path with it.

## §15 Phase 5 as built

- **`NativeSkaterGait`** ports the numeric core in one kernel: `SkaterLocomotion`
  with the rules it calls, the coordinator's alignment and pivot read, and the
  `GaitPose` solve. The overlay layers were not ported — idle most frames, and
  where the feel tuning lives — so a pass a layer shapes mirrors the port's
  stroke back and solves the pose in GDScript. Results cross the boundary as a
  few `Vector4`s: a native getter costs ~0.14 µs against ~0.03 µs for a
  GDScript field read, so copying the locomotion's thirty fields back would
  have spent much of what the port saves.
- **Parity at the coordinator, not the kernel.** Two coordinators share one
  capture skater, one native and one forced to GDScript, and every published
  output is compared every pass through fuzzed skating, pivots, every overlay,
  resets, the settle and a reconfigure. Worst difference 2.6e-7 (the float32
  of the `Vector4`s); three planted bugs (the pivot law, the skid's stance, the
  stop's split sign) each fail it within a few hundred passes.
- **Cost, skating, per skater per frame:** 46 µs GDScript → 21 µs native, of
  which the rig writes are ~15 (gliding 36 → 17, hockey stop 32 → 13; a pass a
  layer shapes 63 → 30). The old native gait was ~20.
- Render against the Phase 3 baseline: 26 poses identical, `turn_tight_exit`
  3 px (the float32 rounding, over the longest held sequence).
- Also corrected: the ARCHITECTURE sections that still described two skeletons.

## §16 The lean in the gameplay frame (pivot at the skates)

Decided after Phase 5: the balance lean pivots at the skates, not the hips, and
the hands and stick lean with the body. Measured before: skating a hard turn the
pelvis and chest sat exactly on the skater's position while the skates swung
0.40 m out — the legs swinging round a still torso.

A lean that pivots at the ice carries the shoulders ~0.5–0.65 m into the turn at
the 30° cap, and the hands hang from the `UpperBody` frame, so the frame has to
go with them. That makes the lean gameplay:

- **The lean moves to the physics tick.** `SkaterController` steps the balance
  spring in `_process_input`, right after `_apply_movement`, from that tick's
  own acceleration — the velocity change the movement model made, so a body
  check's impulse (applied after the tick, in the skater's integration) never
  enters it and needs no snap filter. Reconcile replay re-runs it for free.
- **The frames TRANSLATE, they do not tilt.** `LowerBody` moves where the hips
  go when the rod tips about the ice under the skater; `UpperBody` moves where
  the shoulders go when the trunk keeps `trunk_lean_share` of the lean on top.
  Both keep their bases, so every IK assumption about an upright frame — the
  blade landed on the ice from the frame's height, the lean-corrected blade Y —
  still holds. The blade is placed blade-first from the cursor, so it stays
  where the player aims; what changes is reach, measured from a shoulder that
  has moved into the turn. `Skater._apply_body_height` stays the one writer of
  both frames' positions.
- **The visible body pivots at the ice too.** `SkaterSpineRig` seats the hips
  at `LowerBody` (now shifted) and tips them by the full lean; the legs hang
  from the hips, so the skates land back under the skater.
- **On the wire.** The blade and top hand travel `UpperBody`-local, so every
  machine must place the frame identically: `balance_tilt` (and its rate, for
  the reconcile baseline) join `SkaterNetworkState`, four s16 —
  `PROTOCOL_VERSION` 60, replay `FORMAT_VERSION` 8. Remotes interpolate the
  tilt; the local reconcile snaps tilt and rate to the host's and replays.
- **Claims.** The host bounds a claimed blade by `max_blade_reach` around the
  body; a leaned shoulder reaches further toward the turn, so the bound grows by
  the largest shift the lean cap allows.

As built, measured on the same hard right turn as before (28° of lean): the
skates sit 0.07 m off the skater's position (0.40 m before), the chest 0.50 m
into the turn, and the visible shoulder within 0.14 m of the gameplay one the
hand hangs from. `test_lean_pivots_at_the_skates.gd` holds the pivot, the
blade on the ice, a body check not entering the lean, and a receiver
rebuilding the frame and blade from the wire; the codec and reconcile suites
hold the new fields. The torso's own pitch and roll followed (v61): receivers
used to re-derive them by snapping to the targets the simulator eases toward,
which in a hard turn put a remote's torso ~0.15 rad and its blade ~18 cm off.
The pose coordinator's smoothed reach lean and posture now replicate (3 × s16),
are adopted on reconcile, and the rebuild test asserts the receiver's torso
within 0.001 rad with no hand-matching. The body check's recoil direction
followed (v62, one byte): remotes had reeled every plain stagger backward, and
a knockdown guessed its fall direction from the slide velocity.

**Retuned after the first playtest of it.** The lean read as rigid: nearly
every real push drives atan(|a|/g) past the cap, so with a hard 30° cap and
ω 7 it sat at the ceiling within 0.6 s of any start, turn or stop, and
side-to-side steering at 1.7 Hz rocked it 11° → 1° → 11° through upright on
every switch. It is now ω 4 (a held lean arrives in ~1 s) into a 20° cap
eased softly (cap · tanh(angle / cap)), so a harder push still leans further.
Measured on the same moves: a start builds 1 → 13° over 0.6 s, a held turn
17° after a second, steering at 1.7 Hz shows 1–4°, and the shoulders' largest
shift into a turn falls from ~0.6 m to 0.44 m (`Skater.max_lean_shift`, which
the claim reach bound follows).
