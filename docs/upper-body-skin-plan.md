# Upper-body skin — one sleeve from the torso to the wrist

Status: **built** on `claude/gifted-lamport-20dlx9`, awaiting a playtest. If it
does not hold up, the fallback is the stitched-parts sleeve at `550e9a0`
(cap-topped sleeve, stitched elbow) — revert to it, not forward.

## Goal

The arm should read as a sleeve sewn into a jersey: the torso owns the shoulder,
the sleeve leaves it through an armhole, and nothing between the chest and the
glove is a separate piece. The reference is a plain long-sleeve shirt on a
low-poly figure — a gentle shoulder line from the neck to a rounded corner,
the sleeve hanging from under it, a crease at the armpit and nothing else.

Every attempt so far fitted a shape between two rigid parts (a cap, a flared
cone) because the rig cannot do the thing a modelled character does: share a
vertex between two bones.

## Why the rig cannot today

Every bone rests at identity and every bind is identity, so a skinned vertex is
`bone_pose * v` with `v` in that bone's own part space. A vertex with two
influences is then two different points blended — its coordinates mean
different things to each bone. So every vertex is rigid on one bone, and a joint
can only be rings on different bones stitched by bands. That is fine for a hinge
(knee, elbow) and fights a ball joint (the shoulder), whose twist and swing have
nowhere smooth to go.

Godot's `Skin` already carries a bind pose per bind, and a bone may appear in
several binds. Nothing stops the upper skin from adding binds whose pose is a
real rest transform; the rigid parts keep their identity binds untouched.

## Design

### 1. One authoring space for the sleeve: the torso's

The sleeve is authored once, in the TORSO bone's frame at rest (default build,
spine at identity, the arm hanging at the cap's rest pole with the elbow
straight). For each bone the sleeve rides, its bind is

    bind = rest_pose(bone)⁻¹ · rest_pose(TORSO)

with both rest poses in the spine's frame (the old UpperBody space). The torso's
own bind stays identity — its mesh is already in its own frame — so the
torso's vertices and the sleeve's share one space, and a vertex can blend
between any of them.

Rest poses, default build, side `s` (−1 left, +1 right):

| bone | rest |
|---|---|
| TORSO | identity basis, at (0, 0.195, 0) |
| cap / deltoid | `shoulder_cap_rest(s)`, scale 1, at the shoulder (0.22·s, 0.40, 0) |
| upper arm | the cap's frame as a prism (`_CAP_TO_PRISM`), scale (r, r, L_upper), at the shoulder + d·L_upper/2 |
| elbow | the same frame, scale e (the elbow pad radius), at the elbow |
| forearm | the same frame, scale (r, r, L_fore), at the elbow + d·L_fore/2 |

`d` is the rest hang (down the cap's −Y), `r` the sleeve radius, `L_*` the
Skater defaults. Runtime poses need no change: a pose's scale against the rest's
is what sizes a build, as it does now.

### 2. The sleeve's topology

One tube per side, eight facets round, from an **armhole** in the torso to the
wrist:

- **Armhole.** The torso lathe's ten facets put a corner straight out at each
  side (azimuth 90°) and corners at ±36° from it. The four torso quads round
  the side corner between the trapezius ring (station 1) and the chest ring
  (station 3) are dropped, which leaves an eight-vertex loop on the torso —
  exactly the sleeve's eight. The loop's vertices are the torso's own; the
  dropped quads are collapsed to degenerate triangles, so the torso surface
  keeps its vertex count and order (the jersey hem and its tests index it
  vertex for vertex).
- **Shoulder** (the cap surface, carrying the shoulder decal): from the armhole
  loop through a ring at the pivot to a ring down the upper arm.
- **Upper arm**, **elbow** (the three rings at the elbow, as now), **forearm**
  (with its wrist neck), closed at the wrist inside the glove.

Each part stays its own surface so the painter's zones are unchanged, but
neighbouring surfaces share their boundary ring exactly — the same positions
and the same weights — so there is no crack and no crease between them.

### 3. Weights

| ring | rides |
|---|---|
| armhole (torso vertices) | torso |
| between armhole and pivot | torso + deltoid, blended |
| pivot | deltoid (turned half as far as the arm) |
| just down the arm | deltoid + upper arm, blended |
| upper arm | upper arm |
| elbow ring | elbow bone (half the bend, as now) |
| forearm | forearm |

Blending only ever spans a half turn (torso→deltoid, deltoid→arm), which keeps
linear blending's thinning small; the deltoid bone is the helper bone a hand-built
rig would add for the same reason. The elbow keeps its rigid three-ring band,
which already bends without thinning.

The arm's frames stay the carried frame from the cap (`_pose_arm_chain`), so
there is no twist to distribute and no twist bone. The cost, already paid: the
elbow pad cannot point out of the bend.

### 4. Handedness without mesh variants

A side's sleeve rides that side's cap and deltoid but the arm bones of whichever
arm is on that side, which handedness decides. The mesh is shared by every
skater, so instead of two meshes there are **two skins**: identical bind poses,
with the sleeve's arm binds naming the TOP or the BOTTOM arm bones. The arm rig
wears the skin matching the side its top shoulder is on, and swaps it when
`Skater.is_left_handed` changes. The shadow proxy carries the same two.

Consequence for the surfaces: `TOP_*` / `BOTTOM_*` arm surfaces become the
left and right sleeves. The painter gives both arms the same materials, so
nothing on screen changes; the enum's doc says so.

### 5. What stays

Gloves, cuffs, the helmet, the pelvis and the jersey's tail keep their identity
binds and rigid parts. The lobby and locker figures (`FigureKit`) keep the
standalone cap and prisms. The arm posing, its C++ port and its parity test are
untouched. Gameplay reads nothing here.

## Tests

- **One piece.** Every sleeve vertex shared between two surfaces carries the
  same weights; the armhole loop's vertices are the torso surface's own, with
  the torso's weight.
- **Rest is rest.** With every bone at its rest pose, every sleeve vertex
  skins to where it was authored (the binds are right).
- **Handedness.** Each skin's arm binds name the arm whose shoulder is on that
  side.
- **Follows the arm.** On the live rig, across random poses in both the GDScript
  and C++ paths, the elbow ring stays on the elbow and the wrist ring inside the
  glove (the glove test, re-pointed at the sleeve).
- The existing rigid-weight test exempts the sleeve and the torso's armhole;
  the shadow proxy test accounts for the extra binds.

## As built — where it differs from the above

- **The cap swings, it does not roll to world +X.** The cap's X used to be kept
  near world +X for the standalone cap's decal; through an arm swung across the
  chest that flips its roll, the half-turned deltoid carries the twist and the
  shoulder band wrings into a fin. The cap now takes the shortest swing from its
  rest hang (`SkaterArmRig.swing`, written out as axis and angle because
  Quaternion's arc differs between the engine and godot-cpp by millimetres near
  half a turn).
- **The torso round each shoulder takes a share of the deltoid**, up to 0.45
  within 7 cm of the pivot and none past 22 cm, so the armhole's edge moves
  with the arm instead of the band beside it folding. The armhole ring carries
  the same per-corner weights as the torso vertices it shares.
- **The shoulder's ring up in the body is laid on the chest** where it would
  sit inside it, so the inner side runs flush into the armpit instead of
  folding under the torso.
- **Each facet is wound from its own outward normal** (away from the nearest
  point of the arm's axis, the pivot above it); the armhole's top faces up, not
  round the arm.
- **The rings at the pivot and above it lie level**, not square to the arm's
  outward hang, the rings below leaning back toward it and the upper arm's band
  turning the rest by the elbow: tilted, their
  outer side stood over the torso's shoulder line and the deltoid's swing lifted
  it into a tent (`test_shoulder_has_no_peak.gd`). The ring above the pivot is a
  little narrower than the arm (0.95), so the shoulder's corner is bevelled
  rather than a wall.
- **The deltoid stretches across the bend** by 1/cos of its own turn, capped at
  1.5: its ring is the mitre between the chest's side and the arm's, and left
  round it pinched the bend's outside into a notch.
- Known: an arm driven well past the body (a full cross-body reach, the
  slapper's wind-up) still creases on the inside of the shoulder's bend; the
  shoulder has few rings. More rings, or a corrective share, are the next
  levers.

## Phases

1. This document.
2. The sleeve mesh, binds and armhole in `SkaterMeshBuilder`; the prototype's
   widened torso reverted.
3. Handedness skins in `SkaterArmRig` and `SkaterShadowProxy`.
4. Tests rewritten; renders; tuning the shoulder's rings and weights.
5. Full suite, lint, warnings; `Scripts/actors/CLAUDE.md`; commit and push.
