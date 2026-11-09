# Held hands — gameplay hands a body can hold, drawn as checked

Status: PHASE 2 BUILT BEHIND A SWITCH (off), with the reach changes of §13. Not yet playable on the backhand in tight (§14).

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

## 11. Phase 1 record

### What was built

- **The model**: `SkaterHoldModel` (`Scripts/actors/`), a pure scorer of §6
  for a hand and a blade against a `Body`, and its brute-force sphere search
  (`search`), the reference phase 2's projection will be measured against.
  `SkaterIKCoordinator.fill_hold_body` fills the body from tick state;
  `SkaterArmRig.fill_drawn_trunk` replaces its trunk with the one drawn. The
  spine's turn in UpperBody's frame is `SkaterSpineRig.spine_in_frame`, which
  `shoulder_in_frame` now composes.
- **Tests**: `test_hold_model_mirrors_the_rig.gd` (the tick body against the
  drawn one) and `test_skater_hold_model.gd` (the model's properties).
- **Instruments**: `tests/instruments/actors/test_hold_map.gd` (bearing ×
  reach, standing and skating, and the swept carries), and
  `tools/hold_sample.gd` (a live 5v5 of bots, every skater every 30 ticks).

### What it found

**Nearly every hand gameplay places is one the drawn body cannot hold.**

| Where | Not held | Violation, median / 90% | Held hand on the sphere exists | Move to it, median / 90% / max |
|---|---|---|---|---|
| Map, standing (44 cells) | 33 | — | all 33 | 8 / 20 / 20 cm |
| Map, skating (44 cells) | 36 | — | all 36 | 16 / 40 / 40 cm |
| Live bots, carriers | 95 of 112 | 135 / 246 mm | all 95 | 10 / 20 / 40 cm |
| Live bots, everyone else | 1,309 of 1,418 | 167 / 291 mm | 1,258 (51 none) | 13 / 25 / 50 cm |

What binds, in live play:
- **Carriers:** the knob in the jersey (45), the top hand nearer its shoulder
  than an elbow folds (31), the fist in the jersey (18).
- **Everyone else:** the fist (676), the knob (280), the bottom arm's sleeve
  (229) and the fold (91).
- **Map, standing:** the fist through every close carry. Far round the
  backhand at 1.4–1.8 m, the bottom arm's sleeve.

What this settles:

- **Hands alone suffice.** With the blade fixed and the stick's lie kept
  within 15°, a held hand exists for every carrier sample and 96% of the rest.
  Decision B (§7) is close to moot. It matters only for the few non-carrier
  poses (the hand-first ones: shots, the block, the down poses) that no
  search reached.
- **The moves are large.** A median of 10–13 cm, and up to 40–50 cm, is a
  visible change in how the stick is held, not a nudge. Phase 2's smoothness
  is the whole question, and it is played, not just measured.
- **Letting the gloves push the jersey's cloth is not the fix.** The fist or
  knob is in the tail below the belt, with the rest of the pose held, in 1 of
  95 carrier samples and 18 of 1,309 others. The hands have to move.

**The tick's trunk is not the drawn one: it sits 3–10 cm too high.** Standing,
the model's shoulders and jersey are the drawn ones to 0.0 mm once a single
offset is taken out, and that offset is vertical: 3 cm standing upright, 8–10 cm
under the carry's chest fold. The gait's crouch and the hips' seat on the
blades lower the drawn trunk at render rate, and the tick never sees either.
Skating adds about 4 cm fore and aft, and the stride's texture turns the
jersey up to 3 cm further. So today's gameplay already places every hand
against shoulders a few centimetres above the drawn ones. Phase 2 needs a
trunk height the tick can derive (the posture's mean crouch and seat as a
function of tick state); without it, the projection would hold poses the
drawing does not.

### What changes for phase 2

- **A first step:** the tick-state trunk height, held to the drawn one by
  `test_hold_model_mirrors_the_rig.gd` with the offset brought inside its
  bound rather than taken out.
- **Then the projection,** judged by the jerk harness and a playtest before
  anything else. The brute-force search is its reference: the projection
  must reach a held hand wherever the search does, and move no further than
  it.

## 12. Phase 2 record

### The trunk's height: measured, deferred

The drawn trunk's height comes from the gait. `GaitPose.solve_stance` turns
the stance (the largest of the locomotion's eased stance, the pivot's, the
stride's reach sit and the layers' floors, among them the carry's crouch)
into a drop by the leg's geometry. `SkaterLegRig.seat_on_ice` then re-seats
the hips on the blades.

Measured against the tick's trunk, the offset is:
- **Standing:** a flat 3.0 cm lower with no carry, growing with the carry's
  crouch to 10 cm at the full 22° fold.
- **Skating:** 5.5–8.4 cm lower and 3.5–4 cm back, ±1.5 cm with the stride.

What it costs, with the held hand found on the tick's trunk and scored on the
drawn one:

| | as is | the tick's trunk lowered by the measured offset |
|---|---|---|
| standing | median 0, 90% 12, max 60 mm | median 0, 90% 1, max 2 mm |
| skating | median 0, 90% 22, max 26 mm | median 6, 90% 26, max 46 mm |

Standing, the height is the whole mismatch (the carry's crouch). Skating, it
is not a translation (the stride's texture and the trunk's lean), and
lowering the trunk makes it worse.

A faithful tick height means mirroring the gait's stance and the leg chain's
seat, which is native-ported code, to take a 90th percentile of 1–2 cm to
zero against violations of ~15 cm today. So the projection is built on the
tick's trunk as it is, and this is revisited if the playtest shows clipping
on standing carries (the carry crouch is its worst case).

### The projection, built behind a switch

`SkaterHoldModel.project` steps from the anchor. Each step moves the hand by
every limit it breaks, along the way out of that limit, by how far past it the
pose is, then puts it back on the sphere with the lie held within 15°. It
stops when a step moves the hand under 0.5 mm, at most 24 steps. It is the
position-based pattern `SkaterIKCoordinator._shaft_clearance` already used
for the drawn shaft alone.

Its tuning was measured, not chosen:
- **Iterations.** Six fixed steps chattered on the long moves (a 134 mm pop
  in a tick). Settled steps track the true answer.
- **No relaxation factor.** A move of exactly how far past each limit
  converges in about 7 steps, to 0.1 mm. At 0.7 it took 10 steps; at 1.3 it
  overshot to an 11–19 mm residual.
- **The bottom arm is scored where the drawing puts it**
  (`BottomHandIK.reachable_grip`), not at the best point of a band: one elbow
  solve, and the hand the eye sees.

It is wired in (`SkaterIKCoordinator.held_top_hand`, `Skater.shaft_hand`; see
`Scripts/controllers/CLAUDE.md`):
- **Drawing:** the held hand is an offset on the drawn hand, eased on the
  shaft clearance's spring.
- **Gameplay:** stick lifts and ties, the host's `top_hand_world`, the bots'
  stick reads and the tie's drawing take it.
- **Unchanged:** the marker keeps the blade's heading and everything derived
  from it.
- **Not applied:** shots, the block, down and diving skaters.

What it does (`test_hold_map.gd`, scored on the drawn trunk): violations go
from 150–200 mm to a median of 8 mm standing and 15 mm skating, 90th
percentile 22 mm. The rest is the trunk's height (§12, the carry's crouch,
up to 55 mm straight ahead at 1.1 m) and a few corners. Live, a plain close
carry's hand moves 27 cm.

What it costs and breaks, with the switch on:
- **Cost.** About 1 ms a call median and 5–9 ms at the 90th percentile in
  GDScript. A 6-skater match's tick went from 4.2 to 20.6 ms. Free play is
  fine; a match needs the native port.
- **Smoothness.** `test_body_stays_smooth.gd` passes every scenario but one:
  the forward→backward pivot with the cursor flipped, where the arm's jerk is
  18% over its gate and the stick's 4%. That pivot crosses the corner where
  the anchor is the hand on its own shoulder (skating, the puck behind the
  forehand), and the held hand there moves 3–7× the anchor's step: it is
  travelling 30–45 cm to somewhere holdable.
- **The look.** In tight carries the held hand clears the jersey by riding up
  the stick's sphere toward the chest, so the stick stands steeper and the
  top elbow can wing out (renders of `tight_sweep`). A limit holding the hand
  0.2 m under its shoulder (the withdrawn plan's technique) leaves no holdable
  hand in many tight carries, and conflicting limits made the projection pop
  (to 260 mm a tick), so it is not in. With the blade fixed close in and a
  full-length stick, "out of the jersey", "both hands on" and "the hand below
  the chest" cannot all hold. Something has to give.

### Decisions this needs

- **D. Tight carries.** Which gives: the hand rises and the stick stands up
  (what the switch does now); the stick is choked in close (the grip slides
  down the shaft, the knob past the hand grows, as the faceoff's choke does);
  or the in-tight reach floor moves out (gameplay, as the withdrawn work
  found).
- **E. The trunk's height** (above): mirror the gait's crouch and seat in the
  tick, or let the standing carry's crouch move the gameplay frame as the held
  poses already do.
- **F. The native port,** before the switch can be on in a match.

## 13. How close in a held blade can come

`tests/instruments/actors/test_tight_room.gd`: per bearing, standing and
skating, the cursor walked in from 1.6 m to the skates. Each blade is
searched for any top hand that holds it, with the shaft at the blade's own
lie (43.3°) ± a window, rather than round today's hand.

"Lost" is the closest blade a body holds against the closest the carry
brings it today (0.67–0.70 m from the body's centre), mean over bearings:

| lie window | standing | skating | worst bearing |
|---|---|---|---|
| ±15° | 0.16 m | 0.27 m | 0.37 m, skating in front |
| ±22° | 0.01 m | 0.09 m | 0.17 m, skating in front and round the forehand |
| ±30° | 0.05 m | 0.08 m | 0.26 m, skating straight ahead |

- **The height rule** (the top hand 0.2 m under its shoulder) costs nothing
  at ±15° or ±22°: at a flat-ish blade the hand already rides under the
  chest. The hand climbed in §12's projection because its window followed
  today's tight hand, whose stick already stands steeper than a flat blade
  allows.
- **At ±30°, without the rule,** a hand holds every blade today's carry
  reaches, but only by standing the stick at up to 73° with the hand at the
  chest. With the rule it loses more than ±22°.
- **Skating with the puck behind the forehand** (cursor at +120° or further
  round) no hand holds at any window. Today's blade there sits 0.05–0.62 m
  from the body's centre, partly under the skater.

Proposed, waiting on the user:
- **The held hand** keeps the shaft within ±22° of the blade's lie and the
  top hand under the chest.
- **The skating carry floor** becomes per bearing, about 0.15 m further out
  in front and round the forehand to about 75°. The standing floor is
  unchanged but for a few centimetres in front.
- **Skating, the carry** stops short of the forehand side behind the hip,
  where no hold exists.

## 14. The reach changes, built behind the switch

Taken, with the user's go-ahead on §13's proposal:

- **The held hand** holds the shaft within 22° of the blade's own lie and
  the top hand under the chest (`SkaterHoldModel.project`, `lie`,
  `HAND_BELOW_SHOULDER_M`).
- **The carry floor** grows across the front
  (`SkaterController.carry_front_floor_*`): 7 cm standing, 17 cm at the full
  skating fold, from 50° round the backhand to 90° round the forehand, faded
  over 15°.
- **The celebration** keeps the marker, as shots do.

Not taken: stopping the skating carry behind the forehand. §13's "no hold
there" was the instruments' doing. They aimed a skating cursor off the facing
every tick, so a cursor behind the skater ran round with him and he spun
after it. Aimed across the ice off up-ice, those blades sit 0.81–0.85 m out
at +107° to +113° and are held. (`test_carry_clipping.gd`, not part of this
work, aims the same way and was left.)

### Measured with the switch on

- **Tight room** (`test_tight_room.gd`, ±22°): today's floor against the
  holdable floor under the corrected aim needs +7 cm standing in front and
  +12–22 cm skating in front, the latter set by the height rule. With the new
  floor, room lost to a holdable pose averages 1 cm standing and 2 cm skating.
- **Hold map, scored on the drawn trunk:** median 0 mm standing and 1 mm
  skating, but the tail is long (standing 90th percentile 120 mm, max 201).
  That tail is the backhand in tight: the blade parked at the backhand stop
  (−67°, 0.68 m), where the only held hand is on the far side of the stick's
  circle, across the body at the top of the lie window. The projection steps
  from today's hand on the near side, the bottom elbow's push carries it round
  the near way, and it stalls with the bottom arm 115 mm short; the drawn
  bottom hand then lets go of the stick. In front, the residual left on the
  drawn body (13–14 mm) is the trunk's height under the chest fold (§12).
- **Smoothness** (`test_body_stays_smooth.gd`): over its gates with the
  switch on in five scenarios — the flipped-cursor pivot (top arm 17%, stick
  7%), the skating wrister's hand-off (14%), pickup/drop (7%), backward to
  forward (bottom arm 7%) — the held hand travelling further than the marker
  does. All pass with the switch off.

### What comes next

- **The far side.** A local projection cannot reach a held hand across the
  circle. It needs a second start there (the nearest held point of a coarse
  ring, `search_lie`'s), kept by hysteresis so it does not flip between the
  two each tick, and eased across when it does change.
- **A playtest** in free play to judge the look in front and at the sides;
  the backhand in tight will look worse than today until the far side is in.

## 15. The native port

`NativeHoldModel` (`native/src/native_hold_model.*`) runs `project` and
`evaluate`; the elbow swivel moved out of `NativeArmRig` into
`native/src/arm_swivel.*`, which both kernels hold, so the hold model's arms
are the arm rig's by construction. `held_top_hand` packs the tick's body
(`SkaterHoldModel.pack`) and calls it where the extension is built; the
GDScript is the reference and the fallback.

- **Parity** (`test_native_hold_model_parity.gd`, 400 cases off a live
  carrier's body, moved, turned, rescaled, the height rule on and off, 356 of
  them unheld, walks up to 1.04 m): every limit and the held hand equal to the
  bit. The arm rig's parity is unchanged by the extraction (worst 4.9e-5).
- **Cost** (`measure-frame-cost.sh 6`, two runs each, headless): the host's
  tick 2.54 ms off, 3.51 ms on — ~0.16 ms a skater a tick, against ~2.7 ms in
  GDScript, nearly all of it under capture and broadcast, where the tick
  first reads each skater's shaft. A far-side second start (§14) would add at
  most another projection's worth.

