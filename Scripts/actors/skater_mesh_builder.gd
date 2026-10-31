class_name SkaterMeshBuilder
extends RefCounted

# Low-poly faceted geometry for the skater. Cosmetic only — gameplay reads the
# Marker3D anchors and collision shapes, never these meshes.
#
# The rigid parts (SkaterRigidParts lays them on the body skeleton), the bone
# and paint-zone enums the body is addressed by, the torso's rest stations the
# connected skin is built round, and the goalie's and the gear tools' shared
# pieces. Every mesh here is cached and shared by the whole roster — per-skater
# colour is a paint zone, per-build sizing rides the scale in a bone's pose — so
# nothing is ever mutated per instance.
#
# UV layouts replicate the Godot primitives they replaced:
#   - Lathed (cylinder-style) parts: side U wraps from +Z toward +X with the
#     side occupying V ∈ [0, 0.5] top→bottom; the top cap disk lands in the
#     U ∈ [0, 0.5], V ∈ [0.5, 1] quadrant, the bottom cap in U ∈ [0.5, 1] of
#     the same half.
#   - Ball (sphere-style) parts: equirect, U from +Z toward +X, V from 0 at
#     the top pole to 1 at the bottom.
#
# Everything is flat-shaded (smooth_group(-1)) — the faceting IS the art
# style; per-face normals are what make the shaped silhouettes read.

# Profiles are (y, radius) stations top→bottom in the part's mesh-local frame,
# spanning the same envelope as the primitive each replaces (heights and radii
# from Scenes/Skater.tscn) so nothing pokes through ice, boards, or gear that
# was tuned around the primitive silhouettes.
const _TORSO_PROFILE: Array[Vector2] = [
	Vector2(0.275, 0.125),   # collar, around the neck's trapezius flare
	Vector2(0.255, 0.185),   # trapezius slope over the shoulder pads
	Vector2(0.215, 0.222),   # shoulder line — the pads' widest
	Vector2(0.130, 0.222),   # chest — from here the sweater hangs nearly straight,
	Vector2(0.000, 0.212),   # barely in at the waist
	Vector2(-0.070, 0.214),  # bunches over a tuck's pad (SkaterJerseyHem.BUNCH_Y_M)
	Vector2(-0.125, 0.218),  # goes in under a tuck's pad (SkaterJerseyHem.PAD_Y_M)
	Vector2(-0.150, 0.219),  # the pants' waistband line (SkaterJerseyHem.BELT_Y_M)
	Vector2(-0.210, 0.232),  # from here the tail hangs over the pants, flaring
	Vector2(-0.280, 0.263),  # out round the thighs' widest
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

# Chest reads wider than deep — lateral/depth scale on the torso's rings.
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
const _HELMET_LAT: int = 4
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

# A loose sleeve's radius at its full-width end; Skater and the glove read it.
# The elbow's pad is just proud of it.
const SLEEVE_RADIUS_M: float = 0.080
const ELBOW_PAD_RADIUS_M: float = SLEEVE_RADIUS_M * 1.04

# Gloved fist, swept along local Y from the wrist (+Y, toward the elbow) to the
# curled fingertips, its knuckle roll across local X; SkaterArmPoses.glove_basis
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
# defaults, the locker and bench figures): the cuff's center sits
# GLOVE_CUFF_BACK_M up the forearm from the fist's, spanning 0.05–0.13 m.
const GLOVE_FIST_RADIUS_M: float = 0.064
const GLOVE_CUFF_RADIUS_M: float = SLEEVE_RADIUS_M * 1.2
const GLOVE_CUFF_BACK_M: float = 0.09

# Arm-rig fixed dimensions. The cuff/knob heights are placement inputs on the
# skater side (SkaterArmPoses.cuff_pose / SkaterStickRig offset along the bone by
# half the height), so they live here with the geometry they measure.
const CUFF_HEIGHT_M: float = 0.08
const KNOB_HEIGHT_M: float = 0.05
const _KNOB_TOP_RADIUS: float = 0.035
const _KNOB_BOTTOM_RADIUS: float = 0.03

# The runner's steel. A MID gray: the holder is a paintable zone, so a near-white runner under a
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
# The steel's side profile, (y, z) in the same frame, round from its top at the
# toe: the nose curving up ahead of the holder, the flat the blade stands on
# from RUNNER_TOE_Y to RUNNER_HEEL_Y, and the tail rising behind the heel tower.
# Both curves leave the ice at ~30°, so a blade pitched less than that still
# touches it at the line's ends, where the contact solve stands it.
const _RUNNER_PROFILE: Array[Vector2] = [
	Vector2(-0.103, 0.090),
	Vector2(-0.1055, 0.097),
	Vector2(-0.1045, 0.104),
	Vector2(-0.1005, 0.110),
	Vector2(-0.094, 0.1165),
	Vector2(RUNNER_TOE_Y, BLADE_ICE_Z),
	Vector2(RUNNER_HEEL_Y, BLADE_ICE_Z),
	Vector2(0.1025, 0.1175),
	Vector2(0.1065, 0.1125),
	Vector2(0.109, 0.106),
	Vector2(0.1095, 0.090),
]
const _RUNNER_HALF_W: float = 0.0035
# The holder's side profiles, wound as _RUNNER_PROFILE is: the toe tower, its
# front sweeping down toward the steel's nose; the heel tower, the two leaning
# apart toward the rail; and the rail the
# steel seats into, joining them under the window between, which is what a real
# holder is recognised by. Their tops tuck up into the boot's sole
# (test_skate_upper.gd holds the seat). Wide where it bolts to the boot,
# narrowing to wrap the steel at the rail.
const _HOLDER_TOE: Array[Vector2] = [
	Vector2(-0.088, 0.042), Vector2(-0.098, 0.094), Vector2(-0.094, 0.100),
	Vector2(-0.038, 0.100), Vector2(-0.020, 0.042),
]
const _HOLDER_HEEL: Array[Vector2] = [
	Vector2(0.016, 0.042), Vector2(0.036, 0.100), Vector2(0.100, 0.100),
	Vector2(0.106, 0.092), Vector2(0.100, 0.042),
]
const _HOLDER_RAIL: Array[Vector2] = [
	Vector2(-0.094, 0.086), Vector2(-0.094, 0.100), Vector2(0.100, 0.100), Vector2(0.100, 0.086),
]
const _HOLDER_TOP_HALF_W: float = 0.011
const _HOLDER_RAIL_HALF_W: float = 0.0055
# Neck: skin tube from chin to collar, a child of the Helmet node like the
# head so it rides the same head-bulk scaling and skeleton offsets. Stations
# are helmet-local (helmet origin y 0.65, torso top 0.47): the top hides
# inside the head ball, the bottom flares into the traps where it sinks
# into the torso.
const NECK_PROFILE: Array[Vector2] = [
	Vector2(-0.095, 0.064),
	Vector2(-0.155, 0.070),
	Vector2(-0.190, 0.092),  # trapezius flare into the collar
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


# ── The leg bones ────────────────────────────────────────────────────────────
# Unlike the upper bones (UpperBone, flat), the legs are a CHAIN: LegL/R carry
# hip pitch and roll, ShinL/R hang off them and carry the knee, and the parts
# per leg ride whichever of the two they belong to. Keep the parents below
# mirroring that — flattening the chain means re-deriving the shin's world frame
# by hand on every gait tick.
#
# Bone order is L then R, pivot first.
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

# The legs' paint zones (zone = LegSurface). Not one per bone: the skate's one
# upper (SkateUpperMesh) is painted in its collar, accent stripe, quarter (SHELL),
# toe cap and laces, and the blade in its holder and steel runner — each a piece
# a gear MODEL paints on its own (GearModelRegistry); the runner stays steel by
# construction. The thigh, knee and sock zones are the connected skin's
# (SkaterConnectedPants).
enum LegSurface {
	THIGH_L, KNEE_L, SOCK_L,
	SKATE_L_COLLAR, SKATE_L_STRIPE,
	FOOT_L_SHELL, FOOT_L_TOE, FOOT_L_HOLDER, FOOT_L_RUNNER, FOOT_L_LACES,
	THIGH_R, KNEE_R, SOCK_R,
	SKATE_R_COLLAR, SKATE_R_STRIPE,
	FOOT_R_SHELL, FOOT_R_TOE, FOOT_R_HOLDER, FOOT_R_RUNNER, FOOT_R_LACES,
}
const LEG_SURFACE_COUNT: int = 20


# ── Merged assemblies ────────────────────────────────────────────────────────
# A part that never moves relative to its parent is a SURFACE, not a node, even
# when it needs its own material (the steel runner). Surfaces within a part
# mesh, for the parts that split into pieces a gear model paints separately.
const BLADE_PART_HOLDER: int = 0
const BLADE_PART_RUNNER: int = 1
const FIST_PART_BACK: int = 0
const FIST_PART_FINGERS: int = 1
const HELMET_SURF_SHELL: int = 0
const HELMET_SURF_SKIN: int = 1


# The head ball and its face, centred on the origin, face toward −Z, white but
# for the features' tints under the skin material. The keeper wears it inside
# his mask.
static func shared_head() -> ArrayMesh:
	return _shared("head", _build_head)


# The shell alone at a finer facet grid, for the body's own helmet
# (SkaterRigidParts).
static func shared_helmet_shell(lon: int, lat: int) -> ArrayMesh:
	return _shared("helmet_%d_%d" % [lon, lat], func() -> ArrayMesh:
		return _build_helmet(lon, lat))


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


# Appends one surface of `src` to `target` as a new surface. Callers that pass
# no transform rely on the part already sitting at identity in its parent's
# frame, which is what keeps the merge geometry-preserving.
static func _append_surface(target: ArrayMesh, src: ArrayMesh,
		xform: Transform3D = Transform3D.IDENTITY, src_surface: int = 0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(src, src_surface, xform)
	st.commit(target)


# ── The upper bones ──────────────────────────────────────────────────────────
# Thirteen bones of the body skeleton — both arms, the torso, the helmet/head
# unit, the pelvis. The rigid parts on them
# (SkaterRigidParts) are bound at identity, rigid to one bone each and left in
# their own local space, so a skinned vertex is exactly `bone_pose * v`.
#
# The shell parts hang from the SPINE bone and the pelvis from WAIST
# (SkaterBodySkeleton.upper_bone_parent); their poses are authored in a space
# that equals UpperBody's while those two rest at identity. The arm parts are
# roots, placed by IK straight in skeleton space.
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
	PELVIS,
}
const UPPER_BONE_COUNT: int = 13
# The upper paint zones (zone = UPPER_ZONE_BASE + UpperSurface). For the first
# ten a zone and its bone share a number, which the arm's surface seams rely on,
# so new zones go at the end. The connected skin paints TORSO, PELVIS and the
# two sleeves (SkaterConnectedMesh.sleeve_surface); the helmet's bone carries
# two zones, its shell and the head/neck skin.
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
	TOP_FINGERS,
	BOTTOM_FINGERS,
	PELVIS,
}
const UPPER_SURFACE_COUNT: int = 16
# The body's paint zones: the leg surfaces, then the upper ones.
const UPPER_ZONE_BASE: int = LEG_SURFACE_COUNT
const BODY_ZONE_COUNT: int = LEG_SURFACE_COUNT + UPPER_SURFACE_COUNT
# Scene node name per bone for the two parts whose placement is authored in
# Scenes/Skater.tscn rather than derived (the arm parts are placed by IK). Read
# by SkaterArmRig.build, which then frees them — same deal as LEG_BONE_NODE.
# Indices 0-9 are unused; the arm parts have no scene node.
const UPPER_BONE_NODE: Array[String] = [
	"", "", "", "", "", "", "", "", "", "",
	"UpperBodyMesh", "Helmet", "",
]


# ── The torso's rest stations ────────────────────────────────────────────────
# Stations of _TORSO_PROFILE the jersey's tail hangs by: the belt it hangs from,
# the bend between its two segments, and the hem.
const TORSO_BELT_STATION: int = 7
const TORSO_BEND_STATION: int = 9
const TORSO_HEM_STATION: int = 10


# One torso ring (sides + 1 points, the last repeating the first), torso-local.
static func torso_ring(station: int) -> PackedVector3Array:
	var s: Vector2 = _TORSO_PROFILE[station]
	var ring: PackedVector3Array = _ring(s.x, s.y, _TORSO_X_SCALE, _TORSO_Z_SCALE,
			_TORSO_SIDES, TAU * TORSO_U_PHASE)
	for k: int in ring.size():
		ring[k].z += _TORSO_REAR_SWAY[station]
	return ring


# The pants are wider than deep by this, as the torso is.
const PELVIS_XZ_SCALE := Vector2(_TORSO_X_SCALE, _TORSO_Z_SCALE)


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
		return m)


# Butt-end knob at its real dimensions (never rescaled).
static func shared_knob() -> ArrayMesh:
	return _shared("knob", func() -> ArrayMesh:
		var h: float = KNOB_HEIGHT_M * 0.5
		var profile: Array[Vector2] = [
			Vector2(h, _KNOB_TOP_RADIUS), Vector2(-h, _KNOB_BOTTOM_RADIUS)]
		return _build_lathe(profile, _LEG_SIDES, 1.0, 1.0))


# ── Part builders ─────────────────────────────────────────────────────────────


# Head ball at HEAD_RADIUS, sitting HEAD_FORWARD_M ahead of the helmet center,
# with its face (SkaterFaceMesh) — every vertex carries the tint the skin
# material multiplies, white but for the face's darker features.
static func _build_head() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.append_from(SkaterFaceMesh.untinted(_build_ball(HEAD_RADIUS, HEAD_LON, HEAD_LAT, 1.0)),
			0, Transform3D.IDENTITY)
	st.append_from(SkaterFaceMesh.build(HEAD_RADIUS, HEAD_LON, HEAD_LAT), 0, Transform3D.IDENTITY)
	return st.commit()

static func shared_skate_blade() -> ArrayMesh:
	return _shared("skate_blade", _build_skate_blade)


# Helmet shell: lat/long bands whose bottom latitude follows the per-azimuth cut
# (see the _HELMET_* constants), closed by a fan from the rim to an interior
# center — those closure faces hide inside the head ball, and closing keeps the
# solid's winding testable. Same ring orientation as _build_ball, so the shared
# quad ordering stays outward.
# `lon` × `lat` facets; the rig's shell is the defaults, and everything fitted
# under a helmet (hair, face gear) is fitted to that one.
static func _build_helmet(lon: int = _HELMET_LON, lat: int = _HELMET_LAT) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see class doc block
	var rings: Array[PackedVector3Array] = _helmet_rings(lon, lat)
	for j in rings.size() - 1:
		for k in lon:
			var a: Vector3 = rings[j][k]
			var b: Vector3 = rings[j][k + 1]
			var c: Vector3 = rings[j + 1][k + 1]
			var d: Vector3 = rings[j + 1][k]
			if _helmet_splits_ac(a, b, c, d):
				_uv_quad(st, a, Vector2.ZERO, b, Vector2(0.1, 0.0), c, Vector2(0.1, 0.1),
						d, Vector2(0.0, 0.1))
			else:
				_tri(st, a, Vector2.ZERO, b, Vector2(0.1, 0.0), d, Vector2(0.0, 0.1))
				_tri(st, b, Vector2(0.1, 0.0), c, Vector2(0.1, 0.1), d, Vector2(0.0, 0.1))
	var apex := Vector3(0.0, _HELMET_RADIUS * _HELMET_LINER_APEX_FRAC, 0.0)
	_cap(st, rings[rings.size() - 1], apex, Vector2(0.5, 0.9), false, 0.05)
	st.generate_normals()
	return st.commit()


# The shell's outer faces as a triangle list, helmet-local, without the liner
# that closes it — what anything worn under the helmet has to stay inside.
static func helmet_shell_triangles() -> PackedVector3Array:
	var rings: Array[PackedVector3Array] = _helmet_rings()
	var out := PackedVector3Array()
	for j in rings.size() - 1:
		for k in _HELMET_LON:
			var a: Vector3 = rings[j][k]
			var b: Vector3 = rings[j][k + 1]
			var c: Vector3 = rings[j + 1][k + 1]
			var d: Vector3 = rings[j + 1][k]
			if _helmet_splits_ac(a, b, c, d):
				out.append_array([a, b, c, a, c, d])
			else:
				out.append_array([a, b, d, b, c, d])
	return out


# Whether a shell quad (a, b, c, d round its edge) splits along a–c rather than
# b–d: whichever diagonal stands further out from the centre. Where the rim's
# cut drops between two azimuths (brow to ear loop) the quad twists, and the
# inner diagonal would fold the shell in through the temple under it.
static func _helmet_splits_ac(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	return (a + c).length() >= (b + d).length()


# The shell's rings from the crown down to the rim, each closed (its first
# point repeated at the end).
static func _helmet_rings(lon: int = _HELMET_LON, lat: int = _HELMET_LAT) \
		-> Array[PackedVector3Array]:
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
	return rings


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
# make_face_gear_material is the one paint source.

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


# Distance along `dir` from `at` (helmet-local, inside the face gear) to the
# innermost face piece's sphere, where the widest piece (the fishbowl) covers;
# INF where the ray leaves under or beside it.
static func face_gear_room(at: Vector3, dir: Vector3) -> float:
	var radius: float = minf(_CAGE_RADIUS, _FACE_SHIELD_RADIUS)
	var b: float = at.dot(dir)
	var t: float = -b + sqrt(maxf(b * b - at.length_squared() + radius * radius, 0.0))
	var hit: Vector3 = at + dir * t
	var off_front: float = absf(wrapf(atan2(hit.x, hit.z) - PI, -PI, PI))
	if off_front > _FISHBOWL_HALF_ARC or hit.y < _FACE_SHIELD_RADIUS * cos(PI * _FISHBOWL_V1):
		return INF
	return t


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


# ── Lathe (cylinder-convention) parts ─────────────────────────────────────────


# Faceted solid of revolution over (y, radius) stations, with the cylinder UV
# convention from the class doc block. Both end caps are emitted.
static func _build_lathe(profile: Array[Vector2], sides: int,
		x_scale: float, z_scale: float) -> ArrayMesh:
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
		rings.append(_ring(s.x, s.y, x_scale, z_scale, sides))
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
	_cap(st, rings[0], Vector3(0.0, y_top, 0.0), Vector2(0.25, 0.75), true)
	_cap(st, rings[rings.size() - 1], Vector3(0.0, y_bot, 0.0), Vector2(0.75, 0.75), false)
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


# ── Blade ──────────────────────────────────────────────────────────────────────


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


# The blade on the FOOT bone, in its rotated frame (SkateUpperMesh.SKATE_FROM_FOOT:
# toe −Y, +Z down), as its two pieces: the HOLDER on surface 0 and the steel
# RUNNER on surface 1. They are separate surfaces because they are separate
# materials in life — the holder is molded plastic a player picks the color of,
# the runner is steel and always will be, so it ships steel and an unpainted rig
# still shows it.
static func _build_skate_blade() -> ArrayMesh:
	var m := ArrayMesh.new()
	var holder := SurfaceTool.new()
	holder.begin(Mesh.PRIMITIVE_TRIANGLES)
	holder.set_smooth_group(-1)  # flat shading — see class doc block
	var taper := Vector4(_HOLDER_TOP_HALF_W, _HOLDER_RAIL_HALF_W,
			_HOLDER_TOE[0].y, _HOLDER_RAIL[1].y)
	for piece: Array[Vector2] in [_HOLDER_TOE, _HOLDER_HEEL, _HOLDER_RAIL]:
		_extrude_profile(holder, piece, taper)
	holder.generate_normals()
	holder.commit(m)
	var runner := SurfaceTool.new()
	runner.begin(Mesh.PRIMITIVE_TRIANGLES)
	runner.set_smooth_group(-1)
	_extrude_profile(runner, _RUNNER_PROFILE,
			Vector4(_RUNNER_HALF_W, _RUNNER_HALF_W, 0.0, 1.0))
	runner.generate_normals()
	runner.commit(m)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = BLADE_STEEL_COLOR
	steel.roughness = 0.25
	BodyRim.apply(steel)
	m.surface_set_material(BLADE_PART_RUNNER, steel)
	return m


# A convex side profile, (y, z), stood up across x as a closed solid: its two
# faces fanned from the first point and the rim between them. `taper` is the
# half-width at one depth and at another, (x at z1, x at z2, z1, z2), held
# linear in z between them and flat past them, so each face stays a plane.
static func _extrude_profile(st: SurfaceTool, profile: Array[Vector2], taper: Vector4) -> void:
	var z0 := Vector2.ZERO
	var n: int = profile.size()
	var near := PackedVector3Array()
	var far := PackedVector3Array()
	for p: Vector2 in profile:
		var half_w: float = lerpf(taper.x, taper.y, clampf((p.y - taper.z) / (taper.w - taper.z),
				0.0, 1.0))
		near.append(Vector3(half_w, p.x, p.y))
		far.append(Vector3(-half_w, p.x, p.y))
	for k: int in range(1, n - 1):
		_tri(st, near[0], z0, near[k], z0, near[k + 1], z0)
		_tri(st, far[0], z0, far[k + 1], z0, far[k], z0)
	for k: int in n:
		var k1: int = (k + 1) % n
		_uv_quad(st, near[k], z0, far[k], z0, far[k1], z0, near[k1], z0)


# Band quads between consecutive CLOSED loops (equal point counts, no
# duplicated seam point — unlike _ring). Contract: loops are wound counter-
# clockwise as seen from the sweep's START side (the side loops[0] faces) and
# advance away from it, matching _ring — the shared quad ordering
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
