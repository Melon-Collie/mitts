# Skating stroke rebuild — plan

Status: **agreed.** The §9 decisions were taken as proposed, with one change:
the C++ port waits until every phase has landed, so the native gait retires at
the start of Phase 1 rather than Phase 2. Deviating from this version means
asking first (CLAUDE.md).

Follows `docs/skater-animation-plan.md`, whose rebuild gave the body one chain,
a balance lean and locomotion states, and explicitly kept the stroke maths
("the stroke mathematics … is good and gets ported"). This plan is about that
stroke: what the legs do inside a state, and which state is skated when.

## Why

Measured with the live rig (`tools/gait_strip.gd`, which renders a scenario as
a strip of frames from behind, beside and ahead of the skater and prints the
locomotion mix at each), skating up-ice at ~10 m/s and through turns:

1. **The stride is a fore-aft scissor.** From behind the skates never leave hip
   width (~0.26 m apart): the stroke is `stride_pitch_deg` 10° fore-aft with a
   10° "V" flare, so it reads as jogging. A skating push goes out to the side
   and back — external rotation and knee extension at push-off, wider strides
   separating fast skaters from slow — with the recovery returning the skate
   under the body.
2. **Crossovers never cross.** Holding a right turn with the stick 45° off
   travel (turning ~60°/s, driving) the mix settles at **0.51 stride + 0.45
   crossover**. The crossover's 24° roll at half weight moves the outside skate
   ~0.14 m inward — not past the other skate — so the legs shuffle side by side
   with a muddle of two patterns.
3. **The states fire on the stick, not on what the skater is doing.**
   `LocomotionRules.classify` splits the stick against travel as cos² stride /
   sin² crossover. But `SkaterMovementRules.apply_movement` turns at the FULL
   edge rate for any stick off travel and thrusts by `stick · cos(angle)`. So:
   - stick perpendicular (holding D at speed): **zero thrust**, the skater coasts
     round on the edges — and the gait shows up to **0.67 crossover**, power
     strokes while not pushing;
   - stick 45° off: turning flat out *and* driving at 71% — shown as half a
     crossover;
   - steering taps every 0.25 s: a churn of ~0.4 glide / 0.5 stride / up to 0.24
     crossover.
4. **The joints are authored, not the feet.** Contact had to be bolted on
   afterwards (`SkaterLegRig.seat_on_ice`), and holding a striding foot on the
   ice fought the stroke's geometry so hard (0.4 rad of knee correction a
   stroke, 30 rad/s thigh peaks) that the plant is now limited to two-footed
   stances. The blade tilts with the shin (rigid ankle), so where a skate meets
   the ice is a side effect of three summed angles. Every shape problem above is
   hard to fix in joint space for the same reason: the eye reads where the
   skates go, and nothing authors that.

## Goals

- Each state is authored as **where the skates go** relative to the body over
  the stroke, and a leg solve turns that into joints. The shapes in §2 become
  directly tunable and checkable.
- The state skated is **what the physics is doing**: driving, turning, both,
  neither (§1).
- Blades on the ice by construction, lifted only where a state lifts them.
- **Zero gameplay and wire change.** Everything stays derived from replicated
  velocity, intent, brake, stance and lean; the gameplay frames and markers are
  untouched.

### Non-goals

- No change to the skating physics, the shot/check/block/faceoff overlays'
  behaviour, the arms, or the trunk.
- No animation clips; still procedural.
- The goalie's stride is out of scope.

## §1 Which state: driving × turning

Two physical quantities, both already derivable from replicated state:

- **Drive** `d = max(intent · travel, 0)` — the share of full thrust the stick is
  asking for along travel, exactly the `par` the movement model thrusts by.
  Its negative part is the skid, as now.
- **Turning** `T = speed · |turn_rate| / (turn_accel · grip)` — how much of the
  edge's available lateral grip the body is actually using, from the measured
  turn rate (`SkaterLocomotion`'s finite difference) against the same grip the
  movement model turns with. 0 on a straight, 1 on a full-lock arc. Read off the
  motion rather than the stick, it is zero the instant the travel stops curving,
  however the stick is held.

The mix, weights summing to 1 as now:

| state | weight | what it is |
|---|---|---|
| STRIDE | `d · (1 − T)` | driving straight |
| CROSSOVER | `d · T` (signed, slow commit as now) | driving through a turn |
| CARVE (new) | `(1 − d − skid) · T` | turning without driving: both blades on edge, inside skate leading |
| GLIDE | `(1 − d − skid) · (1 − T)` | coasting straight |
| SKID | `skid` | pulling against travel |

Brake → STOP, the stance (Shift) → TIGHT in place of CROSSOVER/CARVE, backward
travel → BACKWARD, below grip speed → the free-push split — all as now.

The crossover keeps its signed, slow commit so steering taps cancel; what is not
yet committed is skated as CARVE (edges), not as stride. Expected on the
measured scenarios:

| input | today | proposed |
|---|---|---|
| 45° stick, sustained arc | 0.51 stride + 0.45 crossover | ~0.7 crossover + ~0.3 carve |
| D held at speed (no thrust) | up to 0.67 crossover | carve, crossovers growing as travel comes round and thrust returns |
| taps every 0.25 s | glide/stride/crossover churn | stride with carve on each tap, no crossover |

`classify` is mirrored in C++; see §6.

## §2 Where the skates go

Each state is a **foot path**: per skate, as a function of stroke phase and the
state's drive, a position on the ice in the travel frame (lateral, fore-aft),
a lift off it, a blade yaw (toe in/out) and an edge (roll). States blend in that
space — a foot halfway between two states is halfway between two places, never
two angle sums fighting.

Targets below are starting points for review, not tuned values. Reference
figures are thin (§10): the literature agrees on direction (wider, deeper,
external rotation and knee extension at push-off) more than on numbers.

**Stride.** Support skate under the hips, knee deep. The pushing skate leaves
from under the body and drives **out and back** on its inside edge, toe turned
out, the knee extending through the push: at full drive it ends ~0.45–0.55 m
out from the midline and ~0.25 m back (stride widths of ~0.53–0.74 m reported
for fast skaters against ~0.45–0.52 m for slow). Recovery lifts it a few cm and
swings it in and forward close to the ice, landing under the hips. The push is
the fast phase (the existing skew). Lower drive shortens the push; gliding at
cruise is the same path with a long dwell.

**Crossover** (described for a right turn; mirrored for left). Two beats over
the two-step cycle, both skates on right edges (left on its inside edge, right
on its outside):
- *under-push*: the inside (right) skate pushes from under the body out to the
  left, **beneath** the left skate's line, extending;
- *over-step*: the outside (left) skate lifts, crosses **in front of** the right
  shin and lands to the right of it; the right skate recovers from behind,
  stepping back out to the inside.

The checkable property: during the over-step the outside skate's lateral
position passes the inside skate's — it crosses. Cadence stays per radian of
heading change, as now.

**Carve.** Both skates down, on edges by the lean, inside skate leading by
~0.15–0.25 m, feet about hip width, knees deep. This is also the crossover at
zero drive, so the two blend without a seam.

**Glide.** Both down, hip width, the existing lazy edge sway.

**Backward (C-cuts), shuffle, tight turn, stop, skid.** Ported as paths with
today's intent: the C-cut draws a C out front; shuffle steps with a lift; the
tight turn digs both edges, inside leading; the stop turns the hips across
travel with the front leg braced and both blades scraping.

## §3 The leg solve

Per leg, analytic two-bone IK from the hip joint to the skate:

- **Frame.** Targets are authored in the hip-yaw frame on the ice (travel
  aligned, as the legs already are via `travel_align_yaw`). The gait tilts them
  by the replicated balance lean before solving, so a skate on the ice stays on
  the ice while the body goes over it. The crouch is the hip height the state
  asks for; the leg solve reaches down to the ice from there.
- **Joints out.** Hip pitch, roll and yaw (yaw from the blade's toe direction),
  knee fold, and the ankle's give-back that sets the blade to its authored edge
  and flat along its length. These are exactly today's channels
  (`GaitPose.l_pitch` … `foot_flat`), so `SkaterLegRig`, the native rig writes
  and every overlay downstream are unchanged.
- **Knee direction.** The knee bends toward the toe, out over the skate (the
  external rotation the literature finds at push-off), never inward.
- **Reach.** A target past full extension is clamped along the hip→foot line —
  the leg straightens and the skate falls short; the seat (below) still puts the
  support on the ice.

## §4 Contact

Authored lifts make contact the default, not a correction. The seat
(`seat_on_ice`, lower blade on the ice under the lean and the overlays) stays as
the guarantee for whatever the overlays add. The second-foot plant
(`_plant_feet`, the knee re-solve) is expected to become redundant for
locomotion; Phase 5 measures it and removes it if the residual is under the
contact tolerance.

## §5 Overlays

Unchanged: they lay joint offsets and overrides on the solved pose, as now
(`GaitLayer`'s LEGS / OVERRIDE stages). The faceoff address's splay and stagger
and the stance layer's width are natural follow-ups to author as foot positions,
but not part of this plan.

## §6 Native and cost

`NativeSkaterGait` ports the classifier, the strokes and the pose solve today,
and `test_native_gait_parity.gd` fuzzes it against the GDScript. As in the
animation rebuild, the native gait is **retired during Phases 1–4** (GDScript
only — measured ~+25 µs per skater per frame skating, ~0.25 ms a frame for ten)
and re-ported in Phase 5 with a new parity fuzz. The leg solve is a handful of
trig per leg; the target is to finish at or under today's native skating cost
(38 µs per skater per frame, minimum of three runs).

## §7 Invariants, as tests

- **Classifier table:** for each scenario in §1's table, the dominant state.
  Pure, in `tests/unit/rules/`.
- **Stride width:** at full drive the pushing skate reaches at least the target
  lateral extension, measured on the live rig's skate bones.
- **The crossover crosses:** in a held arc the outside skate's lateral position
  passes the inside skate's each over-step.
- **Contact:** `test_blades_stand_on_the_ice.gd` as now (lower blade within
  6 mm, two-footed states both blades, no pops).
- **Push faster than recovery:** `test_gait_stroke_profile.gd`, re-pointed at the
  skate path.
- **Symmetry:** `test_gait_direction_symmetry.gd`; left and right turns mirror.
- **Parity:** rebuilt in Phase 5.
- **Strips:** `tools/gait_strip.gd` committed as the visual check, with the
  scenarios above, and its frames attached to each phase's review.

## §8 Phases

Each phase pushed for local testing at its end.

| Phase | Work | Visible result |
|---|---|---|
| 0 | `tools/gait_strip.gd` committed; baseline strips recorded | none |
| 1 | native gait retired; §1 classifier | crossovers only through driven turns; coasting turns ride the edges |
| 2 | §3 leg solve with every state's foot paths taken from today's strokes by forward kinematics (the framework, pose-identical) | none (strips identical) |
| 3 | §2 stride and glide re-authored | the wide, out-and-back push |
| 4a | §2 crossover and carve | crossovers that cross; carves on the edges |
| 4b | §2 stop and skid (§14) | a wide, dug-in stop on both edges |
| 4c | §2 backward, shuffle, tight turn | consistent turns and C-cuts |
| 5 | native re-port, new parity fuzz, plant solve measured and retired if redundant, docs | cost back |

Phase 1 stands alone and is the quickest win, which is why it goes first and
ships on its own for a playtest.

## §9 Decisions (taken)

1. **CARVE as its own state** (proposed), or skate undriven turns as GLIDE with
   the lean? CARVE costs one more state; it is what makes coasting turns and the
   uncommitted part of a crossover look like edges rather than a straight glide.
2. **Turning from the measured turn rate** (proposed) or from the stick angle?
   Measured is zero the moment the arc ends; the stick reads a lane change held
   one frame too long as a turn.
3. **Stride width at full drive:** ~0.5 m from the midline proposed. From the
   game camera width is what reads; too wide reads as speed skating.
4. **Retire the native gait during Phases 1–4** (taken; proposed as 2–4), accepting ~+25 µs
   per skater per frame on main until Phase 5, or keep both in step every phase
   (slower; every iteration twice)?
5. **Ship order:** Phase 1 alone first for you to feel (proposed), or hold it
   for Phase 3?

## §10 References

Hockey crossover kinematics are essentially unmeasured; the foot paths in §2
take the stride's direction from the biomechanics below and the crossover's
choreography from coaching material, and are to be judged on the strips.

- High- vs low-calibre stride (greater knee extension and external rotation at
  push-off, hip flexion throughout): Principal component analysis study,
  [sponet.de](https://www.sponet.de/sponet/Record/4069005).
- Fast vs slow skaters (stride width, leg spread, forward lean ~10° more):
  [The Coaches Site](https://members.thecoachessite.com/article/investigation-biomechanical-differences-between-fast-and-slow-skaters),
  [The Hockey News](https://thehockeynews.com/news/all-access/a-harmony-of-motion-what-sets-the-worlds-best-skaters-apart).
  Treat the widths as indicative: the summary does not give the sample.
- Backward crossover as alternating single and double support with lateral
  deviation from the crossing leg:
  [Marino & Grasse, ISBS](https://ojs.ub.uni-konstanz.de/cpa/article/view/1699/1601).
- Crossover technique (outside leg pushes round a circle, inside foot crossing
  under): [How To Hockey](https://howtohockey.com/forward-crossovers-basics/).

## §11 Phase 1 as built

- **The native gait is gone** until Phase 5: the C++ class, its parity fuzz and
  the benchmark's native row. Skating costs ~51 µs per skater per frame in
  GDScript against ~29 native.
- **Not in the design: the push is banded, not linear.** §1 weighted the
  crossover by the drive (`d · T`). Measured, a 45° arc — driving at 71% and
  turning flat out — came out half carve, because the coasting share was the
  stick's sine. The weights now say *whether* the skater pushes: from half the
  thrust (`LocomotionRules.DRIVE_FULL`, a stick 60° off travel) fully, easing to
  coasting below it by a smoothstep. How hard is the stroke's amplitude, which
  already follows the measured acceleration.
- **Not in the design: the cadence averages the stroking states only**, so a
  crossover sharing the mix with a carve keeps its tempo.
- **Not in the design: the turn's inside is the curve's sign.** §1 took the side
  from the stick. Once the travel comes round to a held key the stick lands on
  alternate sides of it tick to tick, and the tight turn and the carve swapped
  their leading skate every frame (0.41–0.44 rad hip steps, the legs visibly
  teleporting in stance turns). `turning` is signed, the side comes from it,
  and the carve and tight turn ease signed like the crossover, so a reversal
  slides through centre; the worst per-frame leg step through the keyboard
  reversals is now the standstill start's 0.09 rad. The lead is carried by
  travel's share of the hips' forward axis rather than its sign, which swapped
  the skates once wherever travel crossed the hips (stance, cursor ahead,
  W → W+A → A → A+S).
- **The carve's legs** are joint-space until Phase 4: inside skate leading
  (`carve_lead_deg`), the inside knee light, the stance floored at
  `carve_stance`, counted as an edge state for the ice marks and the plant.
- **Measured** on the strips (mix at 0.75 s into the input):

  | input | before | after |
  |---|---|---|
  | 45° stick, sustained arc | 0.51 stride + 0.45 crossover | 0.63 crossover + 0.35 carve, the carve the uncommitted part, still committing |
  | stick across travel (no thrust) | 0.89 crossover | 0.92 carve, 0.00 crossover |
  | D held at speed | up to 0.67 crossover | carve first, crossovers growing to 0.59 as thrust returns |
  | taps every 0.25 s | crossover up to 0.24 | crossover ≤ 0.14, each tap carved |

## §12 Phase 2 as built

- **The solve** is `LegIK` (`Scripts/domain/rules/`), analytic, in the rig's
  own parametrisation: the hip's YXZ euler and a knee fold about X. It works in
  scalars: `Vector3` is single precision, and near a straight knee the fold is
  the square root of the reach error. `test_leg_ik.gd` holds the round trip
  (5·10⁻⁸ rad worst over the gait's range) and the out-of-reach behaviour;
  `test_leg_ik_mirrors_the_rig.gd` holds the model against the live bones,
  build lengths included.
- **The target is the ankle, not the skate.** The boot's centre sits 0.10 m
  ahead of the shin's end, so near straight two knee folds reach the same boot
  position; the ankle has exactly one. Phase 3 authors where the skate goes and
  offsets it to the ankle by the boot.
- **Not in the design: the states still blend in joint space.** §8 has every
  state's foot path taken from its stroke by FK; FK is non-linear, so blending
  per-state targets would move any pose that mixes states, and the phase is
  defined as pose-identical. The ankle target is the FK of the blended joints.
  Phase 3 adds each re-authored state as a foot-space offset on that target,
  and Phase 4 empties the joint-space side.
- **Not yet: the lean tilt** (§3 *Frame*). Un-tilting targets moves the feet,
  so it arrives with Phase 3's targets on the ice.
- **The layers are unchanged**: their joint offsets land on the solved legs,
  and a layer's knee straightening (`GaitPose.extend_knees`) counter-pitches the
  thigh as the stroke's own knee does.
- **Measured:** every strip pixel-identical to Phase 1's, and the printed
  locomotion mix identical line for line.

## §13 Phase 3 as built

- **The stride** is a foot path (`SkaterLocomotion._stride_path`): per unit of
  stroke amplitude, the push leaves from under the hips and drives 0.28 m out
  and 0.20 m back, toe turning out 25°; the recovery lifts up to 5 cm (by the
  swing speed, so ~2.5 cm at cruise) and comes back in along the same line to
  land 0.05 m ahead of the hips; both skates shift 0.04 m under the body toward
  the support. The stroke's own phase, skew and cadence are untouched.
  Measured on the skates: 0.31 m from the midline cruising at 6 m/s, 0.45–0.53 m
  driving hard (the reach decides which), the push 2.2× the recovery's speed.
- **The glide needed nothing.** §2's glide — both down, hip width, the existing
  sway — is the stance with its joint-space sway, which it already was.
- **Not in the design: the stride decides its own crouch.** §2 asked for the
  push's width and the support's deep knee separately; a leg can only reach so
  far out at a given hip height, so the stride sits as low as its push needs
  (`GaitPose.reach_hip`, capped at `stride_sit_max_deg` 45°), and the reach
  eases in near full stretch so the knee slows into it.
- **Brought forward from Phase 4: the ice frame** (§3 *Frame*). The stride's
  targets are turned through the hips' tilt against the ice — the balance lean
  about the ice under the body, and the lower body's own pitch, which the plan
  did not mention and which mattered as much (8° of it raised a push 2 cm).
  Only the stride's share is turned, so the joint-space states keep their look
  until Phase 4.
- **The ankle** gained a second give-back (`SkaterLegRig.set_ankle_flatten`'s
  level weights): the blade laid flat along its length against the ice, its
  edge left as the leg rolled it. The stride aims the runner rather than the
  ankle at the ice (`GaitPose._runner_depth`), so an edged push comes down by
  what the edge takes off the boot. The pushing skate now rides within 0.1 mm of
  the ice through every push (`test_blades_stand_on_the_ice.gd`); on Phase 2's
  joint stride it floated 3.8 cm.
- **Fixed on the way:** the boot's forward offset scaled with the build in the
  gait's crouch maths, where the rig does not scale it.
- **Measured cost:** skating ~+30 µs per skater per frame over Phase 2 in
  GDScript (Phase 2 and 3 alternated in one session, ~70 → ~100 µs; the
  benchmark's run-to-run noise is ±10 µs): each stride leg is solved twice for
  its runner and the rig levels both blades. Gliding is within the noise. The
  Phase 5 port is where it comes back.

## §14 The stop, before 4b

Rendered from 6.5 m/s after Phase 3, the stop reads as standing sideways, not
digging in:

- **The feet stay close.** *Wrong, measured in 4b:* the skates were already
  0.37 m apart along the travel; from behind, the camera looks down that line
  and hides it. What did differ is below. (The hips turn across travel,
  `stop_yaw`, capped at 70°; the legs scissored 14° fore-aft and rolled 12°
  the same way.)
- **The edges barely bite.** The knees bend moderately and the shins stand
  near vertical, so neither blade goes far onto its edge. A stop sits back
  against the momentum over two hard edges, the front knee deep.
- **Contact is corrected, not authored.** The stop is where the second-foot
  plant made its largest knee corrections (up to 1.08 rad).

4b authors it as where the skates go, with Phase 3's machinery: both skates
planted wide along travel and flat on their blades, the crouch and spacing
set so the front knee sits deep, and the edges coming from the body sitting
back over planted feet (the ice frame) rather than a fixed roll — so the
deceleration lean digs them in. Both blades on the ice by construction leaves
the plant nothing to correct. The side latch and the hips' turn stay. The skid
(pulling against travel at speed) is the same family and goes with it.

## §15 Phase 4a as built

- **The crossover** is the stride's phase law on each leg, half a cycle apart,
  with landings and extensions of its own (`SkaterLocomotion._crossover_path`):
  the outside skate lands 0.30 m inside its hip and pushes back out 0.12 m past
  it, its recovery the over-step, lifted 8 cm and passing in front; the inside
  skate lands 0.05 m inside its hip and pushes 0.25 m under the body, recovering
  from behind. Measured through a held arc at 5 m/s: the outside skate crosses
  the inside one on every step, by up to 0.22 m.
- **Not in the design: which beats alternate.** §2's two beats are the two
  pushes, and they ride opposite halves of the cycle; the over-step rides the
  inside skate's under-push, as it does on the ice. The old joint crossover put
  the over-step and the under-push on opposite halves, and its test said so;
  the test now pins the pushes.
- **The crossing does not shrink with speed.** Its lateral reach is the
  stroke's engagement (intensity against the crouch's full-speed share), full
  well below top speed; scaled by intensity alone, a 5 m/s arc never crossed.
- **The carve** is both skates down at hip width, the inside one 0.20 m ahead
  (`carve_lead_m`); the bank puts them on their edges through the ice frame.
  The old inside-knee tuck went: both skates are on the ice.
- **Fixed on the way**, all in Phase 3's solve: the reach limit could drive a
  target's depth past the leg and collapse its reach out from under the hip
  (a 0.25 rad pop as a crossed skate landed), so the depth eases in first; the
  limit and the stride's crouch demand switched on with the authored share and
  popped a gliding leg as a stride faded, so both now move by that share; and
  the limit was pulling in near-straight joint-space legs it should never have
  touched.

## §16 Phase 4b as built

- **The stop** is authored as where its skates go (`SkaterLocomotion._stop_path`):
  both planted 0.10 m out past their hips along the travel and set 0.28 m
  toward it, so the hips sit back of both, the skate on the travel side 0.05 m
  ahead. The legs turn the blades the last of the way square across the
  travel that the hips' 70° cap leaves, measured in the frame the hips are
  turning to, so they never make up the turn still to come.
- **Measured** a quarter second into a stop from 9.5 m/s
  (`test_hockey_stop_pose.gd`), against the joint stop it replaced:

  | | before | after |
  |---|---|---|
  | edges | back skate −24°, front −9..+2° (the edges that catch) | +7..+23°, both dig |
  | blades off square to travel | 26–29° | ≤ 11° |
  | second-foot plant's knee correction | 0.70 rad | 0.05 rad |
  | apart along travel | 0.37 m | 0.35 m |

- **The skid** is a snowplow (`_skid_path`): skates 0.16 m out past their hips
  and 0.10 m toward the travel, toes in 20°, both blades on their inside edges
  (0.50 m apart, 8°+).
- **Not in the design: the stop's skates slide.** §3 has every authored skate
  turned back through the lean about the ice under the body, so it stays put
  while the body goes over it. A stop's skates scrape along with the body, and
  holding them put as the lean built pulled the hips off the front skate until
  it was out of reach. The stop and skid (`SkaterLocomotion.sliding`) keep
  their place under the hips; the lean only lays them level.
- **Not in the design: the blade's heading is the leg's yaw.** The level
  give-back laid the blade's length flat along whatever heading the chain gave
  it, and a bent leg's roll turns that heading; it now lays it along the yaw,
  keeping the edge (`SkaterLegRig._foot_pose`, `GaitPose._runner_depth`). This
  is §3's "yaw from the blade's toe direction", and it touches the stride and
  the crossover too.
- **Fixed on the way:** the reach limit measured depth and reach in the hips'
  frame; it now measures them against the ice (a leaned-back body otherwise
  read a front skate as too deep and pulled it in).

## §17 Phase 4c as built

- **Backward C-cuts** (`SkaterLocomotion._ccut_path`): each push sweeps out from
  under its hip and ahead of the hips — skating backward, the body moves away
  from it — bulging 0.20 m out and ending 0.20 m ahead per unit of amplitude,
  the toe out as the C starts and in as it ends; the return comes back close
  to centre with the blade still down. Both blades stay on the ice
  (`test_blades_stand_on_the_ice.gd`); measured, a C reaches 0.13 m past the
  hip and 0.22 m ahead (`test_gait_backward_and_sidestep.gd`).
- **The side-step** (`_shuffle_path`) scissors the skates sideways half a cycle
  apart, lifting each as it steps toward the travel. The lean into the step is
  the balance lean's, not a fixed roll. The classifier only side-steps from a
  dead start, so its test drives the path directly.
- **The tight turn** is the carve's shape with its own lead
  (`tight_turn_lead_m`), dug onto its edges by the bank.
- **The joint stroke is gone** (`_stroke`, the push extension and its knee
  release, and their tunables). What is left in joint space is the glide's edge
  sway and inside knee, and the overlays.
- **The runner correction runs three passes**: a C-cut tips its blades further
  than the stride, and two left the second blade 7 mm up.
- **The strip renderer** gained a `back` scenario (the stick held back with the
  cursor up-ice).
