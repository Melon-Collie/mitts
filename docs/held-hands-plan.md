# Held hands — gameplay hands a body can hold, drawn as checked

Status: PROPOSED.

One line: **the blade stays where gameplay puts it today; the hand that holds
the stick is moved, by the least that makes it holdable, by one pure body
model that the tick, every peer and the drawing share.**

## 1. Why

Measured on the elbow-swivel branch (`tests/instruments/actors/
test_arm_pose_quality.gd`, renders by `.claude/hooks/render-arms.sh`):

- The drawn elbow is no longer what reads wrong: the swivel
  (`SkaterArmPoses.swivel_bend`) takes the best elbow the circle allows. What
  is left is where the gameplay hands are.
- Tight backhand: the top hand sits ~0.2 m straight under its shoulder,
  against the ribs, inside the jersey's side. Every elbow on its circle is in
  the chest or raised 58–85° (the wing).
- Blade behind the backhand: the bottom hand is 0.65 m from a 0.66 m arm, and
  the straight arm's line runs through the chest.
- Skating sweeps: the top hand passes 6–15 cm from its own shoulder.

The drawn body and the gameplay hands disagree about what a body can do, and
the drawing loses.

## 2. What the withdrawn attempt taught

`docs/arm-anatomy-plan.md` solved the same anatomy, and its poses were judged
right on the reference sheets, but the carry it drove played "jerky and
bizarre". Its own record says why. Each failure becomes a rule here:

| What went wrong | Rule |
|---|---|
| A table of per-cell global optima: neighbouring blades picked different pose families, so the carry jumped between them | No tables and no global picks at play time. The held hand is a continuous function of tick state |
| It replaced the carry: the reach floor went 0.83 → 1.26 m, the dangle's face changed, bots' duels changed | The blade is untouched, and so is everything gameplay derives from the closed-form hand (§4) |
| Hands placed in a frame the drawn arm did not reach them in (arms drawn at 1.06–1.30 of themselves) | One body model. The tick and the rig call the same functions, and a test holds them together |
| Pickup and drop moved the hands in a tick | No regime the puck switches. Inputs that move continuously move the hand continuously |

## 3. The idea

Gameplay already chooses the blade (`TopHandIK`, the clamps, the stops) and a
hand as a consequence. That hand is the **prior**. Where a body can hold the
stick there, which is most of the time, the held hand is exactly the prior.
Where it cannot, the hand moves **over the sphere the rigid stick allows round
the fixed blade** to the nearest place it can be held.

The move is a smooth penalty, minimised in a fixed number of steps started
from the prior. It is not warm-started from the last tick, so the result is a
pure function of this tick's state. Prediction, reconcile replay and remotes
all derive the same held hand with nothing new on the wire.

Why this is smooth where the table was not:

- When no limit binds, the correction is exactly zero, so the hand is
  `TopHandIK`'s, which is already smooth and tuned.
- The penalties are squared hinges, with zero slope where they engage, so the
  correction grows from zero continuously as a limit starts to bind.
- A fixed number of steps of a continuous update from a continuous start is a
  continuous map. The outer solve takes no argmin over discrete candidates;
  the one inner minimum (the elbow's swivel) is continuous in its value even
  where its argmin switches.

This is the usual real-time full-body IK recipe: a few damped steps from a
good pose, with a stiffness per target (Unreal's position-based Full Body IK
works this way, and damped least squares in general). The difference is that
the good pose is the closed-form carry rather than last frame, which keeps it
replay-safe. The arm inside it is analytic, with the elbow's swivel as its one
free parameter (Tolani, Goswami & Badler 2000), which is what
`SkaterArmPoses.swivel_bend` already is.

## 4. Two hands: the anchor and the held hand

The top hand marker does two jobs today. It holds the stick, and it orients
the blade: `Skater.set_blade_position` turns the blade along the line from the
hand to the heel. That heading decides the contact point, the carried puck's
pin, the shot's release origin, the face a deflection leaves from, and the toe
clamps. The carry's target placement (`SkaterIKCoordinator._blade_target_for`)
and the pin (`Skater._carry_target_raw`) also cancel only while the hand
stays on the shoulder→blade line. Moving the marker would move every one of
those, and an uncancelled offset is a puck that creeps by itself.

So the two jobs separate:

- **The anchor** is today's closed-form hand, computed exactly as now. It
  stays on the wire as `top_hand_position`, and everything listed above keeps
  reading it: the blade's heading and contact, the pin, the release origin,
  the face, the toe clamps, and the reach lean (`SkaterPoseCoordinator`, which
  feeds `torso_lean` back into the frame). Puck feel, reach and the bots'
  `AISkaterCaps` do not change.
- **The held hand** is the anchor projected as in §3. It is derived from tick
  state every peer has, on every peer, and it is what holds the stick:
  - the drawn arm, shaft and knob;
  - the shaft line gameplay reads: stick-lift hook quality
    (`puck_controller.gd`, `StickLiftClaimResolver`), the stick-tie gap
    (`StickTieClaimResolver`, `StickTieTracker`), and the client's stick-lift
    claim edge (`LocalController`);
  - the host's `top_hand_world` (not serialized), which the rewound
    resolvers and the bots' stick reads (`skater_agent_stick_play.gd`) take.

The held hand and the anchor hold the blade at the same heel, so the shaft
line moves most at the hand end and not at all at the blade. Every move is a
continuous function of the pose.

Decision A (§9) asks whether the blade's heading should later follow the held
hand too.

## 5. The body model (one, pure, shared)

A domain class, computed from tick state only:

- **Shoulders**: the trunk's, as the tick already has them
  (`SkaterSpineRig.shoulder_in_frame`, then the address and the carry's chest
  fold, as `SkaterIKCoordinator.arm_shoulder` composes them), the bottom one
  read the same way.
- **Jersey**: `SkaterMeshBuilder.torso_clearance` in the torso's frame, the
  torso placed from the same tick state as the shoulders.
- **Arms**: `TwoBoneIK.reach_root` (the girdle's give), the swivel's costs
  (`SkaterArmPoses.swivel_cost`) and their minimum over the circle.
- **Stick**: rigid, `solve_stick_length`, the knob
  (`SkaterStickRig.SHAFT_BUTT_EXTEND_M`) past the top hand, the bottom hand's
  grip band from a glove's width (`_glove_spacing`) down.

The render-only inputs it does not see are the stride's hand pump, the trunk
texture's sway and the gait's hip yaw. Each is centimetres, the drawn arm
absorbs them, and a test bounds the gap.

The tick's existing two-hand reach (`TopHandIK.two_hand_reach`, from
`BottomHandIK.reachable_grip`) and the drawn bottom hand
(`soft_reachable_grip`) are two answers to one question. Phase 3 has both read
this model.

## 6. What "holdable" means

Each penalty is measured in metres or radians past its limit, and squared:

1. The top fist is out of the jersey, past the gear press (3 cm, the
   withdrawn plan's liberty).
2. The top arm reaches the hand within its working length plus the girdle's
   give.
3. The best elbow on the top arm's circle clears the jersey (the swivel
   cost's jersey term at its minimum).
4. The bottom arm reaches some point of the shaft in its grip band, and its
   best elbow there clears.
5. The knob is out of the jersey.
6. The hand is no nearer its own shoulder than a folded forearm allows (the
   6–15 cm cases).

A prior term, the distance from the anchor, makes the correction the least
that satisfies them.

## 7. Where no hand holds the blade

The withdrawn work found blades gameplay lands that no pose holds: 44 of 98
cells, mostly far round either side at 1.2–1.5 m out. With the blade fixed,
the penalties settle there on the least-bad hand, and the body clips by what
is left. There are two ways to answer that. Phase 1's map decides between
them; this plan does not:

- the body clips there, if it is rare and far round; or
- the blade's reach gives a little there, through a soft cap on the cursor's
  target the same shape as the existing stops, so the dangle's speed cap eases
  it in. It is never laid on the drawn blade. This one changes gameplay, so it
  is its own phase with its own playtest.

## 8. Phases

1. **Measure, changing nothing.** The body model as a pure class; a test that
   it agrees with the drawn rig (shoulders, jersey, arm) within millimetres;
   and an instrument mapping, round the body (bearing × reach × standing,
   skating, twisted) and over bot play, how often and by how much the anchor
   breaks §6, and whether a held hand exists on the stick's sphere that does
   not. Deliverable: the map and the frequencies.
2. **The held hand, behind a flag.** The projection, pure, a fixed number of
   steps from the anchor; the drawing and the shaft readers switched to it.
   Unit tests for each property in §3 (zero where free, continuous, holds
   where a hold exists, identical on replay); the jerk harness
   (`body_jerk_harness.gd`) and the arm sweep, before and after; a playtest.
3. **The bottom hand on the same model**, sliding within its grip band to
   where its arm holds it, at tick rate and drawn the same.
4. **Native port** inside the blade pass (`NativeBladePass`), with its parity
   fuzz, and a benchmark of the cost per skater-tick including replay.
5. **The reach where nothing holds** (§7), only if phase 1 says it matters.
6. **Held poses and shots** (the slapper's coil, the wrister's aim, the
   block, the commit stance) take the same projection where they need it.

Each phase is its own branch and PR. The flag stays off until phase 2's
playtest.

## 9. Decisions for the user

- **A. The blade's heading.** The plan keeps it on the anchor (§4), so puck
  feel is untouched. Moving it to the held hand is truer to the drawn stick,
  but it shifts the contact point by up to about a centimetre and needs
  `_blade_target_for` and `_carry_target_raw` rewritten onto one heading so the
  puck does not creep. Proposed: anchor now, revisit with phase 2's renders.
- **B. Where no hand holds** (§7): body clips, or reach gives. Proposed:
  decide on phase 1's map.
- **C. The trunk as a free variable.** If phase 1 finds cells where no hand on
  the sphere holds but a few degrees more twist or fold would, the projection
  could take the twist too. That changes `UpperBody`, which the blade is local
  to, so it is not proposed unless the map asks for it.

## 10. Cost

Per skater-tick, and again per replayed input on the local skater: one
evaluation of §6 when the anchor holds (expected to be the common case) and a
few steps when it does not, on every peer for every skater. The budget is set
from phase 1's frequencies and phase 4's benchmark.
