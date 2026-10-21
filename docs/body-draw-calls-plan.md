# Player bodies in one draw — plan

Status: **implemented** on `ccr-ae00628d-ai6tzb`.

## Why

Measured at the 5v5 opening faceoff on Forward+ (software Vulkan, so counts, not
timings; see `docs/performance-findings.md` → *The render side*), after the
particle-shadow and net-merge fixes: **1,181 draw calls a frame.** Hiding the ten
skaters' two body meshes removed ~780 of them. Each body is 38 surfaces (20 leg,
18 upper), and a surface is a draw call in the depth prepass and in the colour
pass. The goalie is 21 separate mesh instances, ten of them casting into the
shadowed lights.

Those 38 surfaces are 38 because each part is painted on its own, not because they
need 38 different shaders: every one is a `StandardMaterial3D` that differs only in
colour, roughness, an optional stripe or decal texture, a U offset, and whether
vertex colour tints it. That is data, and data can ride one material.

## The design

### One material, a zone per surface

`Shaders/body_zones.gdshaderinc` is a spatial shader that reads a **zone id** from
`UV2.x` and looks up that zone's paint in uniform arrays:

| array | per zone |
|---|---|
| `zone_albedo` | sRGB RGB + alpha, converted in the shader per renderer (see *Result*) |
| `zone_pbr` | roughness, metallic, rim, rim tint |
| `zone_tex` | texture slot (−1 none), U offset, vertex-colour flag |

and up to eight albedo samplers. It reproduces `StandardMaterial3D`'s output for
the subset the bodies use: `diffuse_burley`, `specular_schlick_ggx`, specular 0.5,
the rim, `albedo × texture × vertex colour`. Textures are sampled at LOD 0 — every
body texture is a mip-less `ImageTexture` or viewport texture, which is what the
standard material samples too.

`body_zones.gdshader` is the opaque body; `body_zones_ghost.gdshader` includes the
same file with `GHOST` defined (alpha blend, the 0.3 ghost alpha as a uniform).

### `BodyZonePaint` — the zone records

A RefCounted that owns one `ShaderMaterial` and a `StandardMaterial3D` **record**
per zone. A record is the description, not something drawn: `set_zone(zone, mat)`
stores it and compiles it into the arrays; `zone(zone)` returns it for reading.
Anything that edits a record in place (the skin tone) hands it back through
`set_zone`. Texture slots are assigned by texture identity, so two zones wearing
one texture share a slot. Ghost swaps the shader and re-pushes the arrays.

The records keep the painters unchanged: `UniformPaint.solid/textured`,
`JerseyDecal.torso_material` and `ShoulderDecal.part_material` still produce the
`StandardMaterial3D` they always did, and the lobby's `FigureKit` dummies, which
wear separate part meshes, keep using them as real materials.

### `BodyZoneMesh` — one surface

`BodyZoneMesh.merge(src, first_zone)` concatenates every surface of a multi-surface
mesh into one, vertex-for-vertex, writing `UV2 = (first_zone + surface, 0)`.
Missing UVs and colours are filled with zeros and white; bones and weights are kept
as they are, so the jersey tail's blended weights survive.

### The skater

- `SkaterMeshBuilder.shared_leg_body_mesh()` / `shared_upper_body_mesh(tuck)` are
  the merges of the existing per-surface skin meshes (legs zones `0..19`, upper
  `20..37`). The per-surface meshes stay: the shadow proxy, the hem flaps and the
  tests read their surfaces.
- `Skater` owns the `BodyZonePaint`; both rig meshes wear its material on their one
  surface. `set_leg_surface_material` / `leg_surface_material` and their upper
  twins keep their names and indices and route to zone records.
- Ghost is one shader swap in `Skater.set_ghost` instead of 38 material fades.
- The coordinator builds each stripe texture once per kit and hands the same one to
  both sides, so the body needs six texture slots, not eleven.

**Result:** 38 surfaces → 2 per skater; head pieces, stick and blade unchanged.

### The goalie

The goalie's parts stay nodes. `skinned-skater-plan.md` → *The goalie does not get a
skeleton* is right about what it measured: the parts are `StaticBody3D`s carrying
colliders, so bones cannot replace their writes and are pure CPU addition. What
that section did not weigh is draw calls, and that is the cost being attacked here.

`GoalieBodyRig` (a `Skeleton3D` under the goalie, owned by `GoalieUniformCoordinator`, so `goalie.gd` — which the shot field is fingerprinted against — carries no rendering):

- At build, after the uniform coordinator is set up, it collects every drawn part
  mesh (not the jersey body, which wears its own `ShaderMaterial`; not the VFX).
  Each becomes one bone of a `Skeleton3D` and its surfaces become zones of one
  merged mesh, with the part's build-time scale baked into the vertices (so a
  non-uniformly scaled part keeps correct normals) and divided back out of its bone.
- The originals stay in the tree as the source of truth for their transforms and
  for every reader that measures them; they go to render layer 0 so nothing draws
  them. `_point_connector`'s `visible` flag still works: a hidden part's bone is
  scaled to zero.
- Every rendered frame, each bone is the part's **interpolated** transform relative
  to the goalie's interpolated root, so the merged body moves exactly as the parts
  would have on screen.
- Shadows come from a second merged mesh of only the parts that cast today
  (`SHADOWS_ONLY`), like the skater's proxy.
- The coordinator rebuilds it at the end of `apply_uniform`, re-reading the
  parts' materials into zone records; its painting is unchanged.
  `apply_jersey_info` only redraws viewport textures the records already hold.

**Result:** 21 instances → 3 (the jersey body, the merged parts, the shadow proxy).

## Verification

- `BodyZoneMesh`: merged vertices, normals, bones and weights equal the source
  surfaces'; zone ids are per-surface.
- `BodyZonePaint`: a record compiles to the arrays it describes; textures share
  slots by identity; ghost swaps and restores.
- Pixel parity against renders recorded before the change: the Forward+ 5v5
  faceoff (whole view, a skater front and back, a goalie) and
  `render-poses.sh`'s Compatibility baseline.
- Draw calls re-measured with the same faceoff probe.

## Result

Measured with the same faceoff probe: **1,181 → 759 draw calls a frame**
(1,533 before the particle and net fixes). Skater bodies 38 surfaces → 2; goalie
21 drawn instances → 3. The goalie rig costs 5.9 µs per goalie per frame on the
main thread (`benchmarks/test_goalie_micro_benchmark.gd`, *body rig pose*), plus
the engine's skeleton upload.

Parity, against renders recorded before the change:

- Forward+ `skater_matrix.gd`: identical but for the ghosted build, where the
  jersey's hem now blends over the pants in the other order (one translucent mesh
  draws its triangles in index order; the old surfaces sorted as separate objects)
  — at most 21/255.
- Compatibility `render-poses.sh`, 56 poses: clean, or one to two stray pixels.
- Forward+ `goalie_capture.gd`: tens to hundreds of pixels at low delta, all where
  the shoulder floaters cut into the jersey body — two near-coincident surfaces
  whose intersection shifts with skinned rather than node-transformed vertices.

Two traps the parity runs caught, both now in the code:

- **Albedo goes up as sRGB, as a `Vector4`.** The server linearises a `Color`
  array itself, and the Compatibility renderer lights in sRGB and converts
  nothing, so the shader converts per `CURRENT_RENDERER`.
- **A mirrored bake reverses winding.** `BodyZoneMesh.add` flips a mirrored
  surface's triangles, as a `MeshInstance3D` would; the goalie's stretch bake
  can carry a mirror.
