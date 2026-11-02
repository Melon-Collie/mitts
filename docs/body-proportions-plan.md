# Body proportions — a 6'1" skater built like one

Status: APPROVED — all four changes, the new body's reach taken as it comes
(no re-derived constants), the body before the arm envelope; the head may
shrink to keep the overall height.

## 1. Why

The arm anatomy work (docs/arm-anatomy-plan.md §14) measured the neutral build
against a man of its height. The arms are right; the body around them is not,
and the errors cancel in the overall height, which is why nobody saw them.

## 2. What was measured

The neutral build (73 in, `height_mult` 1.043), standing at rest, against
textbook segment ratios of stature, with the skate raising the body ~7 cm.
The ratios are estimates; the ANSUR II raw data could not be fetched to check
them.

| | Model | A 6'1" man on skates | Off by |
|---|---|---|---|
| top of helmet | 1.95 m | ~1.95 m | — |
| shoulder joints above ice | 1.47 m | ~1.54 m | 7 cm low |
| hip joints above ice | 0.92 m | ~1.05 m | 13 cm low |
| knee above ice | 0.60 m | ~0.60 m | — |
| thigh (hip to knee) | 0.32 m | ~0.44 m | 12 cm short |
| shin (knee to ankle) | 0.43 m | ~0.44 m | — |
| hip joints to shoulder joints | 0.55 m | ~0.50 m | 5 cm long |
| shoulder joints to top of helmet | 0.48 m | ~0.41 m | 7 cm long |
| shoulder joints apart | 0.44 m | ~0.35–0.37 m | 8 cm wide |
| upper arm, elbow to grip | 0.34, 0.34 m | ~0.34, 0.34 m | — |
| jersey at the chest, wide × deep | 0.47 × 0.39 m | ~0.35 × 0.26 m bare, plus pads | ~5 cm deep |
| shaft past the top hand | 0.13 m | ~0.09 m with a hockey glove | 4 cm |
| stick, top hand to heel | 1.34 m | ~1.45 m | 11 cm short |

Read together: the legs start 13 cm too low (the hip joints hang 0.136 m under
the trunk's pivot, which itself sits where a real hip joint does), so the
thigh is short and the trunk above the drawn hips long. The shoulders sit 7 cm
low and the neck and head make up the difference.

## 3. Where each lives

Mapped from the code; every peer derives these from the six-int build, so
nothing is on the wire, but every change ships to all peers together.

- **Hip joints and thigh** — cosmetic, except the held poses' drops.
  `Skater.tscn` `LegL`/`LegR` (y −0.13) and `ShinL` (−0.31); `GaitPose.THIGH_LEN`
  (0.31), `HIP_DROP` (0.13), copied in `native/src/native_skater_gait.cpp`
  (parity test), `SkaterConnectedMesh` (`_HIP`, `_THIGH_DROP_M`, …) and
  `LockerMannequin` (mirrors test), `BodyBalanceRules.stance_base_ratio`. The
  gameplay frame's height does not come from the legs
  (`FACEOFF_SPAWN_HEIGHT` + `SKATE_LIFT_M`); the drawn hips are seated on the
  ice. Gameplay reads leg length only in the held poses' frame drop (block,
  faceoff, knockdown) and `faceoff_address_drop`, which places the dot.
- **Shoulder joints** (height 0.45, half-width 0.18, × build) — gameplay.
  `Skater.shoulder_height` / `shoulder_offset`, scaled in `apply_attributes`;
  read by the reach (ROM) derivation, `TopHandIK`, the two-hand reach, the
  host's claim clamp and the bots' reach, shots, the reach lean, the dive and
  the knockdown. Copied in `SkaterConnectedMesh._BIND_SHOULDER` and
  `LockerMannequin` (mirrors test). The torso mesh is placed separately
  (`UpperBodyMesh` y 0.195) and must move with them.
- **Chest** — cosmetic and measurement. `SkaterMeshBuilder._TORSO_PROFILE` /
  `_TORSO_Z_SCALE` (elbow steering, pants, paint) and the visible jersey's own
  rings, `SkaterConnectedMesh._CHEST`.
- **Shaft past the hand** — cosmetic. `SkaterStickRig.SHAFT_BUTT_EXTEND_M`,
  sized to clear the drawn fist with a finger of shaft showing.
- **Stick length** — gameplay. `GameRules.DEFAULT_STICK_LENGTH_M` × build:
  reach, blade speed, claims, the bots, the AI snapshots.

## 4. Proposed changes

In order, each its own commit, each rendered (`render-body.sh`,
`skater_matrix.gd`, `render-poses.sh`) and run through the suite:

1. **Legs from the hips.** DONE: the hip joints 11 cm up, just under the
   pivot (`GaitPose.HIP_DROP` 0.02), the thigh 0.42 m (`THIGH_LEN`), knees and
   skates where they were. The gait is tuned in angles, so it was retuned to
   move the body as it did: `stance_hip_deg` 22 → 17.5 and `stride_sit_max_deg`
   45 → 35 keep every crouch floor's drop within a few millimetres, and the
   plant's knee rate 8 → 6 rad/s keeps its speed at the knee. Two pops the
   longer lever showed were fixed rather than re-bounded: the plant now holds
   the feet as soon as no stroke places them (`SkaterLocomotion
   .plant_intensity`), so a shuffle no longer leaves a skate off the ice, and
   the leg solve eases the knee into straight (`LegIK.SOFT_REACH`) instead of
   stopping it dead. The thigh's collider starts where the hip was, or it
   fills the jersey's tail.
2. **Upper body up, head smaller.** DONE: torso, shoulders
   (`Skater.shoulder_height` 0.40 → 0.45), helmet and pants 5 cm up, the head
   and helmet drawn at 0.75 (the Helmet node's scale) so the top stays at
   1.95 m, and the neck stretched to reach the collar. The resting hands stay
   at the hips (`hand_rest_y` −0.10 → −0.05), so the shoulder-to-hand drop and
   the reach it gives are unchanged; the stick at rest is steeper, and the
   blade's lie follows it (`blade_lie_deg` 42 → 47.5°, a real lie 6), or the
   slapper's strike drives the toe into the ice. A seated figure sits down
   under its jersey (`LockerMannequin._settle_hem`). Four smoothness bounds
   were re-set a quarter over the new measure: the same frames, scaled by the
   longer lever. The shoulder joints came 4 cm in each side
   (`shoulder_offset` 0.22 → 0.18, 0.36 m apart), inside the pads, whose width
   the jersey keeps; the hands-apart rule (ArmTechnique) is measured across the
   pads (`ArmAnatomyBody.shoulder_width`), not joint to joint. The neutral
   build's reach came in with them (`LEAGUE_MAX_BLADE_REACH_M` 2.47 → 2.43),
   and a skating wrister's whip peaks 4% higher at the stick, its bound
   re-set a quarter over that.
3. **A shallower chest.** The visible jersey's rings and the measured profile
   together, ~5 cm off its depth. Cosmetic. DONE: each torso ring has its
   share of the depth scale (`SkaterMeshBuilder.TORSO_DEPTH`), the chest's
   0.875 easing to the pants' full depth at the waist. Thinning them all
   brought a seated figure's thighs through the jersey's tail.
4. **Shaft past the hand** 13 → 9 cm, the knob on the glove. Cosmetic. DONE.
5. **Stick length** — DONE: `DEFAULT_STICK_LENGTH_M` 1.30 → 1.40 (top hand to
   heel ~1.44 m with the knob, against ~1.45 m), taken after the body change
   left two slow bot scenarios short of reach. The lie follows the rest pose
   (`blade_lie_deg` 47.5 → 43.3°, a lie 5), and the close-in ceiling
   (`hand_y_max` 0.30 → 0.40) lets the longer stick still tuck the blade in
   tight. The bots' reach and strike constants, the keeper's carrier reach and
   the AI snapshots moved with it, and the shot field was regenerated. The
   bots' one-timer zone now follows the swing the bot committed to, not the
   net, and the keeper racing for a post from within a glide of its overlap
   skates on onto it rather than stopping first: the longer stick exposed
   both.

Then re-render the arm references (their hand heights are measured from the
ice, so they stand), re-run the calibration and re-derive the carry envelope.

## 5. Decisions for the user

- Change 2: keep today's reach (re-derive the constants) or take the reach the
  new body gives?
- Change 4: knob on the glove (~9 cm) or a finger above it (13 cm, today)?
- Which of 1–4 to do, and whether before or after the arm envelope lands.
