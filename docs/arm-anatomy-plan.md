# Arm anatomy — every stick pose a body can hold, and the reach that follows

Status: APPROVED. Phase 1 (the model and its instruments) built; its record is
§12. Treat it as the agreed design; ask before deviating from it.

One-line summary: **one anatomical model of the trunk, both arms and the grip
decides whether a stick pose is possible and how it is held; hockey technique
narrows it where players do less than anatomy allows; gameplay's range of
motion is derived from it per build instead of tuned; and the drawn body is the
pose that was checked.**

## 1. Why

Two systems decide the arms today, and nothing connects them.

- **What gameplay allows** is a hand-tuned envelope: `TopHandIK`'s reach rim
  about the shoulder (`rom_*_reach_max`, `rom_*_angle_max_deg`), the hand's rest
  height and ceiling (`hand_rest_y`, `hand_y_max`), the forehand floor
  (`top_hand_forward_m`), the two-hand reach (`TopHandIK.two_hand_reach`), the
  backhand release (`bh_release_angle_deg`), the carry's floor off the body
  (`carry_reach_min_m`, `carry_reach_fold_m`), the chest fold
  (`CarryPostureRules`), the trunk's twist (`upper_body_max_twist_deg`,
  `SkaterSpineRig.TWIST_LIMIT`). Each was tuned to stop one visible failure.
- **What is drawn** is a separate two-bone solve per arm: a fixed elbow pole,
  the torso steer (`SkaterArmPoses.steer_turn`), the sword grip and the top
  fist's roll (`glove_basis`, `grip_roll`).

The branch that introduced most of those knobs measured what the split costs:

- The forearms run across the belly, elbows out at the sides, so holding the
  shaft like a sword needs a forearm twisted 95–160° off neutral against a real
  range of about ±85°. The top fist's roll hides most of it; the bottom hand
  reads right only because the twist measure (elbow-bend neutral) mis-reads a
  supinated forearm.
- The bottom arm went through the torso with the blade at the skates until the
  carry floor removed that range; the top hand held a dagger skating round the
  forehand until the floor grew with the fold.
- Every fix was a patch on one symptom, because there is no model to ask "can a
  body hold this?"

## 2. Principles

1. **Grounded anatomy is the default.** A pose is allowed when a human trunk and
   two arms within their joint ranges can hold a rigid stick there, out of their
   own body. Ranges come from clinical range-of-motion norms (§3.3), scaled by
   nothing but the build's segment lengths.
2. **Liberties are explicit.** Any place the game allows or draws something a
   body cannot do is a named entry in §8 with its reason, never a tuned
   number that happens to permit it.
3. **Hockey technique narrows anatomy.** What players actually do is a second,
   separate layer of limits (§4), each one a rule a coach would recognise. It
   only ever removes poses anatomy allows; it never adds one anatomy forbids
   (that would be a liberty).
4. **Gameplay's range of motion is derived, not tuned.** The per-tick envelope
   stays cheap and replay-safe, but its numbers are measured from the model per
   build when attributes apply (§6). Feel tunables (dangle speed, ease rates)
   stay hand-picked; reach does not.
5. **What is drawn is what was checked.** The rig poses the trunk and arms from
   the model's solution for the pose gameplay chose, so the picture cannot
   disagree with the rules (§7).

## 3. The model

### 3.1 Bodies

- **Trunk:** pelvis (the hips' yaw and pitch), lumbar and thoracic spine as one
  twist, one fold and one side-bend about the pelvis, then the shoulder girdle.
  The shoulders' positions come from the trunk, not from fixed markers.
- **The hips stay with the travel; the twist is the spine's.** Skating, the
  pelvis points along the direction of travel (the gait's `travel_align_yaw`,
  the pivot), so every degree the chest turns toward the stick past that is
  thoracolumbar rotation, bounded by the spine's own range (§3.3) — the hips
  give the arms no extra turn. Standing still there is no travel, and the hips
  are where the feet left them (the facing).
- **Arms:** shoulder (three rotations: flexion/extension, abduction/adduction,
  internal/external rotation) with the scapula's protraction as the existing
  `shoulder_reach_m`; elbow (flexion only); forearm (pronation/supination);
  wrist (flexion/extension, radial/ulnar deviation).
- **Grip:** the top hand on the knob holding the shaft like a sword
  (`top_grip_angle_deg`), the bottom hand under the shaft at its own angle and
  free to slide along it (`_grip_fraction`, `_glove_spacing`); one-handed when
  the bottom hand lets go (`ReachPurposeRules`).
- **Stick:** rigid, its length the build's (`solve_stick_length`, chokes
  included), the blade on the ice.

### 3.2 Solving a pose

Given the trunk's state (facing, the hips, the lean and fold the tick already
has) and the blade's target, find the pose that holds the blade there:

- the trunk's twist, fold and side-bend inside their ranges;
- each hand on the shaft, the elbow on its swivel circle, the forearm's twist and
  the wrist's two angles all inside their ranges;
- both arms out of the torso (`SkaterMeshBuilder.torso_clearance`, as
  `steer_turn` measures it).

Among the poses that hold, it takes the one nearest each joint's neutral
(a weighted comfort cost), so the elbow position, the forearm's twist and the
fist's roll come out of the solve rather than from a pole and a measure laid on
afterwards. That is what puts the forearms forward and down into the hands. The
answer is **feasible / not**, the pose, and which limit binds.

### 3.3 Ranges (defaults; each a named constant)

Clinical active range-of-motion norms (AAOS / AMA tables), adult:

| Joint | Motion | Range |
|---|---|---|
| Shoulder | flexion / extension | 180° / 50° |
| | abduction / adduction | 180° / 40° |
| | internal / external rotation | 70° / 90° |
| | horizontal adduction | ~130° |
| Elbow | flexion | 0–145° |
| Forearm | pronation / supination | 80° / 85° |
| Wrist | flexion / extension | 80° / 70° |
| | radial / ulnar deviation | 20° / 35° (ulnar at the top of its published 30–35°) |
| Trunk (thoracolumbar, pelvis fixed) | rotation each way | ~45° |
| | flexion | ~80° (with the hips, more) |
| | lateral flexion each way | ~35° |

The model uses these as hard limits. Today's numbers that disagree are flagged
for review, not changed blindly: the
trunk's twist, which with the hips on the travel is all spine — the skeleton's
limit (`SkaterSpineRig.TWIST_LIMIT`) is 55° and gameplay's cap
(`upper_body_max_twist_deg`) 67°, against ~45°. The twist cap is one of the
derived numbers (§6), so expect it to come down toward the spine's range; every
reach that leans on it moves with it — the facing rules' edges
(`forehand_edge_rad`, `backhand_edge_rad`, rim angle plus twist), the backhand
release, and how far round the body the blade goes before the hips have to
pivot. That shift lands in phase 3 and is reviewed there.

## 4. Hockey technique layer

Limits players observe inside what anatomy allows (`ArmTechnique`, used by the
search when its `technique` is on). Each is a rule with a test
(`test_arm_technique.gd`) and a named, PROVISIONAL number, to be confirmed
against footage before it binds gameplay:

- **The top hand is the pivot and stays in front of the body** — between the
  hips and the chest, not behind the hip or above the shoulder, outside a shot:
  no lower than 0.15 m under the hip joints, no higher than 0.2 m under the top
  shoulder, no more than 0.05 m behind the hips; across the body no further
  than 0.15 m past its middle, and out on its own side no further than 0.4 m.
- **Both hands on the stick while carrying** (already a rule:
  `TopHandIK.two_hand_reach`, the backhand release; the model always holds both).
- **The bottom hand slides, the top hand does not** — reach changes the bottom
  hand's grip along the shaft (the model's freedom), within a hands-apart band
  from a glove's width to the shoulders' width.
- **The knob stays clear of the body** — a stick pulled in so tight the knob
  digs into the stomach is not a carry: the butt (`SkaterStickRig
  .SHAFT_BUTT_EXTEND_M` past the top hand) 2 cm clear of the jersey.
- **The puck is not carried under the body** — toe drags in tight are allowed:
  the blade's middle stays out of the skates' footprint (0.3 m either side,
  0.25 m behind to 0.2 m ahead of the hips).
- **The blade rides flat** — on its heel or its toe a little: the shaft within
  15° of the stick's lie (`Skater.blade_lie_deg`, 42°). Phase 1 left the lie
  free and reported it; this is that window.
- **Shots keep their own technique** — the wrister's weight transfer, the
  slapper's wind-up height — but on top of anatomy, not instead of it (§5).

New ones get added the same way: named, sourced to what players do, tested.

## 5. Shots and the other held poses

The slapper's wind-up and follow-through, the wrister's whip and finish, the
block, the celebration and the faceoff address are authored poses
(`SkaterShotPoseCoordinator`, `_address_*`). Under this plan they are authored as
targets the model must find a pose for, the same as the carry: a wind-up height
the shoulders cannot reach becomes a lower wind-up, not an arm through the
helmet. Each held pose gets a test that its authored keyframes are feasible.
Where a pose needs more than a body has (a celebration's flourish, say), it
becomes a liberty in §8.

## 6. Deriving gameplay's range of motion

The tick path keeps its cheap closed forms — `TopHandIK`'s rim, ceiling and
floors, the two-hand reach, the release angle, the carry floor — because they
run 90×/s per skater and again per replayed input. What changes is where their
numbers come from:

- At `apply_attributes`, the build's segment lengths and stick feed the model,
  which is swept over blade positions round the body at the trunk states that
  matter (standing, the skating fold, twisted each way) to find the feasible
  region.
- The envelope's parameters are fitted to that region: the rim reach per angle,
  the hand's ceiling and floors, the carry's floor off the body as a function of
  the fold, the backhand release, the trunk's twist cap. Some may need a richer
  closed form (a table by angle rather than an ellipse); that is decided by how
  far the current forms sit from the measured region.
- A property test samples the gameplay envelope on a grid and asserts every
  blade it allows has a feasible pose, for every build in the attribute grid.
  `test_top_hand_reaches_its_rim.gd` and its kin become checks of the fit rather
  than of tuned numbers.
- The bots' copies (`AISkaterCaps`, `carry_facing_rules`, the duel harness)
  already read the controller's values, so they follow.

No new wire fields: everything stays a function of tick state every peer has.

## 7. The drawn body

The arm rig and the spine rig pose from the model's solution for the pose
gameplay chose, at render rate, eased where the solution can jump (as the steer
and the roll are now). `steer_turn`, the fixed `arm_pole_local`, `grip_roll` and
the top-hand-only roll are replaced by the solve; `glove_basis` stays as the
grip's own geometry. The locker figure poses through the same model.

## 8. Liberties

Allowed or drawn although a body cannot, each with its reason. Starts empty;
entries get added with the user's sign-off.

## 9. Phases

1. **The model and an instrument, changing nothing in play.** The pure solve
   (§3) with unit tests on known poses; an instrument that sweeps blade
   positions and trunk states per build and maps feasibility and the binding
   limit, against today's gameplay envelope. Deliverable: the map, so the
   decisions in phase 3 are made against data.
2. **The technique layer** (§4), measured the same way.
3. **Derive the envelope** (§6) and land the property test. This is the phase
   that changes feel; reviewed with the map and a playtest before merging.
4. **Draw from the model** (§7), retiring the steer, the pole and the roll.
5. **Shots and held poses** (§5).
6. **Native ports** of the model and the passes that read it, with parity tests,
   once the feel is settled. Until then the GDScript paths stay authoritative,
   as they are on this branch.

Each phase is its own branch and PR.

## 10. Cost

- Gameplay's tick path keeps its closed forms: no new per-tick work.
- The derivation runs per build at `apply_attributes` (a sweep of a few thousand
  solves), off the hot path; cached per build.
- The drawn solve runs at render rate per visible skater, replacing the steer's
  bisection and the roll; it must stay within that budget (two arms, a handful
  of iterations), measured with `measure-frame-cost.sh`.

## 11. Open questions

- The tick side takes the hips square to the **facing**
  (`SkaterSpineRig.shoulder_in_frame`), because their drawn yaw carries the
  render-rate gait; with the hips on the **travel**, the spine's twist budget is
  measured from the travel, so whenever the facing and the travel differ the
  arms have more or less turn than the tick assumes. Phase 1 measures how far
  apart they get in play; the derivation then either takes the hips from a tick
  quantity that follows the travel, or bounds the gap.

- Does the top hand's forehand floor survive once the elbow comes from the solve,
  or does the solve make it redundant?
- How rich does the envelope need to be — is a per-angle table enough, or does
  the reach depend on the fold strongly enough to need a second axis?

## 12. Phase 1 record

### What was built

- **The model** (`Scripts/domain/rules/`): `ArmAnatomy` reads one arm's joint
  angles off where its joints are and holds them to §3.3's ranges, measures it
  against the jersey (`TorsoSection`, the section `SkaterMeshBuilder` already
  drew it from), and solves the arm's own freedoms, the elbow round its circle
  and the fist round the shaft. `ArmAnatomySearch` solves a whole pose for a
  blade on the ice: the trunk's twist, the stick standing from the blade, its
  face's tilt, the bottom hand's place down it. `ArmAnatomyBody` holds the
  numbers, read off a built skater by `SkaterAnatomyCapture`, which also reads
  the trunk as the skater holds it now.
- **Tests**: `test_arm_anatomy.gd` (every motion on a known pose, a left arm as
  the right one's mirror); `test_skater_anatomy_capture.gd` (the model's trunk
  puts the shoulders and the jersey where the rig draws them, within 5 mm,
  standing and skating; the search holds a carry and names the arms' reach
  past one).
- **Instruments**: `tests/instruments/actors/test_arm_anatomy_map.gd` (the map,
  to `.preview/arm_anatomy.md`) and `test_facing_travel_gap.gd` (§11's open
  question).

### Decisions taken

With the user:

- **The grip.** The top hand's grip is fixed to the shaft; the shaft turns
  about its own length, which opens and closes the blade's face, within
  `ArmAnatomySearch.FACE_TILT_MAX` (40°, provisional) of square. The bottom
  hand's cradling grip turns round the shaft freely. Square is the roll a
  relaxed top fist takes at a reference forehand carry
  (`SkaterAnatomyCapture.SQUARE_*`).
- **The lie is free.** Anatomy puts the top hand at any height a body allows;
  the map reports the lie each pose implies, and a lie window is phase 2's.

In building:

- **The jersey check** samples the elbow, the forearm 40% of the way to the
  hand and the upper arm three quarters of the way down
  (`ArmAnatomy.UPPER_ARM_SAMPLE`): the shoulder joints sit inside the jersey's
  ring by ~1 cm, its top half rides under the shoulder pad, and measured at
  its middle the upper arm of an arm hanging at the side read as in the chest.
  Each point keeps the drawn sleeve's radius less its 3 cm of contact out. The
  fist and the shaft are measured too; the pelvis and legs are not.
- **The fist's roll** is searched from the roll that lays the hand's long axis
  along the forearm, scored on the full cost: the wrist's deviation (20°/30°)
  is the arm's narrowest range and the forearm's twist (80°/85°) one of its
  widest, so the roll that turns the hand least overall lands in impossible
  wrists.
- **The reach is the drawn arm's**: the girdle's give and the working
  extension through `TwoBoneIK.reach_root`, as `SkaterArmRig.arm_root` has
  them.
- **Comfort**: each angle's squared share of its range off rest (the elbow's
  rest 80°, the rest 0), the trunk's twist the same; violations weigh 100 per
  radian, a metre of depth or reach as 5 radians.

### What it found

The map (`test_arm_anatomy_map.gd`, ~25 min): three builds (5'7", 6'1",
6'8"), standing and skating carries, the cursor on 55 points round the body
(0.6–1.8 m out, ±150° off the facing), 98 of whose blades a carry reaches.

- **Today's drawn arms hold none of the 98.** The top arm: the fist in the
  jersey (34) or past ulnar deviation (34), then the shoulder's internal
  rotation (12); its elbow is bent 114° at the median (38–150°), the hand held
  up by the chest. The bottom arm: in the jersey in 66, at full stretch (its
  elbow at 28°, the girdle's give taken) in nearly every one.
- **No pose holds 44 of the 98 blades gameplay lands.** Most often the top arm
  cannot clear the jersey (12) or the bottom hand cannot reach the shaft (8),
  then the wrist's ulnar range. These are mostly far round the forehand or the
  backhand, and out at 1.2–1.5 m: gameplay's envelope is too wide there.
- **Inside the carry's floor a body could hold a blade** at most points 0.6 m
  out (gameplay holds it out to 0.8 m and more) — but the poses that do are the
  ones below.
- **Anatomy alone allows poses no player uses**: a stick near vertical with
  both arms raised past the shoulder holds many blades the natural carries
  cannot. The technique layer (phase 2) is what removes them.
- **The natural carry misses by a few degrees**, mostly the wrist's ulnar
  range: §3.3's 30° against the 35° the rig draws to. That review lands in
  phase 3, with the map to decide it against.

Facing against travel (`test_facing_travel_gap.gd`, bots on bots, 60 s each of
3v3 and 5v5): moving skaters' drawn hips sit on average 19–21° off the facing
the tick assumes, and at the gait's 50° cap (`hip_align_max_deg`) 20–25% of
the time; carriers in 5v5 12° and 9%. An upper bound: it reads the hips as
turned all the way to the travel, and the bots' facing stands in for a
player's cursor. The gap is the size of the spine's whole twist budget a
quarter of the time, so phase 3 takes the hips from a tick quantity that
follows the travel rather than bounding it.

## 13. Phase 2 record

`ArmTechnique` (§4) and the search's `technique` switch; the map runs with it
on (`ARM_MAP_ANATOMY_ONLY=1` gives phase 1's). The search now refines the
grid's best three stick poses, not just its best: a dense brute force over one
carry found a near miss the single refinement had settled 0.18 rad short of.
It is still a search: a marginal cell's "no pose" can be a pose it did not
find, and the map prints how far each miss is.

### What it found

The same 330 cells as phase 1 (three builds, standing and skating), 98 of
whose blades a carry lands.

- **Technique costs little where gameplay carries.** 49 of the 98 landed
  blades are held as players hold them, against 54 by anatomy alone. What it
  removes is mostly inside the carry's floor: at 0.6 m out, where anatomy held
  most blades with a stick near vertical and the arms raised, almost none now
  hold — the lie and the footprint rule them out. The floor is technique's,
  not just the drawing's.
- **What stops the other 49 is mostly the wrist.** Ulnar deviation binds in
  20 (the top hand 12, the bottom 8), then the bottom hand's reach to the shaft
  (8), the top arm in the jersey (4) and the lie (4). §3.3's 30° against the
  rig's 35° decides more of the region than any other single number.
- **Today's drawn stick breaks technique as well as anatomy.** Its knob digs
  into the jersey in 49 of the 98 carries; the top hand is behind the hips in 8
  and above the chest in 3. (The map's digits never show, because the drawn
  arms already fail anatomy first in every cell.)
- **The standing carry's trunk is nearly upright** (the pivot 1.6 cm under
  rest): with the hands near the hips, the bottom arm only just reaches the
  shaft, at full stretch, in most of the best poses the search finds. A deeper
  crouch or fold is a phase 3 question, alongside the wrist's range.

### After the wrist's range and the standing crouch

With ulnar deviation at 35° (§3.3) and the standing carry's crouch floor at
1.7 × `stance_hip_deg` (the hips ~7 cm under rest at the full fold, 1.6 cm
before), 62 of the 98 landed blades are held as players hold them, against 49.
The wrist no longer decides the region: what stops the other 36 is the top arm
in the jersey (11), the arms' reach to the shaft (8), the bottom arm in the
jersey (5) and the top hand under its hip band (5). Standing gains least —
neutral standing goes from 13 cells no pose holds to 10 — because the carry at
its 0.8 m floor folds the chest, and so crouches, only partway. Today's drawn
arms still hold none; their knob is in the jersey in 54.
