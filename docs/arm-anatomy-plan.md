# Arm anatomy — every stick pose a body can hold, and the reach that follows

Status: PROPOSED. Not started. Treat it as the agreed design once approved; ask
before deviating from it.

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
| | radial / ulnar deviation | 20° / 30° |
| Trunk (thoracolumbar, pelvis fixed) | rotation each way | ~45° |
| | flexion | ~80° (with the hips, more) |
| | lateral flexion each way | ~35° |

The model uses these as hard limits. Today's numbers that disagree are flagged
for review, not changed blindly: the wrist's ulnar range here is 35°; and the
trunk's twist, which with the hips on the travel is all spine — the skeleton's
limit (`SkaterSpineRig.TWIST_LIMIT`) is 55° and gameplay's cap
(`upper_body_max_twist_deg`) 67°, against ~45°. The twist cap is one of the
derived numbers (§6), so expect it to come down toward the spine's range; every
reach that leans on it moves with it — the facing rules' edges
(`forehand_edge_rad`, `backhand_edge_rad`, rim angle plus twist), the backhand
release, and how far round the body the blade goes before the hips have to
pivot. That shift lands in phase 3 and is reviewed there.

## 4. Hockey technique layer

Limits players observe inside what anatomy allows. Proposed first set, each a
rule with a test, each to be confirmed against footage before it binds:

- **The top hand is the pivot and stays in front of the body** — between the
  hips and the chest, not behind the hip or above the shoulder, outside a shot.
- **Both hands on the stick while carrying** (already a rule:
  `TopHandIK.two_hand_reach`, the backhand release).
- **The bottom hand slides, the top hand does not** — reach changes the bottom
  hand's grip along the shaft first (already the model's freedom), within a
  hands-apart band (a glove's width to roughly shoulder width).
- **The knob stays clear of the body** — a stick pulled in so tight the knob
  digs into the stomach is not a carry.
- **The blade stays ahead of the skates in a carry** — toe drags in tight are
  allowed, the puck under the body is not.
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
