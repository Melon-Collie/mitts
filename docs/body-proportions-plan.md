# Body proportions — a 6'1" skater built like one

Status: APPROVED — all four changes, the new body's reach taken as it comes
(no re-derived constants), the body before the arm envelope.

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
- **Shoulder joints** (height 0.40, half-width 0.22, × build) — gameplay.
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

1. **Legs from the hips.** Raise the hip joints to just under the pivot and
   lengthen the thigh to match (~0.42 m × build), knees and skates where they
   are. Cosmetic, plus the held poses' drops and the faceoff dot, which follow
   from the same constants. The pants and pelvis mesh must fill the new hip.
2. **Shoulders up and in.** Shoulder joints ~7 cm higher and ~4 cm in on each
   side; the torso mesh, neck and skin bind with them; the hands-apart rule
   (ArmTechnique) measured on the shoulders' outside, not joint to joint.
   GAMEPLAY: a higher, narrower shoulder moves every reach — the ROM rim, the
   two-hand stop, the claim clamp, the bots' caps. Either accept the new
   reach, or re-derive the reach constants so the blade's envelope stays
   where it is and only the body changes. Needs a playtest.
3. **A shallower chest.** The visible jersey's rings and the measured profile
   together, ~5 cm off its depth. Cosmetic. DONE: each torso ring has its
   share of the depth scale (`SkaterMeshBuilder.TORSO_DEPTH`), the chest's
   0.875 easing to the pants' full depth at the waist. Thinning them all
   brought a seated figure's thighs through the jersey's tail.
4. **Shaft past the hand** 13 → 9 cm, the knob on the glove. Cosmetic. DONE.
5. **Stick length** — leave as tuned. It is a reach decision, not anatomy.

Then re-render the arm references (their hand heights are measured from the
ice, so they stand), re-run the calibration and re-derive the carry envelope.

## 5. Decisions for the user

- Change 2: keep today's reach (re-derive the constants) or take the reach the
  new body gives?
- Change 4: knob on the glove (~9 cm) or a finger above it (13 cm, today)?
- Which of 1–4 to do, and whether before or after the arm envelope lands.
