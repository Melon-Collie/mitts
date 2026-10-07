# Skater animation rebuild — plan

Status: **draft for agreement.** Nothing here is implemented. §9 lists the
decisions that need an answer before Phase 1 starts; deviating from the agreed
version means asking first, per CLAUDE.md.

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
  frame bug as §0, but *gameplay* geometry. It decides where the blade sits.
  Fixing it is a gameplay change (blade reach while the torso is twisted), so
  it is listed rather than assumed.
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

## §10 Bugs found along the way, not yet fixed

- The crouch drop writes the gameplay frame at render rate, visibility-gated
  (§1). Blade height may differ between machines; this is unconfirmed.
- The knockdown tilt rotates `MeshRoot` about the skater origin (hip height),
  while its comment describes a pivot at ice level between the skates.
- Reconcile writes `lower_body_lag` alone to the lower-body yaw, without the
  stop, alignment and shot channels, until the next tick rewrites it.
- The slapper wind-up path skips `_apply_lean` entirely, so the torso lean
  stays at the zero written on entry while the trunk texture keeps moving.
