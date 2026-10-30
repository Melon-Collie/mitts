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
| `_legs` | `SkaterLegRig` | the leg bones, the gait written onto them, the ankles' give-back against it, where that puts the blades against the ice (the contact seat), and the ice VFX's two reads (skate mark position, edge load) |
| `_arms` | `SkaterArmRig` | the upper bones: torso, the jersey's tail and its flaps (`SkaterHemFlaps`), pelvis, helmet, both arms by IK (their poses in `SkaterArmPoses`), the trunk texture, the head pieces (face gear, hair and brows on one bone attachment) |
| `_spine` | `SkaterSpineRig` | the four bones that join them (hips, waist, spine, neck) and the balance lean |
| `_stick` | `SkaterStickRig` | the shaft pose, the knob, and the cosmetic flex/whip |
| `_draw` | `SkaterDrawTracker` | the faceoff swipe crest, host-only |
| `_uniform` | `SkaterUniformCoordinator` | the paint |
| `_hud` | `SkaterHUDCoordinator` | the world HUD (ring, plate, chevrons, beacon) |
| `_appearance` | `SkaterAppearanceCoordinator` | per-attribute visual scaling |
| `_shadow` | `SkaterShadows` | the Player Shadows setting: whether the body's meshes and the stick cast, and a ghost never does |
| `_paint` | `BodyZonePaint` | the body's one material: a zone per leg and upper surface, painted from `StandardMaterial3D` records through `Skater`'s surface seams |
| `_anim_lod` | `SkaterAnimationLod` | how often the mesh is re-posed, by camera distance and the Animation Detail setting |
| `_connected` | `SkaterConnectedRig` | the body's one mesh (`SkaterBodyMesh`: the skin and the rigid parts) and the skin's deform bones (below) |

## The body's skin

`SkaterConnectedMesh` builds the torso, sleeves, pants and socks as ONE
connected skin with blended weights; the head, gloves and skates are rigid
parts on their bones (`SkaterRigidParts`). Every part is a zone of the body's
one paint (`BodyZonePaint`), dressed by `SkaterKitPaint`, which the display
figures share, and the whole body is ONE surface (`SkaterBodyMesh`): a draw a
pass, which matters because eight shadowed spots each redraw every skater in
them every frame. `.claude/hooks/render-body.sh` draws it.

- **Its density is spent where it bends.** The jersey has twice the torso
  stations' sides (`SkaterMeshBuilder.TORSO_SIDES`) all the way down, and `SkaterHemFlaps` drapes its tail in as many
  columns (`TAIL_COLUMNS`), on column bones of its own past the deform bones
  (`SkaterBodySkeleton.column_bone`); sleeves and legs have twelve
  sides, with extra rings through the shoulder, elbow, hips and knee.
  Triangles are nearly free here (the figure is ~3.3k against ~1.2 M a frame);
  bones and tail columns are what cost per frame (the cloth is linear in its
  columns: ~20 µs a skater natively at 20). The pants and legs are
  `SkaterConnectedPants`.
- **It is authored in a bind pose**, the body skeleton with HIPS/WAIST/SPINE at
  identity, the legs straight and the arms out, forward and 35° under level
  (`bind_arm`). Each bind's inverse rest is its bone's global pose there
  (`bind_rests`), so it rides the rigs' bones untouched; the torso's rings are
  built round `SkaterMeshBuilder`'s rest stations (`torso_ring`), and its tail
  hangs from the belt on `SkaterHemFlaps`' column bones. Its pants stand their
  rim up under a tuck: a padded band eased up
  as far as each column is tucked (no spike at a half tuck's corner), with the
  jersey bloused wider above it and kidney pads behind. Beside a half tuck's
  corner its tail is drawn in taut (`tail_ring`): the belt ring toward the
  tucked girth and the hem lifted all but up to it, and the flaps hold those
  columns to that drape as far, so the hem runs up into the waistband rather
  than flaring out beside it.
- **The arms get deform bones of their own** (`SkaterConnectedRig`, after the
  TAIL bone on the skeleton): the arm bones roll from world up, and a blended
  elbow needs both halves turning about one hinge. Per side the upper arm, the
  elbow's middle and the forearm share the ELBOW bone's hinge.
- **The armhole is a jersey's seam**, near upright from the shoulders' flat
  top down to under the arm, so the torso carries the shoulder's top out level
  from the neck and the sleeve leaves it at the side; the seam joins the
  upper arm's first ring directly: one tube narrowing from the seam down the
  arm. Any ring between them reads as a separate shoulder part, a kink where
  the sleeve meets it.
- **The shoulder splits the arm's turn off the chest into swing and twist.** The
  girdle (the armhole and the top of the shoulder) takes a share of the swing
  that rises as the arm lifts, as the collarbone and shoulder blade do (the
  scapulohumeral rhythm), the shoulder's middle (half of the upper arm's
  first ring) two thirds, the upper arm all of it and half
  the twist, the elbow the rest. Blending the chest straight into the arm
  collapses the pad into a fin past ~90°; putting the whole twist on one ring
  pinches the sleeve shut.
- **Each sleeve is painted whole** (`SleeveDecal`): the kit's `sleeve`
  (`SleevePaint`, one base and stripes from the shoulder to the cuff) drawn
  down a texture with the number on the outside near its top, U round the arm
  and V down its whole length, one paint zone per arm (`sleeve_surface`). The
  goalie still paints his arm in two; the registry cuts the sleeve back into
  `arms.upper` / `arms.lower` for him (`SleevePaint.segment`).
- **The knees** blend through a middle bone at half the shin's turn
  (`Deform.KNEE_*`), so the back of the knee does not collapse.
- **The display figures wear the same body.** `FigureKit` (the player screen's
  case, the lobby's bench) builds the body skeleton, the skin, the rigid parts,
  the kit paint and the jersey's cloth; `LockerMannequin` poses the skeleton's
  bones itself (the arms through `SkaterArmPoses`) and hands the skin its deform
  bones (`SkaterConnectedRig.pose`). Its cloth hangs under gravity alone — there
  is no skater to accelerate — and is carried round with the case's turn.

## The puck's tilt and spin are drawn, never simulated

The analytic puck is a flat disc. `PuckSpinRig` gives the drawn one its spin,
its wobble after a hit and its tumble in the air, reading only the position
the puck is drawn at and who this peer draws carrying it
(`PuckController.drawn_carrier`, through `Puck.set_carrier_view`). It writes
the mesh's local transform and the smear on the face print (`PuckPrint`, the
Mitts skater over a bar, blurred across the angle the disc turns in a 60 fps
frame) on the tick and nothing else, so it needs no wire
bytes and no reconcile, and the `Puck` node itself never rotates (`PuckShadow`
relies on that). `test_puck_spin_rig.gd` holds the model, and holds that
nothing but `Puck` names the rig; `.claude/hooks/render-puck.sh` shows it.

## The seam

Traffic runs **one way**. A collaborator holds `_skater` and READS the node's
tuning vars, markers and replicated state; it writes only its own fields and the
NODES it was handed (bone poses, mesh transforms — that is what a rig does).
`Skater` calls methods on a collaborator and never writes one of its fields.

That single rule is the whole contract, and it is not a style preference:
whoever writes a field has re-derived *when* it changes, which is the other
side's lifecycle, and from that moment the other side's own updater is dead code
waiting to happen. The correlation was measured across the old goalie's
collaborators — contested fields 0/2/2/12 predicted dead methods 0/0/0/17. See
`Scripts/controllers/CLAUDE.md`.

Two more, held by the same test
(`tests/unit/actors/test_skater_collaborator_seams.gd`):

- **Rigs never name each other.** They are siblings; a const read across a
  GDScript `class_name` cycle fails at *parse* time and takes every file in the
  cycle down. What two rigs share lives outside both: the look-at helper the
  stick knob and the arm parts compose alike is `SkaterArmPoses.up_for_look_at`.
- **Build order in `_ready` is load-bearing.** The rigs stand first: the uniform
  pass installs the shaft's flex ShaderMaterial and the appearance pass sizes
  bones through the rigs' seams, so both need a rig that exists.

## Why Skater still has a wide public API

The rigs took the *state* and the *code*, not the call sites: `set_leg_swing`,
`upper_surface_material`, `begin_draw_tracking` and the rest stay on `Skater` as
one-line delegates, because the controllers, the gait, the uniform pass and the
ice VFX all address a skater and should not have to know which rig answers.
That is the same shape `_hud` and `_uniform` already had. So the line count
moved a long way and the public API did not — the entanglement the split was
measured against is shared *fields*, and there are now none.

## One skeleton, one chain

The whole figure is one `Skeleton3D` (`SkaterBodySkeleton.new_body_skeleton`),
built by `Skater` and handed to each rig, which poses only its own bones. It
sits under `MeshRoot` as a sibling of `UpperBody` and `LowerBody`, so skeleton
space is the space those two gameplay frames are placed in, and the arm IK
reads the gameplay hands straight into it, through the frames as drawn (see
*Cosmetic vs. gameplay* below).

```
HIPS     on LowerBody (which carries the lean's shift): its yaw and pitch, and
         the full balance lean; both legs root here
  WAIST  half the trunk's twist — the pelvis (shorts) rides it
    SPINE  the fold about the hips, then the rest of the twist, then the
           reach lean, less the lean the trunk hands back; the torso
      NECK   takes back part of the trunk's lean; the helmet
    TAIL   the torso's placement hung from the waist: the share of the
           jersey's tail the hips carry
deform   the skin's sleeves (roots) and knees (on the LEG bones), posed off
         the bones above (SkaterConnectedRig)
tail     roots, one pair per tail column: the jersey's tail below the belt,
         draped by SkaterHemFlaps (with the jersey's carry above, SkaterJerseyHem)
arms     roots, solved from the spine's shoulders to the gameplay hands
```

Two things that order buys, and that the old sibling rigs (an upper skeleton
under `UpperBody`, a leg skeleton under `LowerBody`) could not:

- **The fold comes before the twist.** `UpperBody` is yawed and then pitched
  (Godot's YXZ), so its forward lean tips sideways whenever the shoulders turn
  toward the stick. The spine folds about the hips' axis first and twists on
  top of the fold. Measured skating at 9 m/s with the cursor swept across the
  body, reach lean held out: the head drifted ±0.18 m across the line of travel
  off the pelvis before, ±0.02 m after. The reach lean tips it toward the hand
  on top of that, by design.
- **The twist has a joint limit** (`SkaterSpineRig.TWIST_LIMIT`, 55°). The
  shoulders always point where gameplay put them, so the arms reach their
  hands; past the limit the hips come round instead.

The order has a price: a trunk both folded and twisted — a skating fold and a
backhand reach — carries its shoulders off `UpperBody`'s markers, 5 cm at full
twist. The arms are drawn from the trunk's, so the top hand is solved from
there too (`SkaterIKCoordinator.arm_shoulder`, through
`SkaterSpineRig.shoulder_in_frame`, which `test_top_hand_reaches_its_rim.gd`
holds against the rig). Solved from the marker, the hand reached past the arm
drawn to it. That copy reads tick state only — the hips are taken square to the
facing, because their yaw carries the render-rate gait and the blade is
gameplay.

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

The pants ride the waist, so the twist between them and the chest shows
somewhere. Half of it goes on the waist and half on the spine. The jersey's
tail takes the rest as cloth would: it hangs
over the pants and blends from the chest onto the hips — wholly at the front,
where the thighs push it, and only `CARRY_BACK` of it at the back, which rides
up with the chest over the seat — so a fold or a twist bends the sweater
rather than driving its hem through the pants. A tuck (the gear style's
`jersey_tuck`) is which shared skin the skater wears
(`SkaterConnectedMesh.shared_mesh`): the tucked tail is pulled inside the
waistband, and the flaps hold it there.
`tests/unit/actors/test_body_chain.gd` holds the chain,
`test_pelvis_fills_the_seat.gd` the seat and `test_jersey_tuck.gd` the tucks.

**The tail below the belt is cloth** (`SkaterHemFlaps`): a ring of
two-segment flaps, one per tail column, hung from the belt ring where the
weights above put it, swung by gravity less the skater's own acceleration,
held to its drape and its neighbours, and pushed out of the thighs and pants
(`SkaterHemColliders`, from the leg bones' live poses and the pants' collider
stations, `SkaterConnectedPants`). A rigid tail cannot do this: a thigh lifted
in a stride or a crouch pokes straight through one. It steps every frame and
writes its 40 bones when drawn;
it runs in C++ where the extension is built (`NativeHemFlaps`), and
`test_native_hem_flaps_parity.gd` holds the two together. The solver itself is
`HemFlaps`, shared with the keeper's jersey tail (`KeeperJerseyTail`); each
figure brings its own drape, its own bones and its own colliders
(`HemColliders`: `SkaterHemColliders`, `KeeperTailColliders`), and the port
takes the same three.
`test_hem_flaps.gd` holds the drape and `tests/slow/actors/test_hem_stays_out_of_the_legs.gd` the
tail against the legs across a skated run.

## The blades stand on the ice

Most of the gait still poses joints rather than feet, and its crouch pays for
the stance alone; the splay, the stagger and the lean all move the blades too.
So the body is placed from where the blades are (`SkaterLegRig.seat_on_ice`,
called by the spine as it places the hips). The authored states (stride,
crossover, carve, stop, skid) are the exception: they are authored as where
their skates go, on the ice (`Scripts/controllers/CLAUDE.md`), and only need the
seat to stand them up.

- **Both feet, then the body.** The lower runner is the support. The other's
  knee is re-solved (the thigh counter-pitched as `GaitPose.seed_legs` does,
  so the foot keeps its fore-aft place) to bring its runner down to the
  support's; where it cannot reach — a braced front leg already straight — the
  support folds to meet it, the skater sitting deeper on the back leg — only
  where folding starts by raising the support's runner. From a straight knee
  the fold first tips the rigid blade down, so the nearest crossing is a fold
  out of all proportion to the gap; the gap stays instead
  (`test_blades_stand_on_the_ice.gd`, the stop from the side). Then the
  hips translate to put the support on the ice; a translation moves both feet,
  so that step is exact.
- **The plant is for two-footed stances.** The gait publishes how much each
  foot is held (`GaitPose.plant_share`): fully while the stroke is idle (rest,
  glide, the faceoff set) and through the dug-edge states (stop, tight turn),
  none while the stroke is driving — a stride's push and recovery are where the
  stroke puts the feet, and holding them down there fights its geometry. The
  block unplants its kneeling leg; the knockdown unplants both and fades the
  seat itself (`plant`), and while the sprawl owns the legs the seat does not
  re-pose them.
- **The ankle gives back two ways** (`SkaterLegRig.set_ankle_flatten`): the
  whole chain's rotation, which squares the boot (the held poses), or the
  blade laid flat on the ice along the leg's heading (its yaw), left on
  whatever edge the leg rolled it to (the authored states, so a push drives its
  whole inside edge rather than rocking onto its heel, and a stop's blades sit
  square across the travel). The second levels against the ice, not
  the hips, so the gait passes the hips' tilt with it.
- **Height is not monotone in the knee.** The ankle is otherwise rigid, so a
  blade tilts with its shin and its lowest point is a tip; near
  straight, unbending rocks the boot and lifts that tip. The solve walks out
  from the gait's own knee in its role's direction (the reaching leg extends,
  the support folds) to the NEAREST crossing, interpolating the closest point
  when there is none — never a sampled or far root, which hops between frames.
- **It runs in C++ where the extension is built** (`NativeLegChain`): the
  plant's walk, the chain it evaluates and the ankle pose. Change
  `_plant_feet`, `_solve_knee`, `_refine`, `_extremum`, `_chain` or
  `_foot_pose` and the port changes with it, or
  `test_native_leg_chain_parity.gd` fails; the rig mirrors its rest geometry
  and the gait's pose into the kernel on every write that changes them.
- **The correction eases.** The right answer itself jumps when the support
  hands from one foot to the other, so the knee change moves at most
  `_PLANT_RATE_RAD_S`, from the render delta the gait passes with the plant.
- **The seat's writes are a function of its inputs**, so they do not bump the
  legs' `pose_version`, which the spine keys its cache on.

`test_blades_stand_on_the_ice.gd` drives every locomotion state through the
render pass, measures the runner mesh against the ice and bounds every leg
pivot's per-tick step; `test_faceoff_prep_pose.gd` holds the centre's address
on both blades; `test_gait_stroke_profile.gd` catches a plant that bleeds into
the stride; `test_leg_ik_mirrors_the_rig.gd` holds the gait's model of the leg
and the boot against these bones.

## Cosmetic vs. gameplay, and the render clock

Everything in the four rigs is cosmetic and derived. Nothing gameplay reads
comes out of them, and that is what makes them safe to move: the blade contact
point is the `Blade` marker's, and the rigs only read it.

Nine rules the rigs sit inside, all easy to break from in here:

- **The top hand is drawn from `Skater.drawn_top_hand()`**, not the `TopHand`
  marker: the marker plus a render-only offset (the stride's pump, and the
  swing that keeps it in front of the chest), so the arm, the stick and the
  blade's dressing pivot about a blade that has not moved. The rebuild gate
  compares the drawn hand, or the offset would never redraw.
- **The rig reads the markers and the frames where the engine draws them**
  (`drawn_top_hand`, `Skater.drawn_blade`, `drawn_upper_body`,
  `drawn_lower_body`): between where the latest tick found them and where they
  are now, at this frame's interpolation fraction (the snapshot is taken on
  `SceneTree.physics_frame`). The blade mesh hangs from the interpolated `Blade`
  marker, so the shaft, the knob and the arms are posed from the same instant,
  and those three nodes are opted out of physics interpolation. An interpolated
  node written at render rate is drawn from the pose the previous FRAME wrote,
  so below 120 fps, where a frame runs two ticks, it lags a tick behind the
  marker it should meet. The skeleton is the frames' sibling, so the spine and
  the arms are built in the frames as drawn too; built in the tick's, a glove
  sat off its shaft by a tick of the trunk's turn. Tick-side reads (the IK's
  reach, claims) stay on the markers and frames themselves.
  `tests/slow/actors/test_stick_draws_at_one_instant.gd` holds it on the real
  main loop.
- **Anything drawn onto the skater at render rate reads
  `Skater.render_transform()`**, not `global_position` — the post-tick pose is up
  to a tick of travel from the body on screen. A node placed that way must also
  opt OUT of physics interpolation, or the engine interpolates an
  already-interpolated pose. `SkaterLegRig.mark_position` is the worked example:
  the body half is read interpolated, the bone-pose half as-is.
- **The crouch is the body's, not the frame's.** The visible body sits
  `Skater.body_drop_below_frame()` under `LowerBody`, applied at the HIPS bone,
  so the skating crouch and its bob never move the frame the hands hang from;
  only a held pose's share lowers the frame itself. Then the hips are seated on
  the blades (below).
- **Nothing in the skeleton is written back into `UpperBody` or `LowerBody`.**
  The blade and shoulder markers hang under `UpperBody`, so writing it at render
  rate would move gameplay geometry. The chain reads both frames and writes
  bones, which are pure mesh.
- **Off camera, only mesh is skipped.** A skater the camera cannot see
  (`Skater.on_camera`, `SkaterCameraCull`'s sphere against the frustum) skips the leg, trunk and
  sprawl writes, the head, the off hand and the spine/arm/stick rebuild — about
  two thirds of his render pass — and rebuilds on the first frame he is drawn.
  The blade mesh is the one piece of mesh hung from a gameplay marker, so a
  skipped frame holds it where it was last drawn (`Skater._hold_blade_mesh`), or
  the tick carries it off the waiting shaft.
  A frame his animation LOD thins (`SkaterAnimationLod`, far from the camera at
  a lower Animation Detail) is off camera in exactly this sense, so it inherits
  the same guarantee; the plant's ease is then charged the whole span since the
  last pass (`SkaterAnimationLod.span`), not one frame.
  The gait itself still computes, because a held pose's crouch moves the
  gameplay frame: whether the host can see a blocker must not move his hands.
  `test_off_camera_culling.gd` holds that, and `ClipFrameCapture` turns culling
  off while its own camera records.
- **The arms are posed in C++ when the extension is built** (`NativeArmRig`,
  which writes the arm bones itself). Change `_update_arm` or the part poses
  (`SkaterArmPoses`) and the port changes with it, or
  `test_native_arm_rig_parity.gd` fails; see `native/README.md`.
- **Through a slapshot the stick is one rigid piece** (`Skater._swing_rigid`):
  the dressed blade is solved from the shaft's bearing, which whips round as
  the blade crosses over the hands, so through the swing the blade and the
  shaft's roll (`Skater.shaft_roll_up`) are instead the swing's starting ones
  turned by the shortest arc from the starting hosel line, in UpperBody's frame.
  Anchored, not carried frame to frame — a carry drifts by the solid angle its
  loop encloses. `test_slapper_stance.gd` measures the roll.
- **The pelvis must not take the fold.** It hangs from the waist, not the
  spine: folding with the torso is what opens the seat in the first place, and
  hanging it off a leg pivot would swing the whole seat with that leg.
  `tests/unit/actors/test_pelvis_fills_the_seat.gd` holds that it does not take
  the fold.
