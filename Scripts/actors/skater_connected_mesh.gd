class_name SkaterConnectedMesh
extends RefCounted

# PROTOTYPE: the skater's body as one connected skin. The jersey grows its
# sleeves out of armholes in the torso, the pants split into both legs at the
# crotch, and each leg runs on through the knee into the sock. Every joint is
# blended across the bones either side of it instead of hidden under a ball or a
# cap; the elbow pad and the knee guard are bulges in the fabric. The helmet,
# the gloves and the skates stay the rigid parts the rig meshes carry
# (SkaterConnectedRigMeshes leaves out of them what this replaces).
#
# Off unless MITTS_CONNECTED_BODY=1 is in the environment or --connected-body is
# on the command line (or `enabled` is set before a skater is built), so the
# live game is unchanged while it is judged.
#
# The mesh is authored in a BIND POSE, the body as SkaterBodySkeleton holds it
# with HIPS, WAIST and SPINE at identity (the space the scene authors UpperBody's
# and LowerBody's parts in, both at rest), the legs straight and the arms in the
# hang below (_BIND_*). Each bind's inverse rest is its bone's global pose there,
# so a vertex weighted to several bones goes where each of them carries it, and
# a skinned vertex is the blend of those. Every existing bone it rides is posed
# by the rigs as before; the sleeves and knees add deform bones of their own
# (SkaterConnectedRig), because the arm bones roll from world up and the elbow
# needs both its halves turning about one hinge.

static var enabled: bool = OS.get_environment("MITTS_CONNECTED_BODY") == "1" \
		or OS.get_cmdline_args().has("--connected-body") \
		or OS.get_cmdline_user_args().has("--connected-body")

# Deform bones, appended to the body skeleton past its tail columns
# (SkaterBodySkeleton.deform_bone). Per side: the upper arm from the shoulder,
# the elbow's middle (half the bend, so the joint does not collapse), the
# forearm from the elbow; then each knee's middle, a child of its LEG bone; then
# each shoulder's middle, two thirds of the way from the chest to the upper arm,
# for the same reason as the elbow's; then each shoulder girdle, the third of
# the arm's swing the collarbone and the shoulder blade take (the scapulohumeral
# rhythm), which the armhole and the top of the shoulder ride.
enum Deform {
	UPPER_L, ELBOW_L, FORE_L, UPPER_R, ELBOW_R, FORE_R, KNEE_L, KNEE_R, SHOULDER_L, SHOULDER_R,
	GIRDLE_L, GIRDLE_R,
}
const DEFORM_COUNT: int = 12
# The share of the arm's swing off the chest each shoulder bone turns by.
const GIRDLE_SWING_SHARE: float = 1.0 / 3.0
const SHOULDER_SWING_SHARE: float = 2.0 / 3.0

# The skin's binds: the bone and its rest in the bind pose, by index.
enum Bind {
	TORSO, TAIL, PELVIS, THIGH_L, THIGH_R, SOCK_L, SOCK_R, KNEE_L, KNEE_R,
	UPPER_L, ELBOW_L, FORE_L, UPPER_R, ELBOW_R, FORE_R, SHOULDER_L, SHOULDER_R,
	GIRDLE_L, GIRDLE_R, COLUMN_BASE,
}

# Where the scene authors the parts this skin rides, at rest (Scenes/Skater.tscn:
# UpperBodyMesh, LegL/R, ThighL/R, ShinL/R, SockL/R), bind space.
const _TORSO_Y_M: float = 0.195
const _HIP := Vector3(0.13, -0.13, 0.0)
const _THIGH_DROP_M: float = 0.13
const _KNEE_DROP_M: float = 0.31
const _SOCK_DROP_M: float = 0.19

# The arms' bind hang, right side (the left mirrors it): from the shoulder
# marker's rest place (Skater.shoulder_offset, shoulder_height) the upper arm
# out, forward and 35° under level, the forearm bent on toward the front. The
# middle of the range the IK asks for — hanging at the sides, reaching for the
# stick, up over the head for a slapshot — so none of it is far from the bind.
const _BIND_SHOULDER := Vector3(0.22, 0.40, 0.0)
const _BIND_UPPER_DIR := Vector3(0.55, -0.85, -0.3)
const _BIND_FORE_DIR := Vector3(0.15, -0.45, -0.88)
# Skater.upper_arm_length / forearm_length and the sleeve's radius at their
# defaults: a deform bone's scale is the live arm over these.
const BIND_ARM_SEGMENT_M: float = 0.33
const BIND_SLEEVE_RADIUS_M: float = SkaterMeshBuilder.SLEEVE_RADIUS_M

const _TORSO_SIDES: int = SkaterMeshBuilder.TORSO_SIDES
const _LIMB_SIDES: int = 8

# The chest above the waist, torso-local (y, half width, half depth, squareness
# — 2 an ellipse, higher boxier — then the rear sway). Every ring is the rig's
# own section (SkaterMeshBuilder's 1.05 : 0.88 ellipse) at its own size: rings
# of one shape make planar quads between them, and a skin shaded flat by its
# drawn faces shows every quad that is not as a fold. Broad over the pads, in to
# the waist, where the rig's own rings take over (SkaterMeshBuilder.torso_ring, station 4 down: the
# jersey's tail and its tuck are the rig's and stay vertex for vertex the same).
# Stations 2–4 are the armhole's top, middle and bottom.
const _CHEST: Array[Vector4] = [
	Vector4(0.275, 0.1313, 0.1100, 2.0),   # collar
	Vector4(0.258, 0.1974, 0.1654, 2.0),   # trapezius, onto the pads
	Vector4(0.222, 0.2352, 0.1971, 2.0),   # shoulder line: the pads' top
	Vector4(0.160, 0.2394, 0.2006, 2.0),
	Vector4(0.095, 0.2331, 0.1954, 2.0),   # under the arm
	Vector4(0.045, 0.2268, 0.1901, 2.0),
]
const _CHEST_SWAY: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.003]
const _FIRST_TORSO_STATION: int = 4
const _LAST_TORSO_STATION: int = 10
const _ARMHOLE_TOP: int = 2
# The torso's facet column under each arm (the lathe's vertex at ±90°), left then
# right; the armhole is the 2 × 2 facets round it.
const _ARMHOLE_COLUMN: Array[int] = [7, 2]
# The armhole, bind space (right side): a round loop on the chest's side the
# size of the sleeve, centred under the shoulder joint, so the sleeve leaves the
# chest no wider than it is.
const _ARMHOLE_CENTRE := Vector3(0.0, 0.365, 0.0)
const _ARMHOLE_RADII := Vector2(0.084, 0.070)   # across (z), up (y)
# How far each armhole vertex rides the shoulder girdle, round the loop from the
# top's back corner (_build_torso's order), and the chest's vertices round it:
# the ring above (the trapezius) and the one below.
const _ARMHOLE_GIRDLE: Array[float] = [0.6, 0.7, 0.6, 0.85, 0.9, 0.95, 0.9, 0.85]
const _TRAP_GIRDLE := Vector2(0.35, 0.15)   # the column under the arm, its neighbours
const _FLANK_GIRDLE := Vector2(0.25, 0.1)

# The sleeve, out from the armhole: a ring standing off the torso toward the
# arm (the pad), then rings along the arm, each (s along its segment, radius).
const _PAD_DOWN_M: float = 0.07
const _PAD_OUT_M: float = 0.0
const _PAD_RADIUS_M: float = 0.086
const _UPPER_RINGS: Array[Vector2] = [
	Vector2(0.12, 0.086), Vector2(0.21, 0.080), Vector2(0.285, 0.079)]
const _ELBOW_RADIUS_M: float = 0.081
# The pad under the sleeve, out the back of the bend: its point and the two
# facets either side of it.
const _ELBOW_PAD_M: float = 0.020
const _FORE_RINGS: Array[Vector2] = [
	Vector2(0.045, 0.077), Vector2(0.13, 0.073), Vector2(0.20, 0.066), Vector2(0.26, 0.050)]
const _FORE_END_M: float = 0.28

# The pants, waist-space (the PELVIS bone's, which rests at bind identity):
# (y, half width, half depth, squareness), rear sway alongside. The top three are
# the rig's own pelvis rings, which the jersey tucks into
# (SkaterMeshBuilder._PELVIS_PROFILE); below them the hips widen over the hip
# joints to the seat, and the last ring is the crotch, where the legs split.
const _PANTS: Array[Vector4] = [
	Vector4(0.056, 0.184, 0.0, 2.0),
	Vector4(0.050, 0.186, 0.0, 2.0),
	Vector4(0.000, 0.190, 0.0, 2.0),
	Vector4(-0.060, 0.228, 0.180, 2.0),
	Vector4(-0.120, 0.258, 0.188, 2.0),   # the seat, over the hip joints
	Vector4(-0.200, 0.268, 0.176, 2.0),   # the crotch
]
const _PANTS_SWAY: Array[float] = [0.006, 0.006, 0.010, 0.016, 0.028, 0.012]
# The pants' top three rings are round lathe rings, scaled like the rig's.
const _PANTS_ROUND: int = 3
# The front centre of a pants ring, which runs from the back centre.
const _PANTS_FRONT: int = 5
const _CROTCH_Y_M: float = -0.215
const _CROTCH_FRONT_Z_M: float = -0.07
const _CROTCH_BACK_Z_M: float = 0.085

# Each leg below the crotch, bind space: (y, radius, its swell to the outside,
# its swell to the back) — then the knee's cap and the calf are added by
# station. The breezers flare a little to their hem, which turns in under itself
# to the sock; the sock runs over the shin guard's knee cap, down the calf and
# into the skate's collar.
const _LEG_RINGS: Array[Vector4] = [
	Vector4(-0.270, 0.128, 0.024, 0.006),
	Vector4(-0.335, 0.132, 0.022, 0.004),
	Vector4(-0.395, 0.138, 0.018, 0.0),    # the pants' hem
	Vector4(-0.402, 0.104, 0.0, 0.0),      # under it, the sock's top
	Vector4(-0.418, 0.102, 0.0, 0.0),
	Vector4(-0.440, 0.100, 0.0, 0.0),      # the knee
	Vector4(-0.472, 0.097, 0.0, 0.0),
	Vector4(-0.550, 0.093, 0.0, 0.004),
	Vector4(-0.650, 0.088, 0.0, 0.0),
	Vector4(-0.745, 0.080, 0.0, 0.0),
	Vector4(-0.780, 0.076, 0.0, 0.0),
]
const _LEG_HEM_RING: int = 2
const _LEG_KNEE_RING: int = 5
# The knee guard's cap through the sock (front, ring by ring) and the calf.
const _KNEE_CAP: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.006, 0.024, 0.014, 0.0, 0.0, 0.0, 0.0]
const _CALF: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.008, 0.004, 0.0, 0.0]
# Where the old sock lathe's top was: the sock's stripes are laid from there.
const _SOCK_TOP_Y_M: float = -0.48
const _SOCK_SIDE_M: float = 0.30

const _UpperSurface = SkaterMeshBuilder.UpperSurface
const _LegSurface = SkaterMeshBuilder.LegSurface

static var _cache: Dictionary = {}
static var _skin: Skin = null


# ── The skin ─────────────────────────────────────────────────────────────────

static func shared_skin() -> Skin:
	if _skin == null:
		_skin = Skin.new()
		var rests: Array[Transform3D] = bind_rests()
		var bones: PackedInt32Array = bind_bones()
		for i: int in bones.size():
			_skin.add_bind(bones[i], rests[i].affine_inverse())
	return _skin


# The body skeleton's bone per bind.
static func bind_bones() -> PackedInt32Array:
	var off: int = SkaterBodySkeleton.LEG_BONE_OFFSET
	var bones := PackedInt32Array([
		SkaterMeshBuilder.UpperBone.TORSO, SkaterBodySkeleton.TAIL_BONE,
		SkaterMeshBuilder.UpperBone.PELVIS,
		off + SkaterMeshBuilder.LegBone.THIGH_L, off + SkaterMeshBuilder.LegBone.THIGH_R,
		off + SkaterMeshBuilder.LegBone.SOCK_L, off + SkaterMeshBuilder.LegBone.SOCK_R,
		SkaterBodySkeleton.deform_bone(Deform.KNEE_L), SkaterBodySkeleton.deform_bone(Deform.KNEE_R),
	])
	for d: int in [Deform.UPPER_L, Deform.ELBOW_L, Deform.FORE_L,
			Deform.UPPER_R, Deform.ELBOW_R, Deform.FORE_R]:
		bones.append(SkaterBodySkeleton.deform_bone(d))
	bones.append(SkaterBodySkeleton.deform_bone(Deform.SHOULDER_L))
	bones.append(SkaterBodySkeleton.deform_bone(Deform.SHOULDER_R))
	bones.append(SkaterBodySkeleton.deform_bone(Deform.GIRDLE_L))
	bones.append(SkaterBodySkeleton.deform_bone(Deform.GIRDLE_R))
	for column: int in _TORSO_SIDES:
		for joint: int in 2:
			bones.append(SkaterBodySkeleton.column_bone(column, joint))
	return bones


# Each bind's bone in the bind pose, bind space.
static func bind_rests() -> Array[Transform3D]:
	var torso := Transform3D(Basis.IDENTITY, Vector3(0.0, _TORSO_Y_M, 0.0))
	var rests: Array[Transform3D] = [torso, torso, Transform3D.IDENTITY]
	for side: float in [-1.0, 1.0]:
		rests.append(Transform3D(Basis.IDENTITY, _hip(side) + Vector3.DOWN * _THIGH_DROP_M))
	for side: float in [-1.0, 1.0]:
		rests.append(Transform3D(Basis.IDENTITY,
				_hip(side) + Vector3.DOWN * (_KNEE_DROP_M + _SOCK_DROP_M)))
	for side: float in [-1.0, 1.0]:
		rests.append(Transform3D(Basis.IDENTITY, _knee(side)))
	for side: float in [-1.0, 1.0]:
		rests.append_array(sleeve_frames(bind_arm(side)))
	for i: int in 2:
		for side: float in [-1.0, 1.0]:
			rests.append(Transform3D(Basis.IDENTITY, bind_arm(side)[0]))
	# The tail's columns hang, at rest, exactly where the torso holds them
	# (SkaterHemFlaps: the rest drape is the lathe's own rings).
	for i: int in 2 * _TORSO_SIDES:
		rests.append(torso)
	return rests


# The arm's joints in the bind pose on `side` (-1 left): shoulder, elbow, hand,
# and the elbow's hinge as SkaterArmRig poses the ELBOW bone (its local Z: along
# the arm's chord crossed with the way the elbow points).
static func bind_arm(side: float) -> Array[Vector3]:
	var mirror := Vector3(side, 1.0, 1.0)
	var shoulder: Vector3 = _BIND_SHOULDER * mirror
	var elbow: Vector3 = shoulder + (_BIND_UPPER_DIR * mirror).normalized() * BIND_ARM_SEGMENT_M
	var hand: Vector3 = elbow + (_BIND_FORE_DIR * mirror).normalized() * BIND_ARM_SEGMENT_M
	var along: Vector3 = (hand - shoulder).normalized()
	var out: Vector3 = elbow - shoulder
	out = (out - along * out.dot(along)).normalized()
	return [shoulder, elbow, hand, along.cross(out)]


# The sleeve's three frames over an arm's joints (bind_arm's layout), unscaled:
# the upper arm at the shoulder, the elbow's middle and the forearm at the
# elbow. Each runs its local Y down its segment and shares the hinge as X, so the
# elbow turns its two halves about one axis and the sleeve does not twist
# through it; local +Z is the way the elbow points.
static func sleeve_frames(arm: Array[Vector3]) -> Array[Transform3D]:
	var shoulder: Vector3 = arm[0]
	var elbow: Vector3 = arm[1]
	var hand: Vector3 = arm[2]
	var hinge: Vector3 = arm[3]
	var upper: Vector3 = _unit_or(elbow - shoulder, Vector3.DOWN)
	var fore: Vector3 = _unit_or(hand - elbow, upper)
	var mid: Vector3 = _unit_or(upper + fore, upper)
	return [Transform3D(_hinged(upper, hinge), shoulder),
			Transform3D(_hinged(mid, hinge), elbow),
			Transform3D(_hinged(fore, hinge), elbow)]


static func _hinged(y: Vector3, hinge: Vector3) -> Basis:
	var x: Vector3 = hinge - y * hinge.dot(y)
	if x.length_squared() < 1e-8:
		x = Vector3.RIGHT - y * y.x
	x = x.normalized()
	return Basis(x, y, x.cross(y))


static func _unit_or(v: Vector3, fallback: Vector3) -> Vector3:
	return v.normalized() if v.length_squared() > 1e-10 else fallback


static func _hip(side: float) -> Vector3:
	return _HIP * Vector3(side, 1.0, 1.0)


static func _knee(side: float) -> Vector3:
	return _hip(side) + Vector3.DOWN * _KNEE_DROP_M


# ── The mesh ─────────────────────────────────────────────────────────────────

# One per GearModelRegistry TUCK_* option, like the rig's upper mesh: the tuck
# moves the jersey's tail and stands the pants' pad up.
static func shared_mesh(tuck: int) -> ArrayMesh:
	if not GearModelRegistry.is_valid_tuck(tuck):
		tuck = GearModelRegistry.TUCK_NONE
	return _shared("body_%d" % tuck, func() -> ArrayMesh:
		var b := ConnectedSkinBuilder.new()
		var armholes: Array[PackedInt32Array] = _build_torso(b, tuck)
		for i: int in 2:
			_build_sleeve(b, -1.0 if i == 0 else 1.0, armholes[i])
		_build_pants(b, tuck)
		return b.commit())


static func _shared(key: String, builder: Callable) -> ArrayMesh:
	var built: ArrayMesh = _cache.get(key)
	if built == null:
		built = builder.call()
		_cache[key] = built
	return built


static func _zone(surface: int) -> int:
	return SkaterMeshBuilder.UPPER_ZONE_BASE + surface


# The jersey from the collar to the hem, with an armhole each side. Returns the
# armholes' loops (left, right), each the eight torso vertices round the hole.
static func _build_torso(b: ConnectedSkinBuilder, tuck: int) -> Array[PackedInt32Array]:
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	var lift := Vector3(0.0, _TORSO_Y_M, 0.0)
	var y_top: float = _CHEST[0].x
	var span: float = SkaterMeshBuilder.TORSO_SIDE_HEIGHT_M
	var rings: Array[PackedInt32Array] = []
	var ys := PackedFloat32Array()
	for i: int in _CHEST.size():
		var s: Vector4 = _CHEST[i]
		var ids := PackedInt32Array()
		for k: int in _TORSO_SIDES:
			var theta: float = TAU * float(k) / float(_TORSO_SIDES) + phase
			var p: Vector3 = _super_ring_point(theta, s.y, s.z, s.w) \
					+ Vector3(0.0, s.x, _CHEST_SWAY[i]) + lift
			ids.append(_torso_vertex(b, p, s.x, theta, tuck, k))
		rings.append(ids)
		ys.append(s.x)
	for station: int in range(_FIRST_TORSO_STATION, _LAST_TORSO_STATION + 1):
		var rest_y: float = SkaterMeshBuilder.torso_ring(station, GearModelRegistry.TUCK_NONE)[0].y
		var ring: PackedVector3Array = SkaterMeshBuilder.torso_ring(station, tuck)
		var ids := PackedInt32Array()
		for k: int in _TORSO_SIDES:
			var theta: float = TAU * float(k) / float(_TORSO_SIDES) + phase
			ids.append(_torso_vertex(b, ring[k] + lift, rest_y, theta, tuck, k))
		rings.append(ids)
		ys.append(rest_y)
	var holes: Array[PackedInt32Array] = []
	for i: int in _ARMHOLE_COLUMN.size():
		holes.append(_cut_armhole(b, rings, _ARMHOLE_COLUMN[i], -1.0 if i == 0 else 1.0))

	var zone: int = _zone(_UpperSurface.TORSO)
	for i: int in rings.size() - 1:
		var v0: float = 0.5 * (y_top - ys[i]) / span
		var v1: float = 0.5 * (y_top - ys[i + 1]) / span
		var inside := Vector3(0.0, (ys[i] + ys[i + 1]) * 0.5, 0.0) + lift
		for k: int in _TORSO_SIDES:
			if _in_armhole(i, k):
				continue
			var k1: int = (k + 1) % _TORSO_SIDES
			var u0: float = float(k) / float(_TORSO_SIDES)
			var u1: float = float(k + 1) / float(_TORSO_SIDES)
			b.quad(rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k],
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1),
					zone, inside)
	# The collar and the hem close as the rig's lathe closes them, with its cap UVs.
	var collar: int = b.vertex(Vector3(0.0, y_top, 0.0) + lift, [Bind.TORSO], [1.0])
	_fan(b, rings[0], collar, Vector2(0.25, 0.75), zone, Vector3(0.0, y_top - 0.1, 0.0) + lift)
	var hem_y: float = ys[ys.size() - 1]
	var hem_centre := Vector3.ZERO
	for id: int in rings[rings.size() - 1]:
		hem_centre += b.position(id) / float(_TORSO_SIDES)
	var mean_tuck: float = 0.0
	for k: int in 36:
		mean_tuck += SkaterJerseyHem.tuck_share(tuck, TAU * float(k) / 36.0) / 36.0
	var hips: float = lerpf((1.0 + SkaterJerseyHem.CARRY_BACK) * 0.5, 1.0, mean_tuck)
	var hem: int = b.vertex(hem_centre, [Bind.TORSO, Bind.TAIL], [1.0 - hips, hips])
	_fan(b, rings[rings.size() - 1], hem, Vector2(0.75, 0.75), zone,
			Vector3(0.0, hem_y + 0.1, 0.0) + lift)

	return holes


# The armhole round `column`: the eight chest vertices round its 2 × 2 facets,
# laid on a sleeve-sized loop on the chest's side, and the shoulder round it put
# partly on the girdle. Returns the loop, from the top's back corner round.
static func _cut_armhole(b: ConnectedSkinBuilder, rings: Array[PackedInt32Array], column: int,
		side: float) -> PackedInt32Array:
	var a: int = _ARMHOLE_TOP
	var before: int = (column + _TORSO_SIDES - 1) % _TORSO_SIDES
	var after: int = (column + 1) % _TORSO_SIDES
	var hole := PackedInt32Array([
		rings[a][before], rings[a][column], rings[a][after], rings[a + 1][after],
		rings[a + 2][after], rings[a + 2][column], rings[a + 2][before], rings[a + 1][before],
	])
	var girdle: int = Bind.GIRDLE_L if side < 0.0 else Bind.GIRDLE_R
	var mid: Vector4 = _CHEST[a + 1]
	var centre: Vector3 = _ARMHOLE_CENTRE
	var psi := PackedFloat32Array()
	for id: int in hole:
		var d: Vector3 = b.position(id) - centre
		var angle: float = atan2(d.y, d.z)
		if not psi.is_empty():
			angle = psi[psi.size() - 1] + wrapf(angle - psi[psi.size() - 1], -PI, PI)
		psi.append(angle)
	var step: float = signf(psi[psi.size() - 1] - psi[0]) * TAU / float(hole.size())
	var offset: float = 0.0
	for i: int in hole.size():
		offset += (psi[i] - step * float(i)) / float(hole.size())
	for i: int in hole.size():
		var angle: float = offset + step * float(i)
		var z: float = cos(angle) * _ARMHOLE_RADII.x
		var across: float = pow(1.0 - pow(minf(absf(z) / mid.z, 1.0), mid.w), 1.0 / mid.w)
		b.move(hole[i], Vector3(side * mid.y * across, centre.y + sin(angle) * _ARMHOLE_RADII.y, z))
		b.reweight(hole[i], [Bind.TORSO, girdle],
				[1.0 - _ARMHOLE_GIRDLE[i], _ARMHOLE_GIRDLE[i]])
	for edge: Array in [[a - 1, _TRAP_GIRDLE], [a + 3, _FLANK_GIRDLE]]:
		var ring: PackedInt32Array = rings[edge[0]]
		var shares: Vector2 = edge[1]
		for k: int in [before, column, after]:
			var share: float = shares.x if k == column else shares.y
			b.reweight(ring[k], [Bind.TORSO, girdle], [1.0 - share, share])
	return hole


static func _in_armhole(ring: int, column: int) -> bool:
	if ring != _ARMHOLE_TOP and ring != _ARMHOLE_TOP + 1:
		return false
	for centre: int in _ARMHOLE_COLUMN:
		if column == centre or column == (centre + _TORSO_SIDES - 1) % _TORSO_SIDES:
			return true
	return false


# A point of a ring that is `squareness` between an ellipse (2) and a box, at
# azimuth θ from +Z toward +X.
static func _super_ring_point(theta: float, half_w: float, half_d: float,
		squareness: float) -> Vector3:
	var s: float = sin(theta)
	var c: float = cos(theta)
	var e: float = 2.0 / squareness
	return Vector3(signf(s) * pow(absf(s), e) * half_w, 0.0, signf(c) * pow(absf(c), e) * half_d)


# A torso vertex, weighted as SkaterJerseyHem.append_torso weights the rig's: on
# the chest above the tail, onto TAIL as the hips carry it, and from the belt
# down on its facet column's segment.
static func _torso_vertex(b: ConnectedSkinBuilder, p: Vector3, rest_y: float, theta: float,
		tuck: int, column: int) -> int:
	if rest_y <= SkaterJerseyHem.BELT_Y_M + 1e-5:
		var bend_y: float = SkaterMeshBuilder.torso_ring(
				SkaterMeshBuilder.TORSO_BEND_STATION, GearModelRegistry.TUCK_NONE)[0].y
		var lower: int = 1 if rest_y <= bend_y + 1e-5 else 0
		return b.vertex(p, [Bind.COLUMN_BASE + column * 2 + lower], [1.0])
	var t: float = SkaterJerseyHem.tuck_share(tuck, theta) * clampf(
			(SkaterJerseyHem.BUNCH_Y_M - rest_y) / (SkaterJerseyHem.BUNCH_Y_M - SkaterJerseyHem.PAD_Y_M),
			0.0, 1.0)
	var hips: float = SkaterJerseyHem.hang(rest_y) * lerpf(SkaterJerseyHem.carry(theta), 1.0, t)
	if hips <= 0.0:
		return b.vertex(p, [Bind.TORSO], [1.0])
	return b.vertex(p, [Bind.TORSO, Bind.TAIL], [1.0 - hips, hips])


# A fan from `centre` over a closed ring of vertex ids, cap UVs round `uv_centre`
# as SkaterMeshBuilder._cap lays them.
static func _fan(b: ConnectedSkinBuilder, ring: PackedInt32Array, centre: int,
		uv_centre: Vector2, zone: int, inside: Vector3) -> void:
	var n: int = ring.size()
	for k: int in n:
		var t0: float = TAU * float(k) / float(n)
		var t1: float = TAU * float(k + 1) / float(n)
		b.tri(centre, ring[k], ring[(k + 1) % n], uv_centre,
				uv_centre + Vector2(sin(t0), cos(t0)) * 0.24,
				uv_centre + Vector2(sin(t1), cos(t1)) * 0.24, zone, inside)


# One sleeve on `side`, grown from its armhole loop: the pad ring standing off
# the torso, then the arm through the elbow to the wrist inside the glove.
static func _build_sleeve(b: ConnectedSkinBuilder, side: float, hole: PackedInt32Array) -> void:
	var left: bool = side < 0.0
	var upper_bind: int = Bind.UPPER_L if left else Bind.UPPER_R
	var elbow_bind: int = Bind.ELBOW_L if left else Bind.ELBOW_R
	var fore_bind: int = Bind.FORE_L if left else Bind.FORE_R
	var shoulder_bind: int = Bind.SHOULDER_L if left else Bind.SHOULDER_R
	var upper_zone: int = _zone(_UpperSurface.TOP_UPPER_ARM if left else _UpperSurface.BOTTOM_UPPER_ARM)
	var fore_zone: int = _zone(_UpperSurface.TOP_FOREARM if left else _UpperSurface.BOTTOM_FOREARM)
	var pad_zone: int = _zone(_UpperSurface.TOP_ELBOW if left else _UpperSurface.BOTTOM_ELBOW)
	var cap_zone: int = _zone(_UpperSurface.SHOULDER_L if left else _UpperSurface.SHOULDER_R)
	var arm: Array[Vector3] = bind_arm(side)
	var frames: Array[Transform3D] = sleeve_frames(arm)
	var upper: Transform3D = frames[0]
	var mid: Transform3D = frames[1]
	var fore: Transform3D = frames[2]

	# The pad ring: off the shoulder down the arm and out from the torso, turned
	# halfway from the arm toward the side it leaves.
	var out := Vector3(side, 0.0, 0.0)
	var pad_centre: Vector3 = arm[0] + upper.basis.y * _PAD_DOWN_M + out * _PAD_OUT_M
	var pad_turn := Basis(Quaternion(upper.basis.y, (upper.basis.y + out).normalized()))
	var pad := PackedInt32Array()
	for m: int in _LIMB_SIDES:
		var phi: float = TAU * float(m) / float(_LIMB_SIDES)
		var dir: Vector3 = pad_turn * (upper.basis * Vector3(sin(phi), 0.0, cos(phi)))
		pad.append(b.vertex(pad_centre + dir * _PAD_RADIUS_M,
				[shoulder_bind], [1.0]))

	var rings: Array[PackedInt32Array] = [pad]
	var vs := PackedFloat32Array([0.0])
	var zones: Array[int] = [cap_zone]
	for r: Vector2 in _UPPER_RINGS:
		var weights: Array = [[upper_bind], [1.0]]
		if r == _UPPER_RINGS[_UPPER_RINGS.size() - 1]:
			weights = [[upper_bind, elbow_bind], [0.6, 0.4]]
		rings.append(_limb_ring(b, upper, r.x, r.y, 0.0, weights[0], weights[1]))
		vs.append(0.5 * r.x / BIND_ARM_SEGMENT_M)
		zones.append(cap_zone if rings.size() == 2 else upper_zone)
	rings.append(_limb_ring(b, mid, 0.0, _ELBOW_RADIUS_M, _ELBOW_PAD_M, [elbow_bind], [1.0]))
	vs.append(0.5)
	zones.append(upper_zone)
	var first_fore: int = rings.size()
	for r: Vector2 in _FORE_RINGS:
		var weights: Array = [[fore_bind], [1.0]]
		if r == _FORE_RINGS[0]:
			weights = [[elbow_bind, fore_bind], [0.4, 0.6]]
		rings.append(_limb_ring(b, fore, r.x, r.y, 0.0, weights[0], weights[1]))
		vs.append(0.5 * r.x / BIND_ARM_SEGMENT_M)
		zones.append(fore_zone)

	_bridge(b, hole, pad, cap_zone, _shoulder_uv.bind(side), (b.centroid(hole) + pad_centre) * 0.5)
	for i: int in rings.size() - 1:
		var inside: Vector3 = (b.centroid(rings[i]) + b.centroid(rings[i + 1])) * 0.5
		var v0: float = vs[i]
		var v1: float = vs[i + 1]
		if i + 1 == first_fore:
			v0 = 0.0
		for m: int in _LIMB_SIDES:
			var m1: int = (m + 1) % _LIMB_SIDES
			var zone: int = zones[i + 1]
			var elbow_band: bool = i + 1 == first_fore - 1 or i + 1 == first_fore
			if elbow_band and (m == 0 or m == _LIMB_SIDES - 1):
				zone = pad_zone
			var u0: float = float(m) / float(_LIMB_SIDES)
			var u1: float = float(m + 1) / float(_LIMB_SIDES)
			if i == 0:
				b.quad(rings[0][m], rings[0][m1], rings[1][m1], rings[1][m],
						_shoulder_uv(b.position(rings[0][m]), side),
						_shoulder_uv(b.position(rings[0][m1]), side),
						_shoulder_uv(b.position(rings[1][m1]), side),
						_shoulder_uv(b.position(rings[1][m]), side), zone, inside, true)
				continue
			b.quad(rings[i][m], rings[i][m1], rings[i + 1][m1], rings[i + 1][m],
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1),
					zone, inside)
	var end: Vector3 = fore * Vector3(0.0, _FORE_END_M, 0.0)
	var tip: int = b.vertex(end, [fore_bind], [1.0])
	var last: PackedInt32Array = rings[rings.size() - 1]
	for m: int in _LIMB_SIDES:
		b.tri(tip, last[m], last[(m + 1) % _LIMB_SIDES], Vector2(0.5, 0.45),
				Vector2(float(m) / _LIMB_SIDES, 0.4), Vector2(float(m + 1) / _LIMB_SIDES, 0.4),
				fore_zone, fore * Vector3(0.0, _FORE_END_M - 0.05, 0.0))


# A ring round a limb segment `s` down `frame`'s Y, `radius` across, with
# `bulge` more at its +Z point and half of it on the facets either side.
static func _limb_ring(b: ConnectedSkinBuilder, frame: Transform3D, s: float, radius: float,
		bulge: float, binds: Array, weights: Array) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for m: int in _LIMB_SIDES:
		var phi: float = TAU * float(m) / float(_LIMB_SIDES)
		var r: float = radius + bulge * maxf(cos(phi), 0.0) ** 2
		ids.append(b.vertex(frame * Vector3(sin(phi) * r, s, cos(phi) * r), binds, weights))
	return ids


# Joins two closed loops of the same count with quads, matching each vertex of
# `b_loop` to the vertex of `a_loop` that turns with it least.
static func _bridge(b: ConnectedSkinBuilder, a_loop: PackedInt32Array, b_loop: PackedInt32Array,
		zone: int, uv: Callable, inside: Vector3) -> void:
	var n: int = a_loop.size()
	var best_cost: float = INF
	var best_shift: int = 0
	var best_dir: int = 1
	for dir: int in [1, -1]:
		for shift: int in n:
			var cost: float = 0.0
			for m: int in n:
				cost += b.position(a_loop[posmod(shift + dir * m, n)]) \
						.distance_squared_to(b.position(b_loop[m]))
			if cost < best_cost:
				best_cost = cost
				best_shift = shift
				best_dir = dir
	for m: int in n:
		var a0: int = a_loop[posmod(best_shift + best_dir * m, n)]
		var a1: int = a_loop[posmod(best_shift + best_dir * (m + 1), n)]
		var b0: int = b_loop[m]
		var b1: int = b_loop[(m + 1) % n]
		b.quad(a0, a1, b1, b0, uv.call(b.position(a0)), uv.call(b.position(a1)),
				uv.call(b.position(b1)), uv.call(b.position(b0)), zone, inside, true)


# The shoulder's paint is ShoulderDecal's, laid round the upper arm as it was
# round the cap: U about the arm's axis from the world's +Z toward +X (so each
# side's material turns the number outboard), V down the arm from the yoke, at
# the cap's metres per V, with the number's band on the pad ring.
const _SHOULDER_V_AT_JOINT: float = 0.28


static func _shoulder_uv(p: Vector3, side: float) -> Vector2:
	var arm: Array[Vector3] = bind_arm(side)
	var axis: Vector3 = (arm[1] - arm[0]).normalized()
	var d: Vector3 = p - arm[0]
	var s: float = d.dot(axis)
	var across: Vector3 = Vector3.RIGHT - axis * axis.x
	var back: Vector3 = across.cross(axis).normalized() * -1.0
	across = across.normalized()
	var u: float = fposmod(atan2(d.dot(across), d.dot(back)) / TAU, 1.0)
	return Vector2(u, _SHOULDER_V_AT_JOINT + s / ShoulderDecal.CAP_M_PER_V)


# The pants: the waist and seat round both hips, splitting at the crotch into
# the legs, each on through the hem and the knee into the sock.
static func _build_pants(b: ConnectedSkinBuilder, tuck: int) -> void:
	var rings: Array[PackedInt32Array] = []
	for i: int in _PANTS.size():
		var s: Vector4 = _PANTS[i]
		var pts := PackedVector3Array()
		var xz: Vector2 = SkaterMeshBuilder.PELVIS_XZ_SCALE
		var half_w: float = s.y * xz.x if i < _PANTS_ROUND else s.y
		var half_d: float = s.y * xz.y if i < _PANTS_ROUND else s.z
		for k: int in _TORSO_SIDES + 1:
			var theta: float = TAU * float(k) / float(_TORSO_SIDES)
			pts.append(_super_ring_point(theta, half_w, half_d, s.w)
					+ Vector3(0.0, s.x, _PANTS_SWAY[i]))
		if tuck != GearModelRegistry.TUCK_NONE and i < 2:
			pts = SkaterJerseyHem.pad_ring(pts, s.x, s.y, _PANTS_SWAY[i], tuck, xz.x, xz.y,
					SkaterJerseyHem.PAD_RISE_M * (1.0 if i == 0 else SkaterJerseyHem.PAD_BULGE_SHARE),
					0.0 if i == 0 else SkaterJerseyHem.PAD_FLARE_M)
		var ids := PackedInt32Array()
		for k: int in _TORSO_SIDES:
			ids.append(b.vertex(pts[k], _pants_binds(i, k), _pants_weights(i, k)))
		rings.append(ids)
	for i: int in rings.size() - 1:
		var inside := Vector3(0.0, (_PANTS[i].x + _PANTS[i + 1].x) * 0.5, 0.0)
		for k: int in _TORSO_SIDES:
			var k1: int = (k + 1) % _TORSO_SIDES
			var ids: Array[int] = [rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]]
			var side: float = 1.0 if b.position(ids[0]).x + b.position(ids[1]).x > 0.0 else -1.0
			var zone: int = _LegSurface.THIGH_R if side > 0.0 else _LegSurface.THIGH_L
			b.quad(ids[0], ids[1], ids[2], ids[3], _pants_uv(side, b.position(ids[0])),
					_pants_uv(side, b.position(ids[1])), _pants_uv(side, b.position(ids[2])),
					_pants_uv(side, b.position(ids[3])), zone, inside, true)
	var waist: int = b.vertex(Vector3(0.0, _PANTS[0].x, _PANTS_SWAY[0]), [Bind.PELVIS], [1.0])
	_fan(b, rings[0], waist, Vector2(0.25, 0.75), _zone(_UpperSurface.PELVIS),
			Vector3(0.0, _PANTS[0].x - 0.1, 0.0))

	var crotch: PackedInt32Array = rings[rings.size() - 1]
	var front: int = b.vertex(Vector3(0.0, _CROTCH_Y_M, _CROTCH_FRONT_Z_M),
			[Bind.PELVIS, Bind.THIGH_L, Bind.THIGH_R], [0.5, 0.25, 0.25])
	var back: int = b.vertex(Vector3(0.0, _CROTCH_Y_M, _CROTCH_BACK_Z_M),
			[Bind.PELVIS, Bind.THIGH_L, Bind.THIGH_R], [0.5, 0.25, 0.25])
	var front_centre: int = _PANTS_FRONT
	for side: float in [-1.0, 1.0]:
		# Round the leg from the back centre: its half of the crotch ring, the
		# front centre, then the inseam back up the middle.
		var top := PackedInt32Array([crotch[0]])
		for j: int in range(1, front_centre):
			top.append(crotch[j] if side > 0.0 else crotch[_TORSO_SIDES - j])
		top.append_array([crotch[front_centre], front, back])
		_build_leg(b, side, top)


static func _pants_binds(ring: int, k: int) -> Array:
	var centre: bool = k == 0 or k == _PANTS_FRONT
	if ring < _PANTS.size() - 2 or (centre and ring == _PANTS.size() - 2):
		return [Bind.PELVIS]
	if centre:
		return [Bind.PELVIS, Bind.THIGH_L, Bind.THIGH_R]
	return [Bind.PELVIS, Bind.THIGH_R if k < _PANTS_FRONT else Bind.THIGH_L]


# Over the hips the pants start to go with the thighs: at the seat a little, at
# the crotch most of the way out at the sides and a little at the middle.
static func _pants_weights(ring: int, k: int) -> Array:
	var centre: bool = k == 0 or k == _PANTS_FRONT
	if ring == _PANTS.size() - 1:
		if centre:
			return [0.8, 0.1, 0.1]
		var near_side: bool = k % 5 == 2 or k % 5 == 3
		return [0.35, 0.65] if near_side else [0.6, 0.4]
	if ring == _PANTS.size() - 2 and not centre:
		var near_side: bool = k % 5 == 2 or k % 5 == 3
		return [0.7, 0.3] if near_side else [0.85, 0.15]
	return [1.0]


# The pants' stripe column is laid round each leg (U from +Z toward +X about the
# leg's axis, as the rig's thighs were) so it runs up over the hip to the waist.
static func _pants_uv(side: float, p: Vector3) -> Vector2:
	var axis: Vector3 = _hip(side)
	return Vector2(fposmod(atan2(p.x - axis.x, p.z - axis.z) / TAU, 1.0), 0.25)


# One leg below the crotch, from its top loop (`top`, eight vertices round the
# leg, the crotch ring's half and the inseam).
static func _build_leg(b: ConnectedSkinBuilder, side: float, top: PackedInt32Array) -> void:
	var left: bool = side < 0.0
	var thigh_bind: int = Bind.THIGH_L if left else Bind.THIGH_R
	var knee_bind: int = Bind.KNEE_L if left else Bind.KNEE_R
	var sock_bind: int = Bind.SOCK_L if left else Bind.SOCK_R
	var thigh_zone: int = _LegSurface.THIGH_L if left else _LegSurface.THIGH_R
	var sock_zone: int = _LegSurface.SOCK_L if left else _LegSurface.SOCK_R
	var knee_zone: int = _LegSurface.KNEE_L if left else _LegSurface.KNEE_R
	var axis: Vector3 = _hip(side)
	# The top loop's azimuths about the leg, mirrored so +φ is outward on both
	# sides, unwrapped to run one way round; the rings below ease them to even.
	var top_phi := PackedFloat32Array()
	for id: int in top:
		var d: Vector3 = b.position(id) - axis
		var phi: float = atan2(d.x * side, d.z)
		if not top_phi.is_empty():
			phi = top_phi[top_phi.size() - 1] + wrapf(phi - top_phi[top_phi.size() - 1], -PI, PI)
		top_phi.append(phi)
	var step: float = signf(top_phi[top_phi.size() - 1] - top_phi[0]) * TAU / float(_LIMB_SIDES)
	var offset: float = 0.0
	for j: int in _LIMB_SIDES:
		offset += (top_phi[j] - step * float(j)) / float(_LIMB_SIDES)
	var rings: Array[PackedInt32Array] = [top]
	for i: int in _LEG_RINGS.size():
		var s: Vector4 = _LEG_RINGS[i]
		var even: float = 0.65 if i == 0 else 1.0
		var ids := PackedInt32Array()
		for j: int in _LIMB_SIDES:
			var phi: float = lerpf(top_phi[j], offset + step * float(j), even)
			var r: float = s.y + s.z * sin(phi) + s.w * cos(phi) \
					+ _KNEE_CAP[i] * maxf(-cos(phi), 0.0) ** 3 + _CALF[i] * maxf(cos(phi), 0.0) ** 2
			var p := Vector3(axis.x + side * sin(phi) * r, s.x, cos(phi) * r)
			ids.append(b.vertex(p, _leg_binds(i, thigh_bind, knee_bind, sock_bind),
					_leg_weights(i)))
		rings.append(ids)
	for i: int in rings.size() - 1:
		var y_mid: float = (b.centroid(rings[i]).y + b.centroid(rings[i + 1]).y) * 0.5
		var inside := Vector3(axis.x, y_mid, 0.0)
		var sock: bool = i > _LEG_HEM_RING + 1
		for j: int in _LIMB_SIDES:
			var j1: int = (j + 1) % _LIMB_SIDES
			var ids: Array[int] = [rings[i][j], rings[i][j1], rings[i + 1][j1], rings[i + 1][j]]
			var zone: int = thigh_zone
			var uvs: Array[Vector2] = []
			for id: int in ids:
				var p: Vector3 = b.position(id)
				var u: float = fposmod(atan2(p.x - axis.x, p.z - axis.z) / TAU, 1.0)
				var v: float = 0.25
				if sock:
					v = 0.5 * clampf((_SOCK_TOP_Y_M - p.y) / _SOCK_SIDE_M, 0.0, 1.0)
				uvs.append(Vector2(u, v))
			if sock:
				zone = sock_zone
				var front: float = -(b.position(ids[0]) + b.position(ids[1])
						- Vector3(axis.x, 0.0, 0.0) * 2.0).normalized().z
				if (i == _LEG_KNEE_RING or i == _LEG_KNEE_RING + 1) and front > 0.4:
					zone = knee_zone
			b.quad(ids[0], ids[1], ids[2], ids[3], uvs[0], uvs[1], uvs[2], uvs[3],
					zone, inside, true)
	var last: PackedInt32Array = rings[rings.size() - 1]
	var foot: int = b.vertex(Vector3(axis.x, _LEG_RINGS[_LEG_RINGS.size() - 1].x, 0.0),
			[sock_bind], [1.0])
	for j: int in _LIMB_SIDES:
		b.tri(foot, last[j], last[(j + 1) % _LIMB_SIDES], Vector2(0.75, 0.75),
				Vector2(0.75, 0.75), Vector2(0.75, 0.75), sock_zone,
				Vector3(axis.x, _LEG_RINGS[_LEG_RINGS.size() - 1].x + 0.1, 0.0))


static func _leg_binds(ring: int, thigh: int, knee: int, sock: int) -> Array:
	if ring < _LEG_KNEE_RING - 1:
		return [thigh]
	if ring == _LEG_KNEE_RING - 1:
		return [thigh, knee]
	if ring == _LEG_KNEE_RING:
		return [knee]
	if ring == _LEG_KNEE_RING + 1:
		return [knee, sock]
	return [sock]


static func _leg_weights(ring: int) -> Array:
	if ring == _LEG_KNEE_RING - 1:
		return [0.65, 0.35]
	if ring == _LEG_KNEE_RING + 1:
		return [0.45, 0.55]
	return [1.0]
