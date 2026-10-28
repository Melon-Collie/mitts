class_name SkaterMeshBuilder
extends RefCounted

# Low-poly faceted geometry for the skater. Cosmetic only — gameplay reads the
# Marker3D anchors and collision shapes, never these meshes.
#
# The two skinned meshes it assembles are shared_upper_skin_mesh (UpperBone /
# UpperSurface) and shared_leg_skin_mesh (LegBone / LegSurface). Every mesh here
# is cached and shared by the whole roster — per-skater colour is a surface
# override, per-build sizing rides the scale in a bone's pose — so nothing is
# ever mutated per instance.
#
# UV layouts replicate the Godot primitives they replace, because
# SkaterUniformCoordinator paints against those exact conventions:
#   - Lathed (cylinder-style) parts: side U wraps from +Z toward +X with the
#     side occupying V ∈ [0, 0.5] top→bottom; the top cap disk lands in the
#     U ∈ [0, 0.5], V ∈ [0.5, 1] quadrant (where the jersey yoke paints), the
#     bottom cap in U ∈ [0.5, 1] of the same half.
#   - Ball (sphere-style) parts: equirect, U from +Z toward +X, V from 0 at
#     the top pole to 1 at the bottom (where the shoulder-number decal paints).
# Change a painter convention there and the matching generator here together.
#
# Everything is flat-shaded (smooth_group(-1)) — the faceting IS the art
# style; per-face normals are what make the shaped silhouettes read.

# Profiles are (y, radius) stations top→bottom in the part's mesh-local frame,
# spanning the same envelope as the primitive each replaces (heights and radii
# from Scenes/Skater.tscn) so nothing pokes through ice, boards, or gear that
# was tuned around the primitive silhouettes.
const _TORSO_PROFILE: Array[Vector2] = [
	Vector2(0.275, 0.125),   # collar, around the neck's trapezius flare
	Vector2(0.250, 0.185),   # trapezius, sloping off the neck over the shoulder pads
	Vector2(0.212, 0.222),   # shoulder line — the pads' widest, the arms hang from it
	Vector2(0.130, 0.222),   # chest — from here the sweater hangs nearly straight,
	Vector2(0.000, 0.212),   # barely in at the waist
	Vector2(-0.070, 0.214),  # bunches over a tuck's pad (SkaterJerseyHem.BUNCH_Y_M)
	Vector2(-0.125, 0.218),  # goes in under a tuck's pad (SkaterJerseyHem.PAD_Y_M)
	Vector2(-0.150, 0.219),  # the pants' waistband line (SkaterJerseyHem.BELT_Y_M)
	Vector2(-0.210, 0.232),  # from here the tail hangs over the pants, flaring
	Vector2(-0.280, 0.263),  # out round the thigh domes' widest
	Vector2(-0.350, 0.278),  # hem, just under the hip pivots (SkaterJerseyHem.HEM_Y_M)
]
# The yoke paints the torso side from the collar down to the shoulder line
# (station 2), as a fraction of the side's height; the collar ring is the top cap.
const TORSO_SIDE_HEIGHT_M: float = _TORSO_PROFILE[0].x - _TORSO_PROFILE[10].x
const TORSO_YOKE_SIDE_FRACTION: float = (_TORSO_PROFILE[0].x - _TORSO_PROFILE[2].x) \
		/ TORSO_SIDE_HEIGHT_M
# Rear (+Z is the back) shift per _TORSO_PROFILE ring — the hockey-butt sway:
# the seat builds through the lower back and peaks at the hem that drapes
# over it, while the chest rings stay centered so the belly keeps its line.
const _TORSO_REAR_SWAY: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.006, 0.012, 0.018, 0.020, 0.026, 0.032, 0.036]
# Per _TORSO_PROFILE ring: (width, depth) against the lathe's ellipse; how
# square the section is (2 is the ellipse; more flattens the chest and back into
# planes and puts a corner at each side) — a chest under shoulder pads, broad and
# shallow, rather than a column; and how far the front panel's two corners sit
# below the ring, metres. The front's drop tips the collar toward the viewer and
# lets the chest fall away under it while the shoulders stay up on their pads.
# The tail's rings stay elliptical: the tuck and the pants under them are built
# against that ellipse.
const _TORSO_SECTION: Array[Vector4] = [
	Vector4(1.0, 1.0, 2.0, 0.025),   # collar, round the neck
	Vector4(1.17, 0.80, 3.4, 0.03),
	Vector4(1.03, 0.76, 4.0, 0.014),  # the shoulder line
	Vector4(1.01, 0.80, 3.6, 0.0),    # the chest
	Vector4(0.95, 0.90, 2.8, 0.0),
	Vector4(1.0, 1.0, 2.0, 0.0), Vector4(1.0, 1.0, 2.0, 0.0), Vector4(1.0, 1.0, 2.0, 0.0),
	Vector4(1.0, 1.0, 2.0, 0.0), Vector4(1.0, 1.0, 2.0, 0.0), Vector4(1.0, 1.0, 2.0, 0.0),
]
# How far toward the front a corner is (−z over the half depth) before the front's
# drop reaches it: the front panel's two corners and no others.
const _TORSO_FRONT_PANEL: float = 0.9
# The pelvis, in the waist's space (y 0 is the trunk's fold pivot, the hip
# pivots sit at −0.13): the pants from the waistband down, and the seat the
# torso does NOT carry. A real pelvis does not fold with the spine, so this one
# does not fold with the torso (SkaterArmRig.repose_bone leaves it out of the
# texture) and fills the seat at every angle.
#
# Under a loose jersey it hides entirely, even with the trunk twisted on it: both
# lathes are wider than deep, so the waistband is narrow enough that its wide
# axis fits the jersey's deep one. A tuck goes in at the waistband, and stands
# the waistband and its lip up into the pad (SkaterJerseyHem.pad_ring).
const _PELVIS_PROFILE: Array[Vector2] = [
	Vector2(0.056, 0.184),   # the lip, turned in off the waistband's top
	Vector2(0.050, 0.186),   # the waistband, just over the jersey's belt line
	Vector2(0.000, 0.190),
	Vector2(-0.060, 0.196),
	Vector2(-0.120, 0.205),  # the seat
	Vector2(-0.170, 0.190),
	Vector2(-0.215, 0.152),  # the leg line
	Vector2(-0.260, 0.100),  # buried in the thighs
]
# Hockey-butt sway, peaked at the seat.
const _PELVIS_REAR_SWAY: Array[float] = [0.006, 0.006, 0.010, 0.016, 0.028, 0.024, 0.012, 0.0]

# The thigh, with the hip joint on top of it. The upper four stations are a
# DOME centred on the hip pivot (_HIP_PIVOT_IN_THIGH above the part's origin,
# _THIGH_DOME_RADIUS across): a sphere centred on the joint it turns about is
# the one shape whose surface does not move when the leg does, so it seals the
# hip at any splay or stride angle — where the pelvis, being static, cannot
# follow the leg out. It replaces the hip ball, which used to do this job as a
# separate part, and is why the pants' side stripe now runs up over the hip
# instead of stopping at it.
# test_skater_scene_mirrors.gd holds the dome on the pivot the scene authors.
const _HIP_PIVOT_IN_THIGH: float = 0.13
const _THIGH_DOME_RADIUS: float = 0.150
const _THIGH_PROFILE: Array[Vector2] = [
	Vector2(0.275, 0.038),   # dome pole, buried in the pelvis
	Vector2(0.240, 0.102),
	Vector2(0.190, 0.137),
	Vector2(0.130, 0.150),   # the hip pivot — the dome's equator
	Vector2(0.050, 0.150),   # breezers: no taper below the hip — the thigh guard holds them out
	Vector2(-0.080, 0.152),
	Vector2(-0.125, 0.152),
	Vector2(-0.150, 0.136),  # the leg hem, turned in over the shin guard
]
const _SOCK_PROFILE: Array[Vector2] = [
	Vector2(0.150, 0.088),
	Vector2(0.070, 0.094),   # calf bulge
	Vector2(-0.040, 0.086),
	Vector2(-0.150, 0.076),  # ankle
]
# The collar ENDS just below its node origin: the scene seats that origin at
# the boot's heel-top line, so the cuff perches ON the boot with ~1 cm of
# overlap seal instead of dropping past the heel as a column.
const _SKATE_PROFILE: Array[Vector2] = [
	Vector2(0.100, 0.090),   # boot collar
	Vector2(0.020, 0.082),
	Vector2(-0.010, 0.078),
]

# Chest reads wider than deep — lateral/depth scale on the torso lathe. The
# legs keep circular sections (hockey pants and socks are round enough).
const _TORSO_X_SCALE: float = 1.05
const _TORSO_Z_SCALE: float = 0.88

const _TORSO_SIDES: int = 10
const TORSO_SIDES: int = _TORSO_SIDES
# Half a facet: the torso's rings turn so a flat face, not an edge, is under the
# name and number. U still starts at vertex 0; the material's offset adds it.
const TORSO_U_PHASE: float = 0.5 / _TORSO_SIDES
const _LEG_SIDES: int = 8

# Head + helmet. One mesh on the HELMET bone: the shell on surface 0 (painted
# the kit's helmet color, scaled by the appearance rig) and the head/neck skin
# on surface 1, so both share its transform. The
# shell's lower edge varies with azimuth — flat at brow height around the
# face and temples, dropping to the nape over the back arc — see the rim
# profile constants below (latitudes are equirect fractions; θ = 0 is +Z,
# the back).
const _HELMET_RADIUS: float = 0.155
# Rim profile, anchored to head anatomy (head r 0.135, eye line ≈ the
# equator): the rim holds FLAT at the brow latitude (y ≈ +0.048, above the
# eye line) from the face around the temples, then smoothsteps down over the
# back arc to the nape — the hockey-helmet shape, rather than a cosine that
# starts sinking immediately off the brow. The drop engages where cos(θ)
# (−1 at the face, +1 at the back) crosses _HELMET_DROP_START_C — about 70°
# either side of dead back.
const _HELMET_FRONT_CUT: float = 0.40
const _HELMET_BACK_CUT: float = 0.76
const _HELMET_DROP_START_C: float = 0.34
# Ear loops: a localized rim dip centered on each side (|sin θ| = 1),
# narrowed by the exponent so it reads as an ear cover, not a lower brim.
# At the nearest sampled azimuths the dip reaches ear-top depth (y ≈ −0.03);
# it fades to nothing at the face and inside the nape drop.
const _HELMET_EAR_DIP: float = 0.22
const _HELMET_EAR_DIP_POWER: float = 6.0
# The shell closes with a fan to an apex HIGH inside the dome (this fraction
# of the radius up), not a floor at rim height — a low floor reads as a
# helmet-colored lid across the face opening from the top-down camera,
# hiding the head entirely. High, the closure is an interior liner you only
# glimpse near the rim.
const _HELMET_LINER_APEX_FRAC: float = 0.5
const _HELMET_LON: int = 10
const HEAD_RADIUS: float = 0.135
# The head ball's facet grid (_build_ball's lon × lat). SkaterFaceMesh and
# SkaterHairMesh lay their pieces on these same facets.
const HEAD_LON: int = 10
const HEAD_LAT: int = 5
# The head sits this far forward of the helmet center (real faces do) so the
# face shows near-flush in the brow opening instead of recessed 2 cm behind
# the rim. Capped by clearance: forward offset + HEAD_RADIUS must stay under
# _HELMET_RADIUS or the face pokes through the shell at the front equator.
const HEAD_FORWARD_M: float = 0.015

# A loose sleeve's radius at its full-width end; Skater, the cap and the lobby
# figures read it. The elbow pad only fills the bend, just proud of it.
const SLEEVE_RADIUS_M: float = 0.080
const ELBOW_PAD_RADIUS_M: float = SLEEVE_RADIUS_M * 1.04

# Shoulder cap: the pad under the sleeve. Its +Y end (SkaterArmRig points it
# into the trap) is a blunt base tucked under the torso's trapezius slope; the
# −Y end stays at the sleeve's radius so the cap flows into the upper arm. The
# origin is the arm root, so the profile sits below it to continue the
# neck-to-arm slope. Stations are (y, radius, equirect v), v keeping the sphere
# mapping the shoulder number paints against, its band on the equator.
const _SHOULDER_PROFILE: Array[Vector3] = [
	Vector3(0.050, 0.056, 0.12),   # blunt torso-side base (flat-capped)
	Vector3(0.025, 0.080, 0.30),
	Vector3(-0.015, 0.090, 0.50),  # equator — the number band
	Vector3(-0.060, 0.088, 0.68),
	Vector3(-0.105, 0.084, 0.85),
	Vector3(-0.140, SLEEVE_RADIUS_M, 1.0),   # arm-side end, at the sleeve's own radius
]

# The yoke crosses the cap at its second ring, so the top of the shoulder
# matches the jersey and the cap's own color starts below it.
const SHOULDER_CAP_YOKE_V: float = _SHOULDER_PROFILE[1].z
# The RIGHT cap's origin in the torso bone's frame as Scenes/Skater.tscn places
# both (ShoulderR less UpperBodyMesh; x mirrors for the left): the sleeve's
# shoulder pivot.
const _CAP_IN_TORSO := Vector3(0.22, 0.205, 0.0)
# The standalone cap lathe's facets round its pole (_build_shoulder).
const _CAP_LON: int = 10
# The cap's rest pole in upper-body space for the RIGHT cap (x mirrors for the
# left): down, a touch outboard and forward — the deltoid's hang on a relaxed
# arm, and the hang the sleeve is authored at.
const SHOULDER_CAP_REST_POLE := Vector3(0.32, -0.93, -0.17)


# A cap's basis with its +Y on `pole` and its X as near world +X as that allows,
# where each side's shoulder decal picks its outboard face by uv1_offset, as at
# identity.
static func shoulder_cap_basis(pole: Vector3) -> Basis:
	var x_axis: Vector3 = (Vector3.RIGHT - pole * pole.x).normalized()
	return Basis(x_axis, pole, x_axis.cross(pole)).orthonormalized()


# The cap on `side` (−1 left, +1 right) hanging at rest.
static func shoulder_cap_rest(side: float) -> Basis:
	var rest: Vector3 = SHOULDER_CAP_REST_POLE.normalized()
	rest.x *= side
	return shoulder_cap_basis(-rest)

# The knee: the sock carried up through the joint, so thigh and shin read as
# one leg. Stations are (y, radius, kneecap) in the KNEE bone's frame, whose
# origin is the knee pivot. Rings at or below _KNEE_STITCH_Y ride the shin (the
# SOCK bone, _KNEE_ABOVE_SOCK below the pivot), the one above it the thigh, deep
# in the pants leg, so a bend stretches the band between them instead of
# opening a gap. The bottom ring is the sock's top ring exactly. `kneecap` is
# how far the shin guard's cap stands proud at the front, on the shin, as the
# real cap is.
const _KNEE_PROFILE: Array[Vector3] = [
	Vector3(0.075, 0.088, 0.0),     # inside the pants leg, on the thigh
	Vector3(0.040, 0.090, 0.010),
	Vector3(0.010, 0.094, 0.022),   # the cap's crown, at the pivot
	Vector3(-0.020, 0.092, 0.012),
	Vector3(-0.040, 0.088, 0.0),    # = _SOCK_PROFILE[0], in the sock's frame
]
const _KNEE_STITCH_Y: float = 0.06
# SockL's drop below the knee pivot in Scenes/Skater.tscn (test_skater_scene_mirrors).
const _KNEE_ABOVE_SOCK: float = 0.19

# Gloved fist, swept along local Y from the wrist (+Y, toward the elbow) to the
# curled fingertips, its knuckle roll across local X; SkaterArmRig.glove_basis
# aims it. UNIT-scale (stations are y, half_w, half_d multiples of
# hand_sphere_radius). A fist off the stick takes its roll from world up, so the
# section stays near-square: no face of it can be the back of the hand or carry
# a thumb.
const _GLOVE_FINGER_STATION: int = 3
# The fist's width across the knuckle roll, in hand radii.
const GLOVE_FIST_SPAN: float = 2.2
# The fist's and cuff's chamfered box section (_octagon_loop's face/side fracs).
const _GLOVE_FACE_FRAC: float = 0.6
const _GLOVE_SIDE_FRAC: float = 0.55
const _GLOVE_FIST_STATIONS: Array[Vector3] = [
	Vector3(0.95, 0.94, 0.86),    # wrist end, inside the cuff
	Vector3(0.55, 1.08, 0.98),    # back of the hand
	Vector3(0.12, GLOVE_FIST_SPAN * 0.5, 1.00),    # knuckle roll
	Vector3(-0.05, 1.00, 0.92),   # seam — the back / fingers split
	Vector3(-0.38, 1.06, 0.98),   # finger roll
	Vector3(-0.78, 0.96, 0.90),
	Vector3(-1.0, 0.70, 0.66),    # fingertips, turned under
]

# The glove on the arm, for every placer of it (the live rig through Skater's
# defaults, the locker mannequin, the lobby dummies): the cuff's center sits
# GLOVE_CUFF_BACK_M up the forearm from the fist's, spanning 0.05–0.13 m.
const GLOVE_FIST_RADIUS_M: float = 0.064
const GLOVE_CUFF_RADIUS_M: float = SLEEVE_RADIUS_M * 1.2
const GLOVE_CUFF_BACK_M: float = 0.09

# Arm-rig fixed dimensions. The cuff/knob heights are placement inputs on the
# skater side (SkaterArmRig._pose_cuff / SkaterStickRig offset along the bone by
# half the height), so they live here with the geometry they measure.
const _ARM_TAPER: float = 0.88   # distal end radius fraction (top of mesh = proximal)
# The forearm is the arm bone with a wrist: from 0.3 L off the hand it necks
# down to a radius the fist hides by 0.2 L, so the sleeve stops in the glove. The
# cuff is metric, so the neck must start under it (0.3 L <= 0.13 m) and be thin
# before it ends (0.2 L >= 0.05 m): forearms of 0.25–0.43 m
# (test_glove_hides_the_sleeve.gd).
const _FOREARM_PROFILE: Array[Vector2] = [
	Vector2(0.5, 1.0),
	Vector2(-0.2, 1.0 - (1.0 - _ARM_TAPER) * 0.7),   # on the plain taper
	Vector2(-0.3, 0.6),
	Vector2(-0.5, 0.6),
]
const CUFF_HEIGHT_M: float = 0.08
const KNOB_HEIGHT_M: float = 0.05
const _KNOB_TOP_RADIUS: float = 0.035
const _KNOB_BOTTOM_RADIUS: float = 0.03

# Boot stations heel→toe in the Foot node's local frame. That node's scene
# transform is rotated: local −Y is the toe direction, local +Z is DOWN, X is
# lateral (see the FootL/R note in SkaterAppearanceCoordinator). Each station
# is (y, half_width, top_z, sole_z) — top_z is negative (up), sole_z positive
# (down). Envelope matches the prolate foot sphere it replaces (r 0.08, half
# length 0.125).
# Station the toe cap starts at — the boot sweep commits stations 0..N as the
# quarter and N..last as the cap, so the two pieces share this ring and meet
# with no gap. The front band is the whole cap, which is the proportion a real
# toe cap covers.
const _BOOT_TOE_STATION: int = 3
const _BOOT_STATIONS: Array[Vector4] = [
	# Heel top rises toward the collar like a real boot's quarter, meeting the
	# collar's bottom so ankle and boot read as one piece from the side. The
	# rearmost station runs the quarter back UNDER the collar's footprint (the
	# cuff seats 0.10 heel-ward of this frame's origin, so its underside
	# otherwise hangs bare behind the heel) — sole tucked well up so the
	# stride's heel-kick arc can't drag it through the ice.
	Vector4(0.155, 0.042, -0.062, 0.030),   # heel counter, under the cuff
	Vector4(0.115, 0.052, -0.070, 0.045),   # heel
	Vector4(0.045, 0.060, -0.072, 0.046),   # instep rise
	Vector4(-0.045, 0.058, -0.048, 0.046),  # forefoot
	Vector4(-0.115, 0.040, -0.012, 0.040),  # toe
]
# Skate blade — its own steel-colored child mesh under each Foot node (the
# boot paints dark, so a fused same-color fin never read as a blade). Same
# rotated frame as _BOOT_STATIONS: toe −Y, +Z down. The holder's two towers
# drop from the sole and are bridged by a bottom rail, leaving the arch open
# between them; the thin runner spans the length and bottoms out at the
# replaced sphere's ice-contact depth (z = 0.080).
#
# A MID gray: the holder is a paintable zone, so a near-white runner under a
# white holder would lose the skate's bottom edge entirely. Dark enough to
# separate from GearModelRegistry.WHITE, bright enough to read against a black
# boot. Public so the display figures (FigureKit) and the gear capture tool
# dress their runners from this one constant rather than a copy.
const BLADE_STEEL_COLOR := Color(0.62, 0.66, 0.70)
# On-skates stance lift: the scene's part layout is tuned as STANDING height,
# so the skate stack raises both body roots (applied in Skater._ready before
# the default-height captures — the same root-raise mechanism the height
# attribute uses) and the blade assembly reaches this much deeper than the
# old foot-sphere ice contact (z 0.080). The authored chain still bottoms out
# ~3 cm above the ice; what puts the steel on it is the visible hips' contact
# solve (SkaterLegRig.seat_on_ice), not this number.
const SKATE_LIFT_M: float = 0.04
# The runner's bottom edge in the FOOT bone's frame (toe −Y, +Z down): the line
# the blade touches the ice along, and what the contact solve seats on it.
const BLADE_ICE_Z: float = 0.080 + SKATE_LIFT_M
const RUNNER_TOE_Y: float = -0.088
const RUNNER_HEEL_Y: float = 0.098
# Skate accent stripe (see shared_skate_stripe): band height, its center on
# the collar's local Y, and a radius just proud of the collar's sidewall at
# that height (~0.085) so the band never z-fights the lathe under it.
const SKATE_STRIPE_HEIGHT_M: float = 0.04
const _SKATE_STRIPE_Y: float = 0.045
const _SKATE_STRIPE_RADIUS: float = 0.092
# Skate laces, drawn-on as geometry: thin rungs laid across the instep, each
# (y, z) pair the rung's center on the boot's top line — z interpolated from
# the _BOOT_STATIONS top_z at that y, so every rung seats on the surface it
# crosses (ankle → forefoot). _LACE_COLOR is only the pre-uniform placeholder;
# the gear style's lace pick repaints them (SkaterUniformCoordinator).
const _LACE_RUNGS: Array[Vector2] = [
	Vector2(0.070, -0.0711),
	Vector2(0.035, -0.0693),
	Vector2(0.000, -0.0600),
	Vector2(-0.035, -0.0507),
]
const _LACE_HALF_W: float = 0.030
const _LACE_HALF_T: float = 0.006   # rung thickness along the instep (local Y)
# Rung depth is biased PROUD of the surface rather than centered on it: the
# top line slopes ~0.46 across the heel→instep segment, so a surface-centered
# box leaves barely 2 mm showing there. Sink keeps the underside buried so no
# gap opens as the slope crosses the rung.
const _LACE_PROUD: float = 0.008    # rise above the top surface
const _LACE_SINK: float = 0.003     # burial below it
const _LACE_COLOR := Color(0.88, 0.88, 0.86)

# Neck: skin tube from chin to collar, a child of the Helmet node like the
# head so it rides the same head-bulk scaling and skeleton offsets. Stations
# are helmet-local (helmet origin y 0.65, torso top 0.47): the top hides
# inside the head ball, the bottom flares into the traps where it sinks
# into the torso.
const NECK_PROFILE: Array[Vector2] = [
	Vector2(-0.095, 0.064),
	Vector2(-0.155, 0.070),
	Vector2(-0.190, 0.092),  # trapezius flare into the collar
	Vector2(-0.225, 0.092),  # sunk under the collar, whose front is low
]

static var _cache: Dictionary = {}


# Swaps a scene primitive for a generated build, in place. Used by the goalie
# and the puck, which hang meshes on nodes; every skater part is a surface of a
# skinned rig and never comes through here.
static func _swap(root: Node3D, path: String, key: String, builder: Callable) -> void:
	_swap_instance(root.get_node_or_null(path) as MeshInstance3D, key, builder)


static func _swap_instance(mi: MeshInstance3D, key: String, builder: Callable) -> void:
	if mi == null:
		return
	var built: ArrayMesh = _shared(key, builder)
	# Carry the scene primitive's material onto the shared build so the part
	# keeps its editor default color until apply_uniform overrides it.
	var prim: PrimitiveMesh = mi.mesh as PrimitiveMesh
	if prim != null and prim.material != null and built.surface_get_material(0) == null:
		built.surface_set_material(0, prim.material)
	mi.mesh = built


static func _shared(key: String, builder: Callable) -> ArrayMesh:
	var built: ArrayMesh = _cache.get(key)
	if built == null:
		built = builder.call()
		_cache[key] = built
	return built


# ── Arm-rig meshes (unit radius — size with node scale, never mesh mutation) ──


# Bone prism for the arm wrappers: unit height (the wrapper's per-frame Z
# scale stretches it to the bone length), unit proximal radius (the visual's
# X/Z scale sets thickness), tapering toward the distal end — look_at points
# both bones' mesh-top at the proximal joint. Side UVs follow the cylinder
# convention because the uniform's sleeve stripes wrap on it.
static func shared_arm_bone() -> ArrayMesh:
	return _shared("arm_bone", func() -> ArrayMesh:
		var profile: Array[Vector2] = [Vector2(0.5, 1.0), Vector2(-0.5, _ARM_TAPER)]
		return _radial_side_normals(_build_lathe(profile, _LEG_SIDES, 1.0, 1.0)))


# The forearm's prism (_FOREARM_PROFILE): its rings sit on the plain bone's
# taper and V, so a sleeve's stripes land where they did.
static func shared_forearm_bone() -> ArrayMesh:
	return _shared("forearm_bone", func() -> ArrayMesh:
		return _radial_side_normals(_build_lathe(_FOREARM_PROFILE, _LEG_SIDES, 1.0, 1.0)))


# Rewrites a Y-axis solid's SIDE normals to be purely radial — no component
# along the axis — leaving the caps alone. Only the arm bones and the glove cuff
# need this, and they need it because they are the parts whose scale is
# strongly non-uniform.
#
# Godot's skinning transforms a normal by the bone matrix itself, not by its
# inverse transpose (an ordinary MeshInstance3D gets the proper normal matrix).
# Under a bone scale of (r, r, length) that skews any normal with an axial
# component the WRONG way and by the ratio length/r — about 4:1 on an arm — so
# the 6.8° taper cone shaded as a 27° one, and worse, the shading then changed
# with the bone's length as the arm stretched on an over-reach.
#
# A normal with no axial component is immune: scaling it by (r, r, length)
# multiplies it by r and normalizes back to itself.
#
# Baking the sides radial is not the art compromise it looks like: the proper
# normal matrix divides the axial component by length and the radial one by r,
# so at an arm's r/length (~0.23) the 6.8° taper already flattens to 1.6° off
# radial. What baking buys is that the shading stops depending on r/length at
# all, so an over-reach that stretches the forearm cannot change how it is lit.
static func _radial_side_normals(src: ArrayMesh) -> ArrayMesh:
	var arrays: Array = src.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in normals.size():
		var n: Vector3 = normals[i]
		# Caps point straight up the axis; flattening them would zero them.
		if absf(n.y) > 0.99:
			continue
		n.y = 0.0
		normals[i] = n.normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# ── The leg rig: one skinned mesh, sixteen bones ─────────────────────────────
# Unlike the upper rig (UpperBone, flat), the legs are a CHAIN: LegL/R carry hip
# pitch and roll, ShinL/R hang off them and carry the knee, and the six meshes
# per leg ride whichever of the two they belong to. Keep the parents below
# mirroring that — flattening the chain means re-deriving the shin's world frame
# by hand on every gait tick.
#
# Bone order is L then R, pivot first. LEG_* and SHIN_* carry no vertices; they
# exist to be rotated.
enum LegBone {
	LEG_L, THIGH_L, KNEE_L, SHIN_L, SOCK_L, SKATE_L, FOOT_L,
	LEG_R, THIGH_R, KNEE_R, SHIN_R, SOCK_R, SKATE_R, FOOT_R,
}
const LEG_BONE_COUNT: int = 14
# Parent per bone, index-aligned with LegBone. -1 = the HIPS bone
# (SkaterBodySkeleton).
const LEG_BONE_PARENT: Array[int] = [
	-1, LegBone.LEG_L, LegBone.LEG_L,
	LegBone.LEG_L, LegBone.SHIN_L, LegBone.SHIN_L, LegBone.SHIN_L,
	-1, LegBone.LEG_R, LegBone.LEG_R,
	LegBone.LEG_R, LegBone.SHIN_R, LegBone.SHIN_R, LegBone.SHIN_R,
]
# Scene node name per bone, index-aligned with LegBone. SkaterLegRig.build
# reads each one's local transform before freeing the subtree, so the .tscn stays
# the place leg proportions are authored.
const LEG_BONE_NODE: Array[String] = [
	"LegL", "LegL/ThighL", "LegL/KneeL",
	"LegL/ShinL", "LegL/ShinL/SockL", "LegL/ShinL/SkateL", "LegL/ShinL/FootL",
	"LegR", "LegR/ThighR", "LegR/KneeR",
	"LegR/ShinR", "LegR/ShinR/SockR", "LegR/ShinR/SkateR", "LegR/ShinR/FootR",
]

# Surfaces of the leg mesh. Not one per bone: the skate collar carries its accent
# stripe, and the boot carries its toe cap, its blade holder, its steel runner
# and its laces — so those parts contribute several surfaces to one bone. Each
# extra surface is a piece a gear MODEL paints on its own (GearModelRegistry);
# the runner is the exception that stays steel by construction.
enum LegSurface {
	THIGH_L, KNEE_L, SOCK_L,
	SKATE_L_COLLAR, SKATE_L_STRIPE,
	FOOT_L_SHELL, FOOT_L_TOE, FOOT_L_HOLDER, FOOT_L_RUNNER, FOOT_L_LACES,
	THIGH_R, KNEE_R, SOCK_R,
	SKATE_R_COLLAR, SKATE_R_STRIPE,
	FOOT_R_SHELL, FOOT_R_TOE, FOOT_R_HOLDER, FOOT_R_RUNNER, FOOT_R_LACES,
}
const LEG_SURFACE_COUNT: int = 20


static func shared_leg_skin_mesh() -> ArrayMesh:
	return _shared("leg_skin", func() -> ArrayMesh:
		var m := ArrayMesh.new()
		var thigh: ArrayMesh = _shared("thigh", _build_thigh)
		var knee: ArrayMesh = _shared("knee", _build_knee)
		var sock: ArrayMesh = _shared("sock", _build_sock)
		var skate: ArrayMesh = shared_skate_assembly()
		var boot: ArrayMesh = shared_boot_assembly()
		# Appended in LegSurface order — see the enum.
		for side: int in 2:
			var leg: int = LegBone.LEG_L if side == 0 else LegBone.LEG_R
			var shin: int = LegBone.SHIN_L if side == 0 else LegBone.SHIN_R
			_append_skinned_surface(m, thigh, leg + 1)
			_append_knee_surface(m, knee, leg + 2, shin + 1)
			_append_skinned_surface(m, sock, shin + 1)
			_append_skinned_surface(m, skate, shin + 2, SKATE_SURF_COLLAR)
			_append_skinned_surface(m, skate, shin + 2, SKATE_SURF_STRIPE)
			_append_skinned_surface(m, boot, shin + 3, BOOT_SURF_SHELL)
			_append_skinned_surface(m, boot, shin + 3, BOOT_SURF_TOE)
			_append_skinned_surface(m, boot, shin + 3, BOOT_SURF_HOLDER)
			_append_skinned_surface(m, boot, shin + 3, BOOT_SURF_RUNNER)
			_append_skinned_surface(m, boot, shin + 3, BOOT_SURF_LACES)
		return m)


# The legs as the rig draws them: every LegSurface as one zone of one surface
# (BodyZoneMesh), painted by the skater's BodyZonePaint. Zone = LegSurface.
static func shared_leg_body_mesh() -> ArrayMesh:
	return _shared("leg_body", func() -> ArrayMesh:
		return BodyZoneMesh.merge(shared_leg_skin_mesh(), 0))


static func shared_leg_skin() -> Skin:
	if _leg_skin == null:
		_leg_skin = Skin.new()
		for i: int in LEG_BONE_COUNT:
			_leg_skin.add_bind(SkaterBodySkeleton.LEG_BONE_OFFSET + i, Transform3D.IDENTITY)
	return _leg_skin


static var _leg_skin: Skin = null


# ── Merged assemblies ────────────────────────────────────────────────────────
# A part that never moves relative to its parent is a SURFACE, not a node, even
# when it needs its own material (the steel runner, the gear-coloured laces).
# These hang under a foot the gait moves every frame, so a node would cost a
# transform propagation and a global recompute, per skater, per frame.
#
# NON-NEGOTIABLE for any merged mesh: nothing may set material_override on it.
# That property overrides EVERY surface at once, so it would erase the steel and
# the laces the moment the boot was painted. The parent's own colour lives on
# surface 0 like everything else — see SkaterUniformCoordinator's BOOT_* slots.
const BOOT_SURF_SHELL: int = 0
const BOOT_SURF_TOE: int = 1
const BOOT_SURF_HOLDER: int = 2
const BOOT_SURF_RUNNER: int = 3
const BOOT_SURF_LACES: int = 4
const SKATE_SURF_COLLAR: int = 0
const SKATE_SURF_STRIPE: int = 1
# Surfaces WITHIN a part mesh, for the three parts that split into pieces a
# gear model paints separately (see _build_boot / _build_skate_blade /
# shared_glove_fist).
const BOOT_PART_QUARTER: int = 0
const BOOT_PART_TOE: int = 1
const BLADE_PART_HOLDER: int = 0
const BLADE_PART_RUNNER: int = 1
const FIST_PART_BACK: int = 0
const FIST_PART_FINGERS: int = 1
const HELMET_SURF_SHELL: int = 0
const HELMET_SURF_SKIN: int = 1


# The per-instance material for one surface, created from the surface's shared
# default on first use. Every writer must go through this: the default lives on
# the CACHED mesh that all skaters share, so painting it directly would repaint
# the whole roster. Returns a material that is safe to mutate.
static func surface_override(mesh: MeshInstance3D, surface: int) -> StandardMaterial3D:
	var mat: StandardMaterial3D = mesh.get_surface_override_material(surface) as StandardMaterial3D
	if mat != null:
		return mat
	var shared: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
	mat = shared.duplicate() as StandardMaterial3D if shared != null else StandardMaterial3D.new()
	mesh.set_surface_override_material(surface, mat)
	return mat


static func shared_skate_assembly() -> ArrayMesh:
	return _shared("skate_assembly", _build_skate_assembly)


static func _build_skate_assembly() -> ArrayMesh:
	var m := ArrayMesh.new()
	_append_surface(m, _shared("skate", _build_skate))
	# The stripe carried its offset and radius as node transform, so unlike the
	# boot's parts it has to be baked. Safe because the collar's own scaling is
	# axis-aligned and the stripe has no rotation — diagonal scales commute, so
	# baking cannot shear it the way a rotated child would.
	_append_surface(m, shared_skate_stripe(), Transform3D(
			Basis.IDENTITY.scaled(Vector3(_SKATE_STRIPE_RADIUS, 1.0, _SKATE_STRIPE_RADIUS)),
			Vector3(0.0, _SKATE_STRIPE_Y, 0.0)))
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.08, 0.08, 0.08)
	stripe.roughness = 0.42
	BodyRim.apply(stripe)
	m.surface_set_material(SKATE_SURF_STRIPE, stripe)
	return m


# The head ball and its face, centred on the origin, face toward −Z, white but
# for the features' tints under the skin material. The keeper wears it inside
# his mask.
static func shared_head() -> ArrayMesh:
	return _shared("head", _build_head)


static func shared_helmet_assembly() -> ArrayMesh:
	return _shared("helmet_assembly", _build_helmet_assembly)


static func _build_helmet_assembly() -> ArrayMesh:
	var m := ArrayMesh.new()
	_append_surface(m, _shared("helmet", _build_helmet))
	# Head and neck were separate nodes but always wore the SAME skin material,
	# so they collapse into one surface rather than two — one skin colour to
	# paint, and Skater.set_skin_tone has a single target.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_shared("head", _build_head), 0,
			Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -HEAD_FORWARD_M)))
	st.append_from(SkaterFaceMesh.untinted(_shared("neck", _build_neck)), 0, Transform3D.IDENTITY)
	st.commit(m)
	m.surface_set_material(HELMET_SURF_SKIN, _make_skin_mat())
	return m


static func shared_boot_assembly() -> ArrayMesh:
	return _shared("boot_assembly", _build_boot_assembly)


static func _build_boot_assembly() -> ArrayMesh:
	var m := ArrayMesh.new()
	var boot: ArrayMesh = _shared("boot", _build_boot)
	var blade: ArrayMesh = _shared("skate_blade", _build_skate_blade)
	_append_surface(m, boot, Transform3D.IDENTITY, BOOT_PART_QUARTER)
	_append_surface(m, boot, Transform3D.IDENTITY, BOOT_PART_TOE)
	_append_surface(m, blade, Transform3D.IDENTITY, BLADE_PART_HOLDER)
	_append_surface(m, blade, Transform3D.IDENTITY, BLADE_PART_RUNNER)
	_append_surface(m, shared_laces())
	# Defaults for the merged surfaces, standing in for the material_override
	# their child nodes used to carry — so an unpainted rig (a spawn before the
	# uniform pass) still shows steel and white laces rather
	# than untextured white. Surface 0 is left null on purpose: _swap_instance
	# carries the scene primitive's material onto it, exactly as before.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = BLADE_STEEL_COLOR
	steel.roughness = 0.25
	BodyRim.apply(steel)
	m.surface_set_material(BOOT_SURF_RUNNER, steel)
	var lace := StandardMaterial3D.new()
	lace.albedo_color = _LACE_COLOR
	lace.roughness = 0.9
	BodyRim.apply(lace)
	m.surface_set_material(BOOT_SURF_LACES, lace)
	return m


# Appends one surface of `src` to `target` as a new surface. Callers that pass
# no transform rely on the part already sitting at identity in its parent's
# frame, which is what keeps the merge geometry-preserving.
static func _append_surface(target: ArrayMesh, src: ArrayMesh,
		xform: Transform3D = Transform3D.IDENTITY, src_surface: int = 0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(src, src_surface, xform)
	st.commit(target)


# ── The upper-body rig: one skinned mesh ─────────────────────────────────────
# Fifteen bones of the body skeleton — both arms, the torso, the helmet/head
# unit, the two deltoid caps, the pelvis — driving one mesh, so posing a part costs an entry in
# the skeleton's pose array rather than a Node3D transform write (which dirties
# a subtree and pushes a global to the RenderingServer).
#
# Four properties make a pose write mean a plain local transform, and all four
# have to hold: every vertex is weighted 1.0 to a single bone (the jersey's tail is
# the one exception — SkaterJerseyHem), the bone rests
# are identity, the skin binds are identity, and each part's geometry is left in
# its own local space. A skinned vertex is then exactly `bone_pose * v`. The
# sleeves are the other exception: authored in the torso's frame with their
# bones' rest poses as binds, so they blend across the shoulder (see the
# sleeve's section below).
#
# The shell parts hang from the SPINE bone and the pelvis from WAIST
# (SkaterBodySkeleton.upper_bone_parent); their poses are authored in a space that equals the old
# UpperBody space while those two rest at identity. The arm parts are roots,
# placed by IK straight in skeleton space.
enum UpperBone {
	TOP_UPPER_ARM,
	TOP_FOREARM,
	BOTTOM_UPPER_ARM,
	BOTTOM_FOREARM,
	TOP_ELBOW,
	BOTTOM_ELBOW,
	TOP_HAND,
	BOTTOM_HAND,
	TOP_CUFF,
	BOTTOM_CUFF,
	TORSO,
	HELMET,
	SHOULDER_L,
	SHOULDER_R,
	PELVIS,
}
const UPPER_BONE_COUNT: int = 15
# The upper skin's binds for the jersey's tail, after the parts' own: TAIL, then
# two per torso facet column — the segment from the belt to the bend, then the
# one from the bend to the hem (SkaterBodySkeleton.column_bone, in that order).
const UPPER_TAIL_BIND: int = UPPER_BONE_COUNT
const UPPER_COLUMN_BIND_BASE: int = UPPER_BONE_COUNT + 1
# Then the sleeves' (_append_sleeve), SLEEVE_PARTS per side, left first.
const UPPER_SLEEVE_BIND: int = UPPER_COLUMN_BIND_BASE + 2 * _TORSO_SIDES

# Surfaces. One per bone for the first thirteen; the helmet is the exception,
# carrying the shell and the head/neck skin as two surfaces of one bone (they
# never move relative to each other, they only need separate materials).
#
# The two FINGERS surfaces ride the hand bones but are listed LAST, out of
# anatomical order, on purpose: for the first ten entries a surface index and
# its bone index coincide, and the uniform painter passes UpperBone values to
# the surface seams on the strength of it. Inserting the fingers next to the
# hands would break that silently. Append new arm surfaces here, at the end.
enum UpperSurface {
	TOP_UPPER_ARM,
	TOP_FOREARM,
	BOTTOM_UPPER_ARM,
	BOTTOM_FOREARM,
	TOP_ELBOW,
	BOTTOM_ELBOW,
	TOP_HAND,
	BOTTOM_HAND,
	TOP_CUFF,
	BOTTOM_CUFF,
	TORSO,
	HELMET_SHELL,
	HELMET_SKIN,
	SHOULDER_L,
	SHOULDER_R,
	TOP_FINGERS,
	BOTTOM_FINGERS,
	PELVIS,
}
const UPPER_SURFACE_COUNT: int = 18
# The body's paint zones: the leg surfaces, then the upper ones.
const UPPER_ZONE_BASE: int = LEG_SURFACE_COUNT
const BODY_ZONE_COUNT: int = LEG_SURFACE_COUNT + UPPER_SURFACE_COUNT
# Scene node name per bone for the four parts whose placement is authored in
# Scenes/Skater.tscn rather than derived (the arm parts are placed by IK). Read
# by SkaterArmRig.build, which then frees them — same deal as LEG_BONE_NODE.
# Indices 0-9 are unused; the arm parts have no scene node.
const UPPER_BONE_NODE: Array[String] = [
	"", "", "", "", "", "", "", "", "", "",
	"UpperBodyMesh", "Helmet", "ShoulderL", "ShoulderR", "",
]


# One per GearModelRegistry TUCK_* option, alike but for the torso surface's
# drape, so a skater's tuck is which shared mesh it wears.
static func shared_upper_skin_mesh(tuck: int = GearModelRegistry.TUCK_NONE) -> ArrayMesh:
	if not GearModelRegistry.is_valid_tuck(tuck):
		tuck = GearModelRegistry.TUCK_NONE
	return _shared("upper_skin_%d" % tuck, func() -> ArrayMesh:
		var m := ArrayMesh.new()
		var fist: ArrayMesh = shared_glove_fist()
		var cuff: ArrayMesh = shared_cuff()
		var helmet: ArrayMesh = shared_helmet_assembly()
		var sleeves: Array[Dictionary] = [_sleeve(0), _sleeve(1)]
		# Appended in UpperSurface order. For the ten arm parts the surface index
		# and the bone index coincide, which is why they can share a number; the
		# sleeve's are the left's under TOP_ and the right's under BOTTOM_.
		_add_sleeve_surface(m, sleeves[0], SleeveSurface.UPPER_ARM)
		_add_sleeve_surface(m, sleeves[0], SleeveSurface.FOREARM)
		_add_sleeve_surface(m, sleeves[1], SleeveSurface.UPPER_ARM)
		_add_sleeve_surface(m, sleeves[1], SleeveSurface.FOREARM)
		_add_sleeve_surface(m, sleeves[0], SleeveSurface.ELBOW)
		_add_sleeve_surface(m, sleeves[1], SleeveSurface.ELBOW)
		_append_skinned_surface(m, fist, UpperBone.TOP_HAND, FIST_PART_BACK)
		_append_skinned_surface(m, fist, UpperBone.BOTTOM_HAND, FIST_PART_BACK)
		_append_skinned_surface(m, cuff, UpperBone.TOP_CUFF)
		_append_skinned_surface(m, cuff, UpperBone.BOTTOM_CUFF)
		var torso := ArrayMesh.new()
		SkaterJerseyHem.append_torso(torso, shared_torso(), shared_torso(tuck), tuck,
				TAU * TORSO_U_PHASE, UpperBone.TORSO, UPPER_TAIL_BIND, _TORSO_SIDES,
				UPPER_COLUMN_BIND_BASE, _TORSO_PROFILE[TORSO_BEND_STATION].x)
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
				_cut_armholes(torso.surface_get_arrays(0)))
		_append_skinned_surface(m, helmet, UpperBone.HELMET, HELMET_SURF_SHELL)
		_append_skinned_surface(m, helmet, UpperBone.HELMET, HELMET_SURF_SKIN)
		_add_sleeve_surface(m, sleeves[0], SleeveSurface.SHOULDER)
		_add_sleeve_surface(m, sleeves[1], SleeveSurface.SHOULDER)
		# Out of anatomical order — see the UpperSurface doc block.
		_append_skinned_surface(m, fist, UpperBone.TOP_HAND, FIST_PART_FINGERS)
		_append_skinned_surface(m, fist, UpperBone.BOTTOM_HAND, FIST_PART_FINGERS)
		_append_skinned_surface(m, shared_pelvis(tuck), UpperBone.PELVIS)
		return m)


# The upper body as the rig draws it: every UpperSurface as one zone of one
# surface, zone = UPPER_ZONE_BASE + UpperSurface.
static func shared_upper_body_mesh(tuck: int = GearModelRegistry.TUCK_NONE) -> ArrayMesh:
	if not GearModelRegistry.is_valid_tuck(tuck):
		tuck = GearModelRegistry.TUCK_NONE
	return _shared("upper_body_%d" % tuck, func() -> ArrayMesh:
		return BodyZoneMesh.merge(shared_upper_skin_mesh(tuck), UPPER_ZONE_BASE))


# The parts' binds are identity, so their skinned vertex is the bone pose alone
# (the tail's column bones are roots SkaterHemFlaps poses in skeleton space). The
# sleeves' binds are their bones' rest poses (sleeve_bind_pose), and name the
# arm bones of whichever arm is on that side: `top_on_right` is which way round
# the skater's handedness puts them. Shared by every skater of that handedness:
# Godot builds a per-instance SkinReference from one Skin resource.
static func shared_upper_skin(top_on_right: bool = true) -> Skin:
	var i: int = 1 if top_on_right else 0
	if _upper_skins[i] == null:
		var skin := Skin.new()
		for bone: int in UPPER_BONE_COUNT:
			skin.add_bind(bone, Transform3D.IDENTITY)
		skin.add_bind(SkaterBodySkeleton.TAIL_BONE, Transform3D.IDENTITY)
		for column: int in _TORSO_SIDES:
			for joint: int in 2:
				skin.add_bind(SkaterBodySkeleton.column_bone(column, joint),
						Transform3D.IDENTITY)
		for side_i: int in 2:
			for part: int in SLEEVE_PARTS:
				skin.add_bind(sleeve_bone(side_i, part, top_on_right),
						sleeve_bind_pose(side_i, part))
		_upper_skins[i] = skin
	return _upper_skins[i]


static var _upper_skins: Array[Skin] = [null, null]


# ── The sleeve: one skin from the torso's armhole to the wrist ───────────────
# docs/upper-body-skin-plan.md. Each side's sleeve is authored once, in the
# TORSO bone's frame at rest (default build, spine at identity, the arm hanging
# straight at the cap's rest pole), and bound to its bones by their rest poses,
# so a vertex can blend between any of them; the torso's own bind is identity
# because its mesh is already in that frame. It leaves the torso through an
# armhole whose loop IS the torso's own corners (_cut_armholes), and its
# surfaces share their boundary rings exactly, positions and weights, so nothing
# between the chest and the glove is a separate piece.

# The Skater defaults the sleeve is authored at (test_sleeve_is_one_piece).
const UPPER_ARM_REST_M: float = 0.33
const FOREARM_REST_M: float = 0.33
# UpperBodyMesh's place in Scenes/Skater.tscn: the TORSO bone's rest, and so the
# frame the sleeve is authored in.
const TORSO_REST_POS := Vector3(0.0, 0.195, 0.0)
# A cap's frame (+Y up the arm) as an arm prism's (+Z up the arm, X shared).
const CAP_TO_PRISM := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 1.0, 0.0))
enum SleevePart { DELTOID, UPPER_ARM, ELBOW, FOREARM }
const SLEEVE_PARTS: int = 4
enum SleeveSurface { SHOULDER, UPPER_ARM, ELBOW, FOREARM }
# The armhole: the torso's corners round each side's outermost one, between
# these two stations. Dropping the four quads they bound leaves a loop of eight
# corners, the sleeve's eight facets.
const ARMHOLE_TOP_STATION: int = 1
const ARMHOLE_BOTTOM_STATION: int = 3
# The torso ring corner pointing straight out at the right; the left's is half
# a turn on.
const _ARMHOLE_RIGHT_CORNER: int = 2
# The shoulder's rings between the armhole and the upper arm, each (distance
# down the arm's rest axis from the pivot, radius in sleeves or 0 for the upper
# arm's own taper there, the deltoid's share, the upper arm's share); the rest
# of a ring's weight is the torso's. Each blend spans half the arm's swing at
# most, torso to deltoid or deltoid to arm, which keeps linear blending from
# thinning the shoulder as it bends.
# The torso round each shoulder turns a little with it, as a hand-weighted rig's
# would: a torso vertex this close to the shoulder's pivot or closer takes this
# share of the deltoid, fading to none by the far reach. The armhole's edge then
# moves with the arm, and an arm swung across the chest stretches the shoulder
# rather than folding the band beside it.
const _TORSO_DELTOID_SHARE: float = 0.45
const _TORSO_DELTOID_NEAR_M: float = 0.07
const _TORSO_DELTOID_FAR_M: float = 0.22
const _SHOULDER_RINGS: Array[Vector4] = [
	Vector4(-0.035, 1.08, 0.45, 0.0),
	Vector4(0.0, 1.0, 1.0, 0.0),
	Vector4(0.035, 0.0, 0.5, 0.5),
	Vector4(0.07, 0.0, 0.0, 1.0),
]


# A sleeve bind's index in the upper skin.
static func sleeve_bind(side_i: int, part: int) -> int:
	return UPPER_SLEEVE_BIND + side_i * SLEEVE_PARTS + part


# The bone a sleeve bind names: that side's deltoid, or the bone of whichever
# arm is on that side.
static func sleeve_bone(side_i: int, part: int, top_on_right: bool) -> int:
	if part == SleevePart.DELTOID:
		return SkaterBodySkeleton.DELTOID_L_BONE if side_i == 0 \
				else SkaterBodySkeleton.DELTOID_R_BONE
	var top: bool = (side_i == 1) == top_on_right
	match part:
		SleevePart.UPPER_ARM:
			return UpperBone.TOP_UPPER_ARM if top else UpperBone.BOTTOM_UPPER_ARM
		SleevePart.ELBOW:
			return UpperBone.TOP_ELBOW if top else UpperBone.BOTTOM_ELBOW
	return UpperBone.TOP_FOREARM if top else UpperBone.BOTTOM_FOREARM


# A sleeve part's bone at rest, in the spine's frame, posed as SkaterArmRig
# poses it.
static func sleeve_rest(side_i: int, part: int) -> Transform3D:
	var cap: Basis = shoulder_cap_rest(_side_sign(side_i))
	var down: Vector3 = -cap.y
	var prism: Basis = cap * CAP_TO_PRISM
	var pivot: Vector3 = _sleeve_pivot(side_i)
	match part:
		SleevePart.DELTOID:
			return Transform3D(cap, pivot)
		SleevePart.UPPER_ARM:
			return Transform3D(prism.scaled_local(Vector3(SLEEVE_RADIUS_M, SLEEVE_RADIUS_M,
					UPPER_ARM_REST_M)), pivot + down * UPPER_ARM_REST_M * 0.5)
		SleevePart.ELBOW:
			return Transform3D(prism.scaled_local(Vector3.ONE * ELBOW_PAD_RADIUS_M),
					pivot + down * UPPER_ARM_REST_M)
	return Transform3D(prism.scaled_local(Vector3(SLEEVE_RADIUS_M, SLEEVE_RADIUS_M,
			FOREARM_REST_M)), pivot + down * (UPPER_ARM_REST_M + FOREARM_REST_M * 0.5))


# A sleeve bind's pose: from the torso's frame, where the sleeve is authored, to
# its bone's at rest.
static func sleeve_bind_pose(side_i: int, part: int) -> Transform3D:
	return sleeve_rest(side_i, part).affine_inverse() \
			* Transform3D(Basis.IDENTITY, TORSO_REST_POS)


static func _side_sign(side_i: int) -> float:
	return -1.0 if side_i == 0 else 1.0


# The shoulder pivot on a side, in the spine's frame.
static func _sleeve_pivot(side_i: int) -> Vector3:
	return Vector3(_CAP_IN_TORSO.x * _side_sign(side_i), _CAP_IN_TORSO.y, _CAP_IN_TORSO.z) \
			+ TORSO_REST_POS


# The upper arm's radius `s` down it from the shoulder.
static func _upper_arm_radius(s: float) -> float:
	return SLEEVE_RADIUS_M * (1.0 - (1.0 - _ARM_TAPER) * s / UPPER_ARM_REST_M)


# The torso corner index straight out on a side.
static func armhole_corner(side_i: int) -> int:
	return _ARMHOLE_RIGHT_CORNER + (_TORSO_SIDES / 2 if side_i == 0 else 0)


# One side's sleeve, in the spine's frame: its rings top to wrist, each
# {pts, binds, weights, s}, the ring spans of its four surfaces, the frame it
# hangs in and the wrist's centre.
static func _sleeve(side_i: int) -> Dictionary:
	var cap: Basis = shoulder_cap_rest(_side_sign(side_i))
	var prism: Basis = cap * CAP_TO_PRISM
	var down: Vector3 = -cap.y
	var pivot: Vector3 = _sleeve_pivot(side_i)
	var deltoid: int = sleeve_bind(side_i, SleevePart.DELTOID)
	var upper: int = sleeve_bind(side_i, SleevePart.UPPER_ARM)
	var forearm: int = sleeve_bind(side_i, SleevePart.FOREARM)
	var rings: Array[Dictionary] = [_armhole_ring(side_i, prism, down)]
	for spec: Vector4 in _SHOULDER_RINGS:
		var radius: float = spec.y * SLEEVE_RADIUS_M if spec.y > 0.0 \
				else _upper_arm_radius(spec.x)
		var binds := PackedInt32Array()
		var weights := PackedFloat32Array()
		for share: Vector2 in [Vector2(UpperBone.TORSO, 1.0 - spec.z - spec.w),
				Vector2(deltoid, spec.z), Vector2(upper, spec.w)]:
			if share.y > 0.0:
				binds.append(int(share.x))
				weights.append(share.y)
		var ring: Dictionary = _arm_ring(prism, pivot + down * spec.x, radius, binds, weights,
				spec.x)
		if spec.x <= 0.0:
			# At the pivot and up into the body. Tilted with the arm's hang, a ring's
			# outer side would stand over the torso's shoulder line, a tent the
			# arm's swing lifts further, so it lies level; and up the axis its inner
			# side would sit inside the chest, and the band to it fold under, so it
			# lies on the chest.
			var pts: PackedVector3Array = ring["pts"]
			var level: float = (pivot + down * spec.x).y
			for k: int in pts.size():
				pts[k] = _out_of_torso(Vector3(pts[k].x, level, pts[k].z))
			ring["pts"] = pts
		rings.append(ring)
	var shoulder_end: int = rings.size() - 1
	var elbow_at: Vector3 = pivot + down * UPPER_ARM_REST_M
	rings.append(_arm_ring(prism, elbow_at, SLEEVE_RADIUS_M * _ARM_TAPER,
			PackedInt32Array([upper]), PackedFloat32Array([1.0]), UPPER_ARM_REST_M))
	var upper_end: int = rings.size() - 1
	rings.append(_arm_ring(prism, elbow_at, ELBOW_PAD_RADIUS_M,
			PackedInt32Array([sleeve_bind(side_i, SleevePart.ELBOW)]), PackedFloat32Array([1.0]),
			UPPER_ARM_REST_M))
	for i: int in _FOREARM_PROFILE.size():
		var station: Vector2 = _FOREARM_PROFILE[i]
		var s: float = UPPER_ARM_REST_M + (0.5 - station.x) * FOREARM_REST_M
		rings.append(_arm_ring(prism, pivot + down * s, station.y * SLEEVE_RADIUS_M,
				PackedInt32Array([forearm]), PackedFloat32Array([1.0]), s))
	# The elbow's band runs from the upper arm's ring through the elbow's to the
	# forearm's top ring, the first of its profile.
	var elbow_end: int = upper_end + 2
	return {
		"rings": rings,
		"spans": [Vector2i(0, shoulder_end), Vector2i(shoulder_end, upper_end),
				Vector2i(upper_end, elbow_end), Vector2i(elbow_end, rings.size() - 1)],
		"prism": prism,
		"end": pivot + down * (UPPER_ARM_REST_M + FOREARM_REST_M),
		"down": down,
		"pivot": pivot,
	}


# A ring round the arm's rest axis at `centre`, its corner k where the arm
# prisms put theirs: sin along the frame's X, −cos along its Y.
static func _arm_ring(prism: Basis, centre: Vector3, radius: float,
		binds: PackedInt32Array, weights: PackedFloat32Array, s: float) -> Dictionary:
	var pts := PackedVector3Array()
	for k: int in _LEG_SIDES:
		var theta: float = TAU * float(k) / float(_LEG_SIDES)
		pts.append(centre + (prism.x * sin(theta) - prism.y * cos(theta)) * radius)
	return {"pts": pts, "binds": binds, "weights": weights, "s": s}


# The armhole's loop of torso corners, in the spine's frame, turned so corner k
# answers the sleeve ring's corner k. A ring round the arm faces down it and the
# armhole faces out of the torso's side, so the ring's frame is carried through
# that bend (the shortest turn from the arm's axis to the side's) before the
# corners are matched to its angles.
static func _armhole_ring(side_i: int, prism: Basis, down: Vector3) -> Dictionary:
	var corner: int = armhole_corner(side_i)
	var top: PackedVector3Array = torso_ring(ARMHOLE_TOP_STATION, GearModelRegistry.TUCK_NONE)
	var mid: PackedVector3Array = torso_ring(ARMHOLE_TOP_STATION + 1, GearModelRegistry.TUCK_NONE)
	var bottom: PackedVector3Array = torso_ring(ARMHOLE_BOTTOM_STATION,
			GearModelRegistry.TUCK_NONE)
	var loop := PackedVector3Array([top[corner - 1], top[corner], top[corner + 1],
			mid[corner + 1], bottom[corner + 1], bottom[corner], bottom[corner - 1],
			mid[corner - 1]])
	var centre := Vector3.ZERO
	for k: int in loop.size():
		loop[k] += TORSO_REST_POS
		centre += loop[k] / float(loop.size())
	var out := Vector3(_side_sign(side_i), 0.0, 0.0)
	var carry := Basis(Quaternion(down, out))
	var across: Vector3 = carry * prism.x
	var along: Vector3 = carry * prism.y
	var angles := PackedFloat32Array()
	for p: Vector3 in loop:
		var v: Vector3 = p - centre
		angles.append(atan2(v.dot(across), -v.dot(along)))
	# The ring's angles rise round it; run the loop the same way.
	var turn: float = 0.0
	for k: int in loop.size():
		turn += wrapf(angles[(k + 1) % loop.size()] - angles[k], -PI, PI)
	if turn < 0.0:
		loop.reverse()
		angles.reverse()
	var best: int = 0
	var best_cost: float = INF
	for shift: int in loop.size():
		var cost: float = 0.0
		for k: int in loop.size():
			var want: float = TAU * float(k) / float(loop.size())
			cost += absf(wrapf(angles[(k + shift) % loop.size()] - want, -PI, PI))
		if cost < best_cost:
			best_cost = cost
			best = shift
	var pts := PackedVector3Array()
	for k: int in loop.size():
		pts.append(loop[(k + best) % loop.size()])
	var shares: Array[PackedFloat32Array] = []
	for p: Vector3 in pts:
		var share: float = _torso_deltoid_share(p - TORSO_REST_POS, side_i)
		shares.append(PackedFloat32Array([1.0 - share, share]))
	return {"pts": pts,
			"binds": PackedInt32Array([UpperBone.TORSO, sleeve_bind(side_i, SleevePart.DELTOID)]),
			"weights": PackedFloat32Array([1.0, 0.0]), "pt_weights": shares, "s": -INF}


# A spine-frame point inside the torso moved straight out from its axis onto
# its section; a point outside it is left alone. Between stations the section is
# interpolated, which the lathe's flat facets only approximate.
static func _out_of_torso(p: Vector3) -> Vector3:
	var local: Vector3 = p - TORSO_REST_POS
	var section: Vector3 = _torso_section_at(local.y)
	var across: float = pow(pow(absf(local.x) / section.x, section.z)
			+ pow(absf(local.z) / section.y, section.z), 1.0 / section.z)
	if across >= 1.0 or across < 1e-4:
		return p
	return Vector3(local.x / across, local.y, local.z / across) + TORSO_REST_POS


# The torso's (half width, half depth, squareness) at torso-local height `y`,
# clamped to its ends. The front panel's drop is not in it: the sleeve, its one
# reader, meets the torso at the sides.
static func _torso_section_at(y: float) -> Vector3:
	var i: int = 0
	var t: float = 0.0
	if y < _TORSO_PROFILE[-1].x:
		i = _TORSO_PROFILE.size() - 2
		t = 1.0
	elif y < _TORSO_PROFILE[0].x:
		while y < _TORSO_PROFILE[i + 1].x:
			i += 1
		t = (_TORSO_PROFILE[i].x - y) / (_TORSO_PROFILE[i].x - _TORSO_PROFILE[i + 1].x)
	var hi := Vector3(_TORSO_SECTION[i].x * _TORSO_PROFILE[i].y * _TORSO_X_SCALE,
			_TORSO_SECTION[i].y * _TORSO_PROFILE[i].y * _TORSO_Z_SCALE, _TORSO_SECTION[i].z)
	var lo := Vector3(_TORSO_SECTION[i + 1].x * _TORSO_PROFILE[i + 1].y * _TORSO_X_SCALE,
			_TORSO_SECTION[i + 1].y * _TORSO_PROFILE[i + 1].y * _TORSO_Z_SCALE,
			_TORSO_SECTION[i + 1].z)
	return hi.lerp(lo, t)


# The deltoid's share of a torso vertex on a side, at torso-local `p`.
static func _torso_deltoid_share(p: Vector3, side_i: int) -> float:
	var pivot := Vector3(_CAP_IN_TORSO.x * _side_sign(side_i), _CAP_IN_TORSO.y, _CAP_IN_TORSO.z)
	var reach: float = (_TORSO_DELTOID_FAR_M - p.distance_to(pivot)) \
			/ (_TORSO_DELTOID_FAR_M - _TORSO_DELTOID_NEAR_M)
	return _TORSO_DELTOID_SHARE * clampf(reach, 0.0, 1.0)


# One of a sleeve's four surfaces into `target`, in the torso's frame. A facet
# takes its own flat normal at rest, except the elbow's: its three rings all sit
# on the elbow at rest, so its facets take the arm's radial normal at their
# middle angle, which is what they show once it bends.
static func _add_sleeve_surface(target: ArrayMesh, sleeve: Dictionary, surface: int) -> void:
	var rings: Array[Dictionary] = []
	rings.assign(sleeve["rings"])
	var span: Vector2i = sleeve["spans"][surface]
	var prism: Basis = sleeve["prism"]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i: int in range(span.x, span.y):
		for k: int in _LEG_SIDES:
			var k1: int = (k + 1) % _LEG_SIDES
			var mid: float = TAU * (float(k) + 0.5) / float(_LEG_SIDES)
			var radial: Vector3 = prism.x * sin(mid) - prism.y * cos(mid)
			var a: Vector3 = rings[i]["pts"][k]
			var b: Vector3 = rings[i]["pts"][k1]
			var c: Vector3 = rings[i + 1]["pts"][k1]
			var d: Vector3 = rings[i + 1]["pts"][k]
			var n: Vector3 = radial
			var order: Array[int] = [0, 1, 2, 0, 2, 3]
			if surface != SleeveSurface.ELBOW:
				n = _sleeve_facet_normal(a, b, c, d, radial, sleeve)
				order = _sleeve_facet_order([a, b, c, d], n)
			var u0: float = float(k) / float(_LEG_SIDES)
			var u1: float = float(k + 1) / float(_LEG_SIDES)
			var corners: Array = [[a, i, u0, k], [b, i, u1, k1], [c, i + 1, u1, k1],
					[d, i + 1, u0, k]]
			for t: int in order:
				var corner: Array = corners[t]
				var ring: Dictionary = rings[corner[1]]
				verts.append(corner[0] - TORSO_REST_POS)
				normals.append(n)
				uvs.append(Vector2(corner[2], _sleeve_v(surface, span, corner[1], ring)))
				_append_influences(bones, weights, ring, corner[3])
	if surface == SleeveSurface.FOREARM:
		var last: Dictionary = rings[span.y]
		var end: Vector3 = sleeve["end"]
		for k: int in _LEG_SIDES:
			for p: Vector3 in [end, last["pts"][k], last["pts"][(k + 1) % _LEG_SIDES]]:
				verts.append(p - TORSO_REST_POS)
				normals.append(sleeve["down"])
				uvs.append(Vector2(0.75, 0.75))
				_append_influences(bones, weights, last, -1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# A ring vertex's influences: the ring's, or corner k's own where the ring
# carries them per corner (the armhole's, which match the torso's there).
# A sleeve facet's flat normal at rest, turned away from the inside of the arm:
# the nearest point of the arm's axis, which above the shoulder's pivot is the
# pivot itself, so the armhole's top faces up rather than round the arm.
static func _sleeve_facet_normal(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		radial: Vector3, sleeve: Dictionary) -> Vector3:
	var n: Vector3 = (c - a).cross(b - d)
	if n.length_squared() < 1e-10:
		return radial
	var pivot: Vector3 = sleeve["pivot"]
	var down: Vector3 = sleeve["down"]
	var centre: Vector3 = (a + b + c + d) * 0.25
	var away: Vector3 = centre - (pivot + down * maxf((centre - pivot).dot(down), 0.0))
	n = n.normalized()
	return -n if n.dot(away) < 0.0 else n


# A facet's two triangles wound to face `n`: Godot's front faces are clockwise
# seen from the side they face.
static func _sleeve_facet_order(quad: Array, n: Vector3) -> Array[int]:
	var order: Array[int] = []
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var p0: Vector3 = quad[tri[0]]
		var p1: Vector3 = quad[tri[1]]
		var p2: Vector3 = quad[tri[2]]
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
			order.append_array([tri[0], tri[2], tri[1]])
		else:
			order.append_array(tri)
	return order


static func _append_influences(bones: PackedInt32Array, weights: PackedFloat32Array,
		ring: Dictionary, k: int) -> void:
	var ring_binds: PackedInt32Array = ring["binds"]
	var ring_weights: PackedFloat32Array = ring["weights"]
	if k >= 0 and ring.has("pt_weights"):
		ring_weights = ring["pt_weights"][k]
	for j: int in 4:
		bones.append(ring_binds[j] if j < ring_binds.size() else 0)
		weights.append(ring_weights[j] if j < ring_weights.size() else 0.0)


# A sleeve ring's V on `surface`: the arm surfaces keep the plain prisms' (V
# runs 0 to 0.5 down each, so a sleeve's stripes land where they did), the
# shoulder spreads the shoulder decal's band over its rings and the elbow is
# painted solid.
static func _sleeve_v(surface: int, span: Vector2i, ring_i: int, ring: Dictionary) -> float:
	match surface:
		SleeveSurface.UPPER_ARM:
			return clampf(0.5 * float(ring["s"]) / UPPER_ARM_REST_M, 0.0, 0.5)
		SleeveSurface.FOREARM:
			return clampf(0.5 * (float(ring["s"]) - UPPER_ARM_REST_M) / FOREARM_REST_M, 0.0, 0.5)
		SleeveSurface.ELBOW:
			return 0.25 + 0.125 * float(ring_i - span.x)
	return lerpf(0.3, 0.9, float(ring_i - span.x) / float(maxi(span.y - span.x, 1)))


# The skinned torso with an armhole each side: the four quads round each side's
# outermost corner between ARMHOLE_TOP_STATION and ARMHOLE_BOTTOM_STATION are
# collapsed onto a point, so the torso keeps its vertex count and order (the
# jersey's tail indexes it vertex for vertex) and shows nothing there; the
# sleeve's armhole ring is the loop of corners round them. Its vertices near a
# shoulder take their share of that side's deltoid (_torso_deltoid_share).
static func _cut_armholes(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var y_top: float = _TORSO_PROFILE[ARMHOLE_TOP_STATION].x + 1e-4
	var y_bottom: float = _TORSO_PROFILE[ARMHOLE_BOTTOM_STATION].x - 1e-4
	# Round the torso by u, which counts its corners whatever its section.
	var half_span: float = 1.0 / float(_TORSO_SIDES) + 1e-3
	for t: int in range(0, verts.size(), 3):
		for side_i: int in 2:
			var corner_u: float = float(armhole_corner(side_i)) / float(_TORSO_SIDES)
			var inside: bool = true
			for j: int in 3:
				var p: Vector3 = verts[t + j]
				if p.y > y_top or p.y < y_bottom \
						or absf(wrapf(uvs[t + j].x - corner_u, -0.5, 0.5)) > half_span:
					inside = false
					break
			if inside:
				verts[t + 1] = verts[t]
				verts[t + 2] = verts[t]
				break
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for v: int in verts.size():
		if bones[v * 4] != UpperBone.TORSO or weights[v * 4 + 1] > 0.0:
			continue  # the tail's, which hangs from the hips
		for side_i: int in 2:
			var share: float = _torso_deltoid_share(verts[v], side_i)
			if share > 0.0:
				bones[v * 4 + 1] = sleeve_bind(side_i, SleevePart.DELTOID)
				weights[v * 4] = 1.0 - share
				weights[v * 4 + 1] = share
				break
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	return arrays


# ── The jersey tail's sim seams ──────────────────────────────────────────────
# Stations of _TORSO_PROFILE the flaps hang the tail by: the belt it hangs
# from, the bend between its two segments, and the hem.
const TORSO_BELT_STATION: int = 7
const TORSO_BEND_STATION: int = 9
const TORSO_HEM_STATION: int = 10


# One torso ring as the lathe builds it (sides + 1 points, the last repeating
# the first), torso-local, draped as `tuck` drapes it.
static func torso_ring(station: int, tuck: int) -> PackedVector3Array:
	var s: Vector2 = _TORSO_PROFILE[station]
	var phase: float = TAU * TORSO_U_PHASE
	var z_off: float = _TORSO_REAR_SWAY[station]
	var ring: PackedVector3Array = _ring(s.x, s.y, _TORSO_X_SCALE, _TORSO_Z_SCALE,
			_TORSO_SIDES, phase)
	for k: int in ring.size():
		ring[k].z += z_off
	return SkaterJerseyHem.tuck_ring(_torso_section(ring, station, z_off), s.x, s.y, z_off,
			tuck, phase, _TORSO_X_SCALE, _TORSO_Z_SCALE)


# The pants at waist-space height `y`: (radius, rear sway), radius < 0 outside
# their span. Their lathe is wider than deep by PELVIS_XZ_SCALE.
static func pelvis_ring(y: float) -> Vector2:
	for i: int in _PELVIS_PROFILE.size() - 1:
		var hi: Vector2 = _PELVIS_PROFILE[i]
		var lo: Vector2 = _PELVIS_PROFILE[i + 1]
		if y <= hi.x and y >= lo.x:
			var t: float = (hi.x - y) / maxf(hi.x - lo.x, 1e-6)
			return Vector2(lerpf(hi.y, lo.y, t),
					lerpf(_PELVIS_REAR_SWAY[i], _PELVIS_REAR_SWAY[i + 1], t))
	return Vector2(-1.0, 0.0)


const PELVIS_XZ_SCALE := Vector2(_TORSO_X_SCALE, _TORSO_Z_SCALE)


# The pants' lathe as (y, radius, rear sway) per station, top down, waist-space.
static func pelvis_stations() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i: int in _PELVIS_PROFILE.size():
		out.append_array([_PELVIS_PROFILE[i].x, _PELVIS_PROFILE[i].y, _PELVIS_REAR_SWAY[i]])
	return out
# The thigh as a capsule in its LEG bone's frame: from the hip pivot, whose dome
# is the capsule's top, down to where the breezers turn in at the leg hem.
const THIGH_CAPSULE_LENGTH_M: float = 0.26
const THIGH_CAPSULE_RADIUS_M: float = 0.152


# Copies a single-surface mesh into `target` verbatim, adding the bone/weight
# attributes that make every one of its vertices rigid to `bone`.
#
# Goes through surface_get_arrays rather than SurfaceTool: SurfaceTool
# re-processes what it is handed (re-indexing, possibly re-deriving normals),
# and this mesh must stay vertex-for-vertex identical to the unskinned source.
static func _append_skinned_surface(target: ArrayMesh, src: ArrayMesh, bone: int,
		src_surface: int = 0) -> void:
	var arrays: Array = src.surface_get_arrays(src_surface)
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var bones := PackedInt32Array()
	bones.resize(vertex_count * 4)
	var weights := PackedFloat32Array()
	weights.resize(vertex_count * 4)
	# resize() zero-fills, so influences 1-3 are already bone 0 at weight 0.
	for i: int in vertex_count:
		bones[i * 4] = bone
		weights[i * 4] = 1.0
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Carry the source surface's shared default across, so surface_override()
	# still has something to duplicate for parts that ship with one (the boot's
	# steel and laces).
	var shared: Material = src.surface_get_material(src_surface)
	if shared != null:
		target.surface_set_material(target.get_surface_count() - 1, shared)


# Elbow ball, unit radius.
static func shared_joint_ball() -> ArrayMesh:
	return _shared("joint_ball", func() -> ArrayMesh:
		return _build_ball(1.0, 8, 4, 1.0))


# Elbow pad, unit radius: a ball drawn out to a soft point at +Y, which a placed
# figure points out of the bend (LockerMannequin) — the pad's shape just showing
# through a thick sleeve. The skinned arm's elbow is its sleeve's (_sleeve).
const _ELBOW_PAD_PROFILE: Array[Vector2] = [
	Vector2(1.08, 0.30), Vector2(0.92, 0.74), Vector2(0.56, 0.98), Vector2(0.1, 1.02),
	Vector2(-0.45, 0.9), Vector2(-0.82, 0.55), Vector2(-0.98, 0.18),
]
static func shared_elbow_pad() -> ArrayMesh:
	return _shared("elbow_pad", func() -> ArrayMesh:
		return _build_lathe(_ELBOW_PAD_PROFILE, _LEG_SIDES, 1.0, 1.0))


# Gloved fist (see _GLOVE_FIST_STATIONS): the BACK of the hand on surface 0
# and the FINGERS on surface 1, each closed at the knuckle ring they share.
static func shared_glove_fist() -> ArrayMesh:
	return _shared("glove_fist", func() -> ArrayMesh:
		var loops: Array[PackedVector3Array] = []
		for s: Vector3 in _GLOVE_FIST_STATIONS:
			loops.append(_octagon_loop(s.x, s.y, s.z, _GLOVE_FACE_FRAC, _GLOVE_SIDE_FRAC))
		var m := ArrayMesh.new()
		_commit_sweep_segment(m, loops, 0, _GLOVE_FINGER_STATION, _fist_loop_center)
		_commit_sweep_segment(m, loops, _GLOVE_FINGER_STATION, loops.size() - 1,
				_fist_loop_center)
		return m)


# A fist loop's axis point — the sweep runs along local Y, so the caps fan to
# the loop's own height on that axis.
static func _fist_loop_center(loop: PackedVector3Array) -> Vector3:
	return Vector3(0.0, loop[0].y, 0.0)


# Glove cuff: the fist's chamfered box section, posed in the fist's frame. x/z
# are multiples of the cuff radius; its height is real (CUFF_HEIGHT_M), since the
# along-bone placement offsets by it. Tapered: the open end clears the sleeve
# going into it, the wrist end closes onto the back of the fist with a lip.
# Its pose scale is (radius, 1, radius), ~10:1, so its sides need the arm
# bone's radial normals (_radial_side_normals) or the taper shades them black.
const _CUFF_STATIONS: Array[Vector3] = [
	Vector3(0.5, 0.94, 0.875),   # open end, toward the elbow
	Vector3(-0.5, 0.75, 0.69),   # wrist end, around the back of the fist
]
static func shared_cuff() -> ArrayMesh:
	return _shared("cuff", func() -> ArrayMesh:
		var loops: Array[PackedVector3Array] = []
		for c: Vector3 in _CUFF_STATIONS:
			loops.append(_octagon_loop(c.x * CUFF_HEIGHT_M, c.y, c.z,
					_GLOVE_FACE_FRAC, _GLOVE_SIDE_FRAC))
		var m := ArrayMesh.new()
		_commit_sweep_segment(m, loops, 0, loops.size() - 1, _fist_loop_center)
		return _radial_side_normals(m))


# Butt-end knob at its real dimensions (never rescaled).
static func shared_knob() -> ArrayMesh:
	return _shared("knob", func() -> ArrayMesh:
		var h: float = KNOB_HEIGHT_M * 0.5
		var profile: Array[Vector2] = [
			Vector2(h, _KNOB_TOP_RADIUS), Vector2(-h, _KNOB_BOTTOM_RADIUS)]
		return _build_lathe(profile, _LEG_SIDES, 1.0, 1.0))


# ── Part builders ─────────────────────────────────────────────────────────────


# Torso scales and facet count, so the seat continues the same silhouette it
# emerges from rather than reading as a separate object under the jersey.
static func _build_pelvis(tuck: int = GearModelRegistry.TUCK_NONE) -> ArrayMesh:
	var deform := Callable()
	if tuck != GearModelRegistry.TUCK_NONE:
		var lip: float = _PELVIS_PROFILE[0].x
		var waistband: float = _PELVIS_PROFILE[1].x
		deform = func(ring: PackedVector3Array, y: float, radius: float,
				z_off: float) -> PackedVector3Array:
			if y < waistband - 1e-5:
				return ring
			var is_lip: bool = y > lip - 1e-5
			return SkaterJerseyHem.pad_ring(ring, y, radius, z_off, tuck,
					_TORSO_X_SCALE, _TORSO_Z_SCALE,
					SkaterJerseyHem.PAD_RISE_M * (1.0 if is_lip else SkaterJerseyHem.PAD_BULGE_SHARE),
					0.0 if is_lip else SkaterJerseyHem.PAD_FLARE_M)
	return _build_lathe(_PELVIS_PROFILE, _TORSO_SIDES, _TORSO_X_SCALE, _TORSO_Z_SCALE,
			_PELVIS_REAR_SWAY, 0.0, deform)


static func _build_torso(tuck: int = GearModelRegistry.TUCK_NONE) -> ArrayMesh:
	var phase: float = TAU * TORSO_U_PHASE
	var deform := func(ring: PackedVector3Array, y: float, radius: float,
			z_off: float) -> PackedVector3Array:
		var shaped: PackedVector3Array = _torso_section(ring, _torso_station(y), z_off)
		return SkaterJerseyHem.tuck_ring(shaped, y, radius, z_off, tuck, phase,
				_TORSO_X_SCALE, _TORSO_Z_SCALE)
	return _build_lathe(_TORSO_PROFILE, _TORSO_SIDES, _TORSO_X_SCALE, _TORSO_Z_SCALE,
			_TORSO_REAR_SWAY, phase, deform)


# The _TORSO_PROFILE station at torso-local height `y`, which is one of theirs.
static func _torso_station(y: float) -> int:
	for i: int in _TORSO_PROFILE.size():
		if absf(_TORSO_PROFILE[i].x - y) < 1e-5:
			return i
	return -1


# An elliptical lathe ring (z shifted by `z_off`) given `station`'s
# _TORSO_SECTION: each corner is pushed straight out onto the section's
# superellipse. Along its own ray, so the corners either side of the chest and
# the back stay about as far apart as on the ellipse and the decals painted
# between them keep their width; the corners at the diagonals go out the most.
static func _torso_section(ring: PackedVector3Array, station: int,
		z_off: float) -> PackedVector3Array:
	var section: Vector4 = _TORSO_SECTION[station]
	var half_width: float = _TORSO_PROFILE[station].y * _TORSO_X_SCALE
	var half_depth: float = _TORSO_PROFILE[station].y * _TORSO_Z_SCALE
	var out := PackedVector3Array(ring)
	for k: int in out.size():
		var across: float = out[k].x / half_width
		var along: float = (out[k].z - z_off) / half_depth
		var push: float = pow(pow(absf(across), section.z) + pow(absf(along), section.z),
				-1.0 / section.z)
		out[k].x = half_width * section.x * across * push
		out[k].z = half_depth * section.y * along * push + z_off
		if -along > _TORSO_FRONT_PANEL:
			out[k].y -= section.w
	return out


# Head ball at HEAD_RADIUS, sitting HEAD_FORWARD_M ahead of the helmet center,
# with its face (SkaterFaceMesh) — every vertex carries the tint the skin
# material multiplies, white but for the face's darker features.
static func _build_head() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.append_from(SkaterFaceMesh.untinted(_build_ball(HEAD_RADIUS, HEAD_LON, HEAD_LAT, 1.0)),
			0, Transform3D.IDENTITY)
	st.append_from(SkaterFaceMesh.build(HEAD_RADIUS, HEAD_LON, HEAD_LAT), 0, Transform3D.IDENTITY)
	return st.commit()



# Shared part accessors for out-of-game figures (the lobby's bench dummies, the
# locker mannequin) so every rendered player body — live or furniture — wears
# the same faceted set from the same cache.
# The torso as a GearModelRegistry TUCK_* option drapes it, vertex for vertex
# the loose one with its tail moved.
static func shared_torso(tuck: int = GearModelRegistry.TUCK_NONE) -> ArrayMesh:
	if tuck == GearModelRegistry.TUCK_NONE or not GearModelRegistry.is_valid_tuck(tuck):
		return _shared("torso", _build_torso)
	return _shared("torso_tuck_%d" % tuck, _build_torso.bind(tuck))


# The pants as a GearModelRegistry TUCK_* option stands their pad up.
static func shared_pelvis(tuck: int = GearModelRegistry.TUCK_NONE) -> ArrayMesh:
	if tuck == GearModelRegistry.TUCK_NONE or not GearModelRegistry.is_valid_tuck(tuck):
		return _shared("pelvis", _build_pelvis)
	return _shared("pelvis_tuck_%d" % tuck, _build_pelvis.bind(tuck))


static func shared_head_ball() -> ArrayMesh:
	return _shared("head", _build_head)


static func shared_shoulder_cap() -> ArrayMesh:
	return _shared("shoulder", _build_shoulder)


static func shared_thigh() -> ArrayMesh:
	return _shared("thigh", _build_thigh)


# The knee as a straight leg wears it, rigid in the KNEE frame (origin on the
# knee pivot), for a figure that places parts rather than skinning them. Built
# at its real size, so a placer scales it only by the build's dials.
static func shared_knee() -> ArrayMesh:
	return _shared("knee", _build_knee)


static func shared_sock() -> ArrayMesh:
	return _shared("sock", _build_sock)


static func shared_boot() -> ArrayMesh:
	return _shared("boot", _build_boot)


static func shared_skate_collar() -> ArrayMesh:
	return _shared("skate", _build_skate)


# Skate accent stripe: a thin unit-radius band that rings the collar proud of
# its sidewall — the one piece the skate-color cosmetic paints (the boot and
# collar themselves stay dark). Unit radius like the glove cuff; the creation
# site scales it to sit just off the collar.
static func shared_skate_stripe() -> ArrayMesh:
	return _shared("skate_stripe", func() -> ArrayMesh:
		var h: float = SKATE_STRIPE_HEIGHT_M * 0.5
		var profile: Array[Vector2] = [Vector2(h, 1.0), Vector2(-h, 1.0)]
		return _build_lathe(profile, _LEG_SIDES, 1.0, 1.0))


# Drawn-on skate laces (see _LACE_RUNGS): one mesh of instep rungs in the
# boot's rotated frame, shared like every other part.
static func shared_laces() -> ArrayMesh:
	return _shared("laces", func() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)  # flat shading — see class doc block
		for rung: Vector2 in _LACE_RUNGS:
			_box(st,
					Vector3(-_LACE_HALF_W, rung.x - _LACE_HALF_T, rung.y - _LACE_PROUD),
					Vector3(_LACE_HALF_W, rung.x + _LACE_HALF_T, rung.y + _LACE_SINK))
		st.generate_normals()
		return st.commit())


static func shared_skate_blade() -> ArrayMesh:
	return _shared("skate_blade", _build_skate_blade)


# Helmet shell: lat/long bands whose bottom latitude follows the per-azimuth cut
# (see the _HELMET_* constants), closed by a fan from the rim to an interior
# center — those closure faces hide inside the head ball, and closing keeps the
# solid's winding testable. Same ring orientation as _build_ball, so the shared
# quad ordering stays outward.
static func _build_helmet() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	var lon: int = _HELMET_LON
	var lat: int = 4
	var rings: Array[PackedVector3Array] = []
	for j in lat + 1:
		var ring := PackedVector3Array()
		ring.resize(lon + 1)
		for k in lon + 1:
			var theta: float = TAU * float(k) / float(lon)
			var v: float = _helmet_cut_v(theta) * float(j) / float(lat)
			var y: float = _HELMET_RADIUS * cos(PI * v)
			var ring_r: float = _HELMET_RADIUS * sin(PI * v)
			ring[k] = Vector3(sin(theta) * ring_r, y, cos(theta) * ring_r)
		rings.append(ring)
	for j in lat:
		for k in lon:
			_uv_quad(st,
					rings[j][k], Vector2.ZERO,
					rings[j][k + 1], Vector2(0.1, 0.0),
					rings[j + 1][k + 1], Vector2(0.1, 0.1),
					rings[j + 1][k], Vector2(0.0, 0.1))
	var apex := Vector3(0.0, _HELMET_RADIUS * _HELMET_LINER_APEX_FRAC, 0.0)
	_cap(st, rings[lat], apex, Vector2(0.5, 0.9), false, 0.05)
	st.generate_normals()
	return st.commit()


# The rim's latitude fraction at azimuth θ (helmet-local, θ = 0 the back).
static func _helmet_cut_v(theta: float) -> float:
	var t: float = clampf((cos(theta) - _HELMET_DROP_START_C)
			/ (1.0 - _HELMET_DROP_START_C), 0.0, 1.0)
	return lerpf(_HELMET_FRONT_CUT, _HELMET_BACK_CUT, t * t * (3.0 - 2.0 * t)) \
			+ _HELMET_EAR_DIP * pow(absf(sin(theta)), _HELMET_EAR_DIP_POWER)


# Helmet-local height of the shell's lower edge at azimuth θ, as built: the rim
# is a chord between the sampled azimuths, so its height between two samples is
# their lerp, not the profile's.
static func helmet_rim_y(theta: float) -> float:
	var step: float = TAU / float(_HELMET_LON)
	var f: float = fposmod(theta, TAU) / step
	var k: float = floorf(f)
	return lerpf(_HELMET_RADIUS * cos(PI * _helmet_cut_v(k * step)),
			_HELMET_RADIUS * cos(PI * _helmet_cut_v((k + 1.0) * step)), f - k)


# ── Helmet face gear ─────────────────────────────────────────────────────────
# Visor / cage / fishbowl, in the helmet's own frame (face toward −Z, matching
# the head's forward offset) so the piece can ride the HELMET bone. All three
# are sections of a sphere just proud of the shell, sampled with the helmet's
# latitude convention: the shields are one solid patch each, the cage is the
# same patch emitted as thin strips (its bars). Looks (color/alpha/roughness)
# live in GearModelRegistry.FACE_*; the meshes carry no default material —
# SkaterUniformCoordinator.make_face_gear_material is the one paint source.

const _FACE_SHIELD_RADIUS: float = 0.158  # proud of the 0.155 shell
# Visor: brow to just under the eye line (the equator). Ends short of the ear
# loops (rim dips at ±90° from the face) so it reads as clipped to the rim.
const _VISOR_V0: float = 0.41   # tucked under the brow rim (front cut 0.40)
const _VISOR_V1: float = 0.55
const _VISOR_HALF_ARC: float = 1.25   # rad each side of dead front
# Fishbowl: the same shield carried down past the chin (the head ball's south
# pole region — v 0.78 is jaw depth on the shield's slightly larger radius).
const _FISHBOWL_V1: float = 0.78
const _FISHBOWL_HALF_ARC: float = 1.35
# Cage: a bar lattice over the fishbowl's opening. Bar half-width is metres of
# arc, converted per-axis to parameter half-widths where the bars are emitted.
const _CAGE_RADIUS: float = 0.157
const _CAGE_BAR_HALF_M: float = 0.003
const _CAGE_V0: float = 0.42
const _CAGE_V1: float = 0.72
const _CAGE_HALF_ARC: float = 1.15
const _CAGE_H_BAR_COUNT: int = 4
const _CAGE_V_BAR_OFFSETS: Array[float] = [-0.84, -0.42, 0.0, 0.42, 0.84]


# The face piece's fixed look — the one gear piece whose colors never resolve
# against the kit (a visor is smoked polycarbonate and a cage bare steel
# whoever wears them), so the material lives here with the geometry instead of
# on the uniform coordinator, and the locker mannequin and the capture tool
# dress their previews from the same factory. The shields carry their
# transparency in the registry alpha; the cage is an open lattice of one-sided
# strips, so it renders two-sided instead.
static func make_face_gear_material(option: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GearModelRegistry.face_color(option)
	mat.roughness = GearModelRegistry.face_roughness(option)
	if mat.albedo_color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if option == GearModelRegistry.FACE_CAGE:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# The face piece for one GearModelRegistry FACE_* option — null for bare (and
# for a forged index, matching the registry's clamp).
static func shared_face_gear(option: int) -> ArrayMesh:
	match option:
		GearModelRegistry.FACE_VISOR:
			return _shared("face_visor", _build_visor)
		GearModelRegistry.FACE_CAGE:
			return _shared("face_cage", _build_cage)
		GearModelRegistry.FACE_FISHBOWL:
			return _shared("face_fishbowl", _build_fishbowl)
		_:
			return null


static func _build_visor() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	_sphere_patch(st, _FACE_SHIELD_RADIUS, _VISOR_V0, _VISOR_V1,
			PI - _VISOR_HALF_ARC, PI + _VISOR_HALF_ARC, 2, 8)
	st.generate_normals()
	return st.commit()


static func _build_fishbowl() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	_sphere_patch(st, _FACE_SHIELD_RADIUS, _VISOR_V0, _FISHBOWL_V1,
			PI - _FISHBOWL_HALF_ARC, PI + _FISHBOWL_HALF_ARC, 3, 10)
	st.generate_normals()
	return st.commit()


static func _build_cage() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	# Latitude half-width of a horizontal bar: metres over the pole-to-pole arc.
	var dv: float = _CAGE_BAR_HALF_M / (PI * _CAGE_RADIUS)
	for i: int in _CAGE_H_BAR_COUNT:
		var v: float = lerpf(_CAGE_V0 + dv, _CAGE_V1 - dv,
				float(i) / float(_CAGE_H_BAR_COUNT - 1))
		_sphere_patch(st, _CAGE_RADIUS, v - dv, v + dv,
				PI - _CAGE_HALF_ARC, PI + _CAGE_HALF_ARC, 1, 8)
	# Azimuth half-width of a vertical bar: metres over the ring radius at the
	# lattice's mid-latitude. Constant per bar, so bars taper slightly toward
	# the brow where rings shrink — as welded cage wire does.
	var dth: float = _CAGE_BAR_HALF_M \
			/ (_CAGE_RADIUS * sin(PI * (_CAGE_V0 + _CAGE_V1) * 0.5))
	for off: float in _CAGE_V_BAR_OFFSETS:
		_sphere_patch(st, _CAGE_RADIUS, _CAGE_V0, _CAGE_V1,
				PI + off - dth, PI + off + dth, 4, 1)
	# The frame's sides, closing the outline the top and bottom bars run along.
	for side: float in [-1.0, 1.0]:
		var edge: float = PI + side * (_CAGE_HALF_ARC - dth)
		_sphere_patch(st, _CAGE_RADIUS, _CAGE_V0, _CAGE_V1, edge - dth, edge + dth, 4, 1)
	st.generate_normals()
	return st.commit()


# One rectangular patch of a sphere between two (latitude, azimuth) corners,
# sampled on a v_steps × th_steps quad grid. Conventions match _build_helmet:
# θ = 0 is +Z (the back) advancing toward +X, v is the latitude fraction, and
# the quad winding faces outward. UVs are nominal — every face piece is
# solid-painted. Open sheet, not a solid: the shields are millimetre glazing
# and the bars are wire, so a closed back would double the triangles to say
# nothing (their materials go two-sided or transparent instead).
static func _sphere_patch(st: SurfaceTool, radius: float, v0: float, v1: float,
		th0: float, th1: float, v_steps: int, th_steps: int) -> void:
	for j in v_steps:
		var va: float = lerpf(v0, v1, float(j) / float(v_steps))
		var vb: float = lerpf(v0, v1, float(j + 1) / float(v_steps))
		for k in th_steps:
			var ta: float = lerpf(th0, th1, float(k) / float(th_steps))
			var tb: float = lerpf(th0, th1, float(k + 1) / float(th_steps))
			_uv_quad(st,
					_sphere_point(radius, va, ta), Vector2.ZERO,
					_sphere_point(radius, va, tb), Vector2(0.1, 0.0),
					_sphere_point(radius, vb, tb), Vector2(0.1, 0.1),
					_sphere_point(radius, vb, ta), Vector2(0.0, 0.1))


static func _sphere_point(radius: float, v: float, theta: float) -> Vector3:
	var ring_r: float = radius * sin(PI * v)
	return Vector3(sin(theta) * ring_r, radius * cos(PI * v), cos(theta) * ring_r)


static func _build_neck() -> ArrayMesh:
	return _build_lathe(NECK_PROFILE, 8, 1.0, 1.0)


# Default-tone skin material — Skater.set_skin_tone repaints the albedo to
# the player's identity pick at spawn (and live from the edit-player popup).
static func _make_skin_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SkinToneRegistry.color_for(SkinToneRegistry.DEFAULT_INDEX)
	mat.roughness = 0.85
	mat.vertex_color_use_as_albedo = true   # the face's features
	BodyRim.apply(mat)
	return mat


static func _build_shoulder() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	var lon: int = _CAP_LON
	var n: int = _SHOULDER_PROFILE.size()
	var rings: Array[PackedVector3Array] = []
	for s: Vector3 in _SHOULDER_PROFILE:
		rings.append(_ring(s.x, s.y, 1.0, 1.0, lon))
	for i in n - 1:
		for k in lon:
			var u0: float = float(k) / float(lon)
			var u1: float = float(k + 1) / float(lon)
			_uv_quad(st,
					rings[i][k], Vector2(u0, _SHOULDER_PROFILE[i].z),
					rings[i][k + 1], Vector2(u1, _SHOULDER_PROFILE[i].z),
					rings[i + 1][k + 1], Vector2(u1, _SHOULDER_PROFILE[i + 1].z),
					rings[i + 1][k], Vector2(u0, _SHOULDER_PROFILE[i + 1].z))
	# Caps sample the decal's pole regions (plain shoulder color).
	_cap(st, rings[0], Vector3(0.0, _SHOULDER_PROFILE[0].x, 0.0),
			Vector2(0.5, 0.06), true, 0.05)
	_cap(st, rings[n - 1], Vector3(0.0, _SHOULDER_PROFILE[n - 1].x, 0.0),
			Vector2(0.5, 0.97), false, 0.02)
	st.generate_normals()
	return st.commit()


static func _build_knee() -> ArrayMesh:
	var profile: Array[Vector2] = []
	for s: Vector3 in _KNEE_PROFILE:
		profile.append(Vector2(s.x, s.y))
	return _build_lathe(profile, _LEG_SIDES, 1.0, 1.0, [], 0.0, _kneecap)


# Pushes a knee ring's front (−Z) out by its station's kneecap, fading to
# nothing at the sides.
static func _kneecap(ring: PackedVector3Array, y: float, radius: float,
		_z_off: float) -> PackedVector3Array:
	var proud: float = 0.0
	for s: Vector3 in _KNEE_PROFILE:
		if is_equal_approx(s.x, y):
			proud = s.z
	for k: int in ring.size():
		var front: float = maxf(-ring[k].z / radius, 0.0)
		var grow: float = 1.0 + proud / radius * front * front
		ring[k].x *= grow
		ring[k].z *= grow
	return ring


# The knee into `target` as the leg skin wears it: rings below the stitch move
# to the sock's frame and ride `sock_bone`, the rest ride `knee_bone`.
static func _append_knee_surface(target: ArrayMesh, src: ArrayMesh, knee_bone: int,
		sock_bone: int) -> void:
	var arrays: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	bones.resize(verts.size() * 4)
	var weights := PackedFloat32Array()
	weights.resize(verts.size() * 4)
	for i: int in verts.size():
		weights[i * 4] = 1.0
		if verts[i].y < _KNEE_STITCH_Y:
			bones[i * 4] = sock_bone
			verts[i].y += _KNEE_ABOVE_SOCK
		else:
			bones[i * 4] = knee_bone
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _build_thigh() -> ArrayMesh:
	return _build_lathe(_THIGH_PROFILE, _LEG_SIDES, 1.02, 0.96)


static func _build_sock() -> ArrayMesh:
	return _build_lathe(_SOCK_PROFILE, _LEG_SIDES, 1.0, 1.0)


static func _build_skate() -> ArrayMesh:
	return _build_lathe(_SKATE_PROFILE, _LEG_SIDES, 1.0, 1.0)


# ── Lathe (cylinder-convention) parts ─────────────────────────────────────────


# Faceted solid of revolution over (y, radius) stations, with the cylinder UV
# convention from the class doc block. Both end caps are emitted — the torso's
# top cap is where the jersey yoke paints.
# `ring_deform`, when given, takes each ring as built (with its rest height,
# profile radius and rear shift) and returns where its points go instead; the
# UVs stay the rest ring's.
static func _build_lathe(profile: Array[Vector2], sides: int,
		x_scale: float, z_scale: float,
		z_offsets: Array[float] = [], phase: float = 0.0,
		ring_deform: Callable = Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	var y_top: float = profile[0].x
	var y_bot: float = profile[profile.size() - 1].x
	var span: float = maxf(y_top - y_bot, 0.001)
	var rings: Array[PackedVector3Array] = []
	var vs := PackedFloat32Array()
	for i in profile.size():
		var s: Vector2 = profile[i]
		var ring: PackedVector3Array = _ring(s.x, s.y, x_scale, z_scale, sides, phase)
		# Optional per-ring Z shift (index-aligned with the profile; short or
		# empty array = centered). Rings stay circular — the shift moves the
		# whole ring, giving the lathe an asymmetric sway (the torso's seat)
		# while the angular UV convention is untouched.
		var z_off: float = z_offsets[i] if i < z_offsets.size() else 0.0
		if z_off != 0.0:
			for k in ring.size():
				ring[k].z += z_off
		if ring_deform.is_valid():
			ring = ring_deform.call(ring, s.x, s.y, z_off)
		rings.append(ring)
		vs.append(0.5 * (y_top - s.x) / span)
	for i in profile.size() - 1:
		for k in sides:
			var u0: float = float(k) / float(sides)
			var u1: float = float(k + 1) / float(sides)
			_uv_quad(st,
					rings[i][k], Vector2(u0, vs[i]),
					rings[i][k + 1], Vector2(u1, vs[i]),
					rings[i + 1][k + 1], Vector2(u1, vs[i + 1]),
					rings[i + 1][k], Vector2(u0, vs[i + 1]))
	var top_off: float = z_offsets[0] if z_offsets.size() > 0 else 0.0
	var bot_off: float = z_offsets[profile.size() - 1] \
			if z_offsets.size() >= profile.size() else 0.0
	var top_centre := Vector3(0.0, y_top, top_off)
	var bot_centre := Vector3(0.0, y_bot, bot_off)
	if ring_deform.is_valid():
		var first: PackedVector3Array = rings[0]
		var last: PackedVector3Array = rings[rings.size() - 1]
		top_centre = Vector3.ZERO
		bot_centre = Vector3.ZERO
		for k in sides:
			top_centre += first[k] / float(sides)
			bot_centre += last[k] / float(sides)
	_cap(st, rings[0], top_centre, Vector2(0.25, 0.75), true)
	_cap(st, rings[rings.size() - 1], bot_centre, Vector2(0.75, 0.75), false)
	st.generate_normals()
	return st.commit()


# One horizontal ring of sides+1 points (the last duplicates the first so the
# UV seam gets u = 1.0 instead of wrapping back to 0). θ starts at +Z (turned
# by `phase`) and advances toward +X — the engine primitive winding the
# painters expect.
static func _ring(y: float, radius: float, x_scale: float, z_scale: float,
		sides: int, phase: float = 0.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.resize(sides + 1)
	for k in sides + 1:
		var theta: float = TAU * float(k) / float(sides) + phase
		pts[k] = Vector3(sin(theta) * radius * x_scale, y, cos(theta) * radius * z_scale)
	return pts


# Fan cap over a ring. Cap UVs live on a disk inside the engine cylinder's cap
# quadrant (top cap around (0.25, 0.75), bottom around (0.75, 0.75)) — the
# painters only ever flood-fill these regions, so the disk mapping inside the
# quadrant is free.
static func _cap(st: SurfaceTool, ring: PackedVector3Array, center: Vector3,
		uv_center: Vector2, facing_up: bool, uv_radius: float = 0.24) -> void:
	var sides: int = ring.size() - 1
	for k in sides:
		var uv_k: Vector2 = uv_center + _cap_uv_offset(k, sides) * uv_radius
		var uv_k1: Vector2 = uv_center + _cap_uv_offset(k + 1, sides) * uv_radius
		if facing_up:
			_tri(st, center, uv_center, ring[k + 1], uv_k1, ring[k], uv_k)
		else:
			_tri(st, center, uv_center, ring[k], uv_k, ring[k + 1], uv_k1)


static func _cap_uv_offset(k: int, sides: int) -> Vector2:
	var theta: float = TAU * float(k) / float(sides)
	return Vector2(sin(theta), cos(theta))


# ── Ball (sphere-convention) parts ────────────────────────────────────────────


# Faceted lat/long ball with equirect UVs. v_end < 1 truncates the bottom at
# that latitude fraction and closes it with a flat cap (the helmet's jaw cut);
# v_end == 1 closes at the bottom pole. y_scale stretches along the pole axis
# (a prolate ball — same latitude-scaling SphereMesh's height param does, so
# the equirect painting convention holds). Pole stations collapse their band
# quads to triangles via the degenerate half of _uv_quad — zero-area triangles
# are invisible and flat shading gives every real face its own normal anyway.
static func _build_ball(radius: float, lon: int, lat: int, v_end: float,
		y_scale: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	var rings: Array[PackedVector3Array] = []
	var vs := PackedFloat32Array()
	for j in lat + 1:
		var v: float = v_end * float(j) / float(lat)
		var y: float = radius * cos(PI * v) * y_scale
		var ring_r: float = radius * sin(PI * v)
		rings.append(_ring(y, ring_r, 1.0, 1.0, lon))
		vs.append(v)
	for j in lat:
		for k in lon:
			var u0: float = float(k) / float(lon)
			var u1: float = float(k + 1) / float(lon)
			_uv_quad(st,
					rings[j][k], Vector2(u0, vs[j]),
					rings[j][k + 1], Vector2(u1, vs[j]),
					rings[j + 1][k + 1], Vector2(u1, vs[j + 1]),
					rings[j + 1][k], Vector2(u0, vs[j + 1]))
	if v_end < 1.0:
		var y_cut: float = radius * cos(PI * v_end) * y_scale
		_cap(st, rings[rings.size() - 1], Vector3(0.0, y_cut, 0.0), Vector2(0.5, 0.92), false, 0.07)
	st.generate_normals()
	return st.commit()


# ── Boot ──────────────────────────────────────────────────────────────────────


# The boot in the Foot node's rotated local frame (see _BOOT_STATIONS): a
# 6-point chamfered cross-section swept heel→toe, emitted as its two paintable
# pieces — the QUARTER (heel through instep) on surface 0 and the TOE cap on
# surface 1. Both are closed solids: each caps the ring they share, so the
# junction faces are interior and the winding stays testable (same reasoning as
# the helmet's liner closure). Solid-painted, so UVs are nominal.
static func _build_boot() -> ArrayMesh:
	var loops: Array[PackedVector3Array] = []
	for s: Vector4 in _BOOT_STATIONS:
		loops.append(_boot_loop(s.x, s.y, s.z, s.w))
	var m := ArrayMesh.new()
	_commit_sweep_segment(m, loops, 0, _BOOT_TOE_STATION, _boot_loop_center)
	_commit_sweep_segment(m, loops, _BOOT_TOE_STATION, loops.size() - 1, _boot_loop_center)
	return m


# A boot loop's axis point, midway between its top and sole edges — the apex
# each end cap fans to.
static func _boot_loop_center(loop: PackedVector3Array) -> Vector3:
	return Vector3(0.0, loop[0].y, (loop[0].z + loop[2].z) * 0.5)


# Sweeps `loops[first..last]` into a new closed surface of `target`, capping
# both ends so the piece is a solid on its own. `center_of` returns the axis
# point a loop's cap fans to. Splitting a sweep this way is how one part
# becomes several PAINTABLE pieces without becoming several meshes.
static func _commit_sweep_segment(target: ArrayMesh, loops: Array[PackedVector3Array],
		first: int, last: int, center_of: Callable) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	_sweep_loops(st, loops.slice(first, last + 1))
	_loop_cap(st, loops[first], center_of.call(loops[first]), true)
	_loop_cap(st, loops[last], center_of.call(loops[last]), false)
	st.generate_normals()
	st.commit(target)


# The blade as its two pieces: the HOLDER on surface 0 and the steel RUNNER on
# surface 1 (see the _BLADE_* constants' doc). They are separate surfaces
# because they are separate materials in life — the holder is molded plastic a
# player picks the color of, the runner is steel and always will be.
#
# The holder is one piece, not two posts: two towers dropping from the sole
# (they tuck up into it — z 0.042 < the boot's 0.045 sole line) bridged along
# the bottom by the RAIL the runner seats into, so only the steel's last few
# millimetres show below it. The arch between the towers stays open above the
# rail, which is the window a real holder is recognised by.
static func _build_skate_blade() -> ArrayMesh:
	var m := ArrayMesh.new()
	var holder := SurfaceTool.new()
	holder.begin(Mesh.PRIMITIVE_TRIANGLES)
	holder.set_smooth_group(-1)  # flat shading — see class doc block
	_box(holder, Vector3(-0.008, 0.036, 0.042), Vector3(0.008, 0.094, 0.098))    # heel tower
	_box(holder, Vector3(-0.008, -0.080, 0.042), Vector3(0.008, -0.026, 0.098))  # toe tower
	# Rail: tower to tower along the bottom, ending where the towers do, so the
	# runner's heel and toe tips still show past it.
	_box(holder, Vector3(-0.008, -0.080, 0.084), Vector3(0.008, 0.094, 0.098))
	holder.generate_normals()
	holder.commit(m)
	var runner := SurfaceTool.new()
	runner.begin(Mesh.PRIMITIVE_TRIANGLES)
	runner.set_smooth_group(-1)
	_box(runner, Vector3(-0.0035, RUNNER_TOE_Y, 0.090),
			Vector3(0.0035, RUNNER_HEEL_Y, BLADE_ICE_Z))
	runner.generate_normals()
	runner.commit(m)
	return m


# Boot cross-section at one station: narrowed top, full-width sidewall, tucked
# sole edge. Wound counter-clockwise as seen from +Y (the heel side) to match
# the lathe rings' winding sense, so the shared band-quad ordering stays
# outward-facing. Local +Z is DOWN in this frame, so top_z < sole_z.
static func _boot_loop(y: float, half_w: float, top_z: float, sole_z: float) -> PackedVector3Array:
	var mid_z: float = lerpf(top_z, sole_z, 0.55)
	var pts := PackedVector3Array()
	pts.resize(6)
	pts[0] = Vector3(-half_w * 0.62, y, top_z)
	pts[1] = Vector3(-half_w, y, mid_z)
	pts[2] = Vector3(-half_w * 0.72, y, sole_z)
	pts[3] = Vector3(half_w * 0.72, y, sole_z)
	pts[4] = Vector3(half_w, y, mid_z)
	pts[5] = Vector3(half_w * 0.62, y, top_z)
	return pts


# Band quads between consecutive CLOSED loops (equal point counts, no
# duplicated seam point — unlike _ring). Contract: loops are wound counter-
# clockwise as seen from the sweep's START side (the side loops[0] faces) and
# advance away from it, matching _ring/_boot_loop — the shared quad ordering
# then keeps every face outward. UVs are nominal; sweep parts paint solid.
# A closed sweep (torus) just appends its first loop again as the last.
static func _sweep_loops(st: SurfaceTool, loops: Array[PackedVector3Array]) -> void:
	var points: int = loops[0].size()
	for i in loops.size() - 1:
		for k in points:
			var k1: int = (k + 1) % points
			_uv_quad(st,
					loops[i][k], Vector2.ZERO,
					loops[i][k1], Vector2(0.1, 0.0),
					loops[i + 1][k1], Vector2(0.1, 0.1),
					loops[i + 1][k], Vector2(0.0, 0.1))


# Chamfered-rectangle cross-section, CCW seen from +Y (the sweep-loop
# contract). face_frac is the flat front/back segment's half-width as a
# fraction of hw; side_frac the flat side segment's half-depth as a fraction
# of hd.
static func _octagon_loop(y: float, hw: float, hd: float,
		face_frac: float, side_frac: float) -> PackedVector3Array:
	var fx: float = hw * face_frac
	var sz: float = hd * side_frac
	var pts := PackedVector3Array()
	pts.resize(8)
	pts[0] = Vector3(-fx, y, -hd)
	pts[1] = Vector3(-hw, y, -sz)
	pts[2] = Vector3(-hw, y, sz)
	pts[3] = Vector3(-fx, y, hd)
	pts[4] = Vector3(fx, y, hd)
	pts[5] = Vector3(hw, y, sz)
	pts[6] = Vector3(hw, y, -sz)
	pts[7] = Vector3(fx, y, -hd)
	return pts


# Fan cap over a closed loop. facing_start caps the sweep's start side
# (facing against the advance direction), the winding mirror of the end cap.
static func _loop_cap(st: SurfaceTool, loop: PackedVector3Array, center: Vector3,
		facing_start: bool) -> void:
	for k in loop.size():
		var k1: int = (k + 1) % loop.size()
		if facing_start:
			_tri(st, center, Vector2.ZERO, loop[k1], Vector2.ZERO, loop[k], Vector2.ZERO)
		else:
			_tri(st, center, Vector2.ZERO, loop[k], Vector2.ZERO, loop[k1], Vector2.ZERO)


# Axis-aligned box between two corners, wound clockwise-from-outside per face.
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var z0 := Vector2.ZERO
	_uv_quad(st,  # +Z
			Vector3(lo.x, hi.y, hi.z), z0, Vector3(hi.x, hi.y, hi.z), z0,
			Vector3(hi.x, lo.y, hi.z), z0, Vector3(lo.x, lo.y, hi.z), z0)
	_uv_quad(st,  # −Z
			Vector3(hi.x, hi.y, lo.z), z0, Vector3(lo.x, hi.y, lo.z), z0,
			Vector3(lo.x, lo.y, lo.z), z0, Vector3(hi.x, lo.y, lo.z), z0)
	_uv_quad(st,  # +X
			Vector3(hi.x, hi.y, hi.z), z0, Vector3(hi.x, hi.y, lo.z), z0,
			Vector3(hi.x, lo.y, lo.z), z0, Vector3(hi.x, lo.y, hi.z), z0)
	_uv_quad(st,  # −X
			Vector3(lo.x, hi.y, lo.z), z0, Vector3(lo.x, hi.y, hi.z), z0,
			Vector3(lo.x, lo.y, hi.z), z0, Vector3(lo.x, lo.y, lo.z), z0)
	_uv_quad(st,  # +Y
			Vector3(lo.x, hi.y, lo.z), z0, Vector3(hi.x, hi.y, lo.z), z0,
			Vector3(hi.x, hi.y, hi.z), z0, Vector3(lo.x, hi.y, hi.z), z0)
	_uv_quad(st,  # −Y
			Vector3(lo.x, lo.y, hi.z), z0, Vector3(hi.x, lo.y, hi.z), z0,
			Vector3(hi.x, lo.y, lo.z), z0, Vector3(lo.x, lo.y, lo.z), z0)


# ── Emission primitives ───────────────────────────────────────────────────────


# One quad as two triangles, corners listed CLOCKWISE as seen from outside the
# mesh (Godot's front-face winding, same convention as StickBladeMeshBuilder)
# so generate_normals() yields outward normals.
static func _uv_quad(st: SurfaceTool,
		a: Vector3, uva: Vector2, b: Vector3, uvb: Vector2,
		c: Vector3, uvc: Vector2, d: Vector3, uvd: Vector2) -> void:
	_tri(st, a, uva, b, uvb, c, uvc)
	_tri(st, a, uva, c, uvc, d, uvd)


static func _tri(st: SurfaceTool,
		a: Vector3, uva: Vector2, b: Vector3, uvb: Vector2,
		c: Vector3, uvc: Vector2) -> void:
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_uv(uvc)
	st.add_vertex(c)
