# Skater collaborators

`Skater` (`skater.gd`) is the Node3D in the scene. It owns the tuning vars the
controller scales per player, the **markers** — `Blade`, `Shoulder`, `TopHand`,
`BottomShoulder`, `BottomHand` — which are gameplay geometry every claim
resolver clamps against, the replicated runtime state, and the physics tick.
Everything else is a RefCounted collaborator it constructs in `_ready` and
delegates to.

(The arena bowl has its own directory and its own rules:
`Scripts/actors/arena/CLAUDE.md`.)

| holder | class | what it owns |
|---|---|---|
| `_legs` | `SkaterLegRig` | the leg bones, the gait written onto them, the ankles' give-back against it, and the ice VFX's two reads (skate mark position, edge load) |
| `_arms` | `SkaterArmRig` | the upper bones: torso, pelvis, helmet, deltoid caps, both arms by IK, the trunk texture, the face gear |
| `_spine` | `SkaterSpineRig` | the four bones that join them (hips, waist, spine, neck) and the balance lean |
| `_stick` | `SkaterStickRig` | the shaft pose, the knob, and the cosmetic flex/whip |
| `_draw` | `SkaterDrawTracker` | the faceoff swipe crest, host-only |
| `_uniform` | `SkaterUniformCoordinator` | the paint |
| `_hud` | `SkaterHUDCoordinator` | the world HUD (ring, plate, chevrons, beacon) |
| `_appearance` | `SkaterAppearanceCoordinator` | per-attribute visual scaling |

## The seam

Traffic runs **one way**. A collaborator holds `_skater` and READS the node's
tuning vars, markers and replicated state; it writes only its own fields and the
NODES it was handed (bone poses, mesh transforms — that is what a rig does).
`Skater` calls methods on a collaborator and never writes one of its fields.

That single rule is the whole contract, and it is not a style preference:
whoever writes a field has re-derived *when* it changes, which is the other
side's lifecycle, and from that moment the other side's own updater is dead code
waiting to happen. The correlation was measured across the goalie's six
collaborators — contested fields 0/2/2/12 predicted dead methods 0/0/0/17. See
`Scripts/controllers/CLAUDE.md`.

Two more, held by the same test
(`tests/unit/actors/test_skater_collaborator_seams.gd`):

- **Rigs never name each other.** They are siblings; a const read across a
  GDScript `class_name` cycle fails at *parse* time and takes every file in the
  cycle down. The single allowed edge is `SkaterStickRig` reading
  `SkaterArmRig.up_for_look_at`, whose composition the stick knob copies.
- **Build order in `_ready` is load-bearing.** The rigs stand first: the uniform
  pass installs the shaft's flex ShaderMaterial and the appearance pass sizes
  bones through the rigs' seams, so both need a rig that exists.

## Why Skater still has a wide public API

The rigs took the *state* and the *code*, not the call sites: `set_leg_swing`,
`upper_surface_material`, `begin_draw_tracking` and the rest stay on `Skater` as
one-line delegates, because the controllers, the gait, the uniform pass and the
ice VFX all address a skater and should not have to know which rig answers.
That is the same shape `_hud` and `_uniform` already had. So the size ratchet
moved a long way and the API ratchet did not — the entanglement the split was
measured against is shared *fields*, and there are now none.

## One skeleton, one chain

The whole figure is one `Skeleton3D` (`SkaterBodySkeleton.new_body_skeleton`),
built by `Skater` and handed to each rig, which poses only its own bones. It
sits under `MeshRoot` as a sibling of `UpperBody` and `LowerBody`, so skeleton
space is the space those two gameplay frames are placed in, and the arm IK
reads the gameplay hands straight into it.

```
HIPS     on LowerBody (which carries the lean's shift): its yaw and pitch, and
         the full balance lean; both legs root here
  WAIST  half the trunk's twist — the pelvis (shorts) rides it
    SPINE  the fold about the hips, then the rest of the twist, then the
           reach lean, less the lean the trunk hands back; torso and caps
      NECK   takes back part of the trunk's lean; the helmet
arms     roots, solved from the spine's shoulders to the gameplay hands
```

Two things that order buys, and that the old sibling rigs (an upper skeleton
under `UpperBody`, a leg skeleton under `LowerBody`) could not:

- **The fold comes before the twist.** `UpperBody` is yawed and then pitched
  (Godot's YXZ), so its forward lean tips sideways whenever the shoulders turn
  toward the stick. The spine folds about the hips' axis first and twists on
  top of the fold. Measured skating at 9 m/s with the cursor swept across the
  body: the head drifted ±0.18 m across the line of travel off the pelvis
  before, ±0.05 m after — what is left is the reach lean.
- **The twist has a joint limit** (`SkaterSpineRig.TWIST_LIMIT`, 55°). The
  shoulders always point where gameplay put them, so the arms reach their
  hands; past the limit the hips come round instead.

**The body leans toward its acceleration** (`BalanceRules`): atan(|a|/g),
eased softly into a 20° cap, through a critically damped spring solved
exactly. One model is the turn's bank, the start's forward drive and the
stop's sit back; the gait authors none of them. It pivots at the ICE under the
skater: the blades are where the body touches the ice, so they stay put and the
body goes over them. That carries
the shoulders up to ~0.45 m into a turn, and the hands go with them, so the lean
is gameplay — `SkaterController` steps it in the tick, it is replicated, and it
TRANSLATES both gameplay frames (`Skater._update_lean_shift`) without tilting
them; the chain then seats the hips on the shifted `LowerBody` and tips them by
the full lean. (Pivoting at the hips instead keeps the torso still and swings
the skates 0.4 m round it, which reads as the legs sliding.) The trunk keeps
only `trunk_lean_share` of it (legs carry the edge, shoulders stay near the
stick), and keeps it `trunk_lean_lag_s` late (`Skater.trunk_tilt`, a
first-order delay off the lean and its replicated rate): the hips go over
first and the chest follows, and on a reversal the chest crosses upright about
0.1 s after the hips. Both the gameplay frame's shift and the spine read that
one tilt, so the visible shoulders stay on the frame the hands hang from. The
neck takes back `head_level_share` of the trunk's lean. The spring is what
tells a steering correction from a turn, and gives the lean its weight: a held
arc arrives in ~1 s, side-to-side steering shows as a few degrees.
`test_lean_pivots_at_the_skates.gd`, `test_balance_rules.gd`.

The shorts and the jersey are both rigid shells, so the twist between them
shows as a seam wherever it happens. Half of it goes on the waist and half
on the spine, and the pelvis profile above the hem is narrow enough to stay
inside the jersey at the resulting angle.
`tests/unit/actors/test_body_chain.gd` holds the chain and
`test_pelvis_fills_the_seat.gd` the seat.

## Cosmetic vs. gameplay, and the render clock

Everything in the four rigs is cosmetic and derived. Nothing gameplay reads
comes out of them, and that is what makes them safe to move: the blade contact
point is the `Blade` marker's, and the rigs only read it.

Five rules the rigs sit inside, all easy to break from in here:

- **Anything drawn onto the skater at render rate reads
  `Skater.render_transform()`**, not `global_position` — the post-tick pose is up
  to a tick of travel from the body on screen. A node placed that way must also
  opt OUT of physics interpolation, or the engine interpolates an
  already-interpolated pose. `SkaterLegRig.mark_position` is the worked example:
  the body half is read interpolated, the bone-pose half as-is.
- **The crouch is the body's, not the frame's.** The visible body sits
  `Skater.body_drop_below_frame()` under `LowerBody`, applied at the HIPS bone,
  so the skating crouch and its bob never move the frame the hands hang from;
  only a held pose's share lowers the frame itself.
- **Nothing in the skeleton is written back into `UpperBody` or `LowerBody`.**
  The blade and shoulder markers hang under `UpperBody`, so writing it at render
  rate would move gameplay geometry. The chain reads both frames and writes
  bones, which are pure mesh.
- **Off camera, only mesh is skipped.** A skater the camera cannot see
  (`Skater.on_camera`, `SkaterCameraCull`'s sphere against the frustum) skips the leg, trunk and
  sprawl writes, the head, the off hand and the spine/arm/stick rebuild — about
  two thirds of his render pass — and rebuilds on the first frame he is drawn.
  The gait itself still computes, because a held pose's crouch moves the
  gameplay frame: whether the host can see a blocker must not move his hands.
  `test_off_camera_culling.gd` holds that, and `ClipFrameCapture` turns culling
  off while its own camera records.
- **The pelvis must not take the fold.** It hangs from the waist, not the
  spine: folding with the torso is what opens the seat in the first place, and
  hanging it off a leg pivot would swing the whole seat with that leg.
  `tests/unit/actors/test_pelvis_fills_the_seat.gd` holds it: it stays under the
  jersey at any twist the waist leaves it, it meets the hip balls it sits
  between, and it does not take the fold.
