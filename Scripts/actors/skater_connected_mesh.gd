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

# Preview only (tools/body_preview.gd --pants): the pants alone, the jersey and
# its sleeves left off so the pants can be seen.
static var preview_pants_only: bool = false

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
# The share of the arm's swing off the chest the shoulder's middle turns by,
# and the girdle's: little with the arm down, rising as it lifts — the
# collarbone and shoulder blade only come up with an arm raised, and the
# armpit's cloth, which rides the girdle, must go up with the arm but never
# fold into the chest when it comes down. Between the two the girdle eases by
# how far the arm's direction has risen against the chest from the bind's.
const SHOULDER_SWING_SHARE: float = 2.0 / 3.0
const GIRDLE_SWING_SHARE := Vector2(0.1, 0.6)   # arm hanging, arm overhead
const GIRDLE_RISE_SPAN := Vector2(-0.2, 1.0)

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

# The jersey has twice the rig's sides all the way down, and SkaterHemFlaps
# drapes its tail below the belt in as many columns, on bones of their own
# (SkaterBodySkeleton.connected_column_bone).
const _CHEST_SIDES: int = 2 * SkaterMeshBuilder.TORSO_SIDES
const TAIL_COLUMNS: int = _CHEST_SIDES
const LIMB_SIDES: int = 12

# The jersey above the belt, torso-local (y, radius, rear sway), every ring the
# rig's own 1.05 : 0.88 section at its own size: rings of one shape make planar
# quads between them, and a skin shaded flat by its drawn faces shows every quad
# that is not as a fold. Broad over the pads, in to the waist. Through the
# waist the rig's own stations take over (`_RIG_STATIONS`, vertex for vertex the
# rig's rings at every other column, so the jersey's tail and its tuck are the
# rig's), with a ring between each two, and on down the tail to the hem. Rings
# 1–3 are the armhole's top, middle and bottom.
const _CHEST: Array[Vector3] = [
	Vector3(0.275, 0.125, 0.0),   # collar
	Vector3(0.262, 0.200, 0.0),   # the shoulders' flat top: the armhole's top row
	Vector3(0.165, 0.228, 0.0),
	Vector3(0.075, 0.222, 0.002), # under the arm: its bottom row
	Vector3(0.025, 0.216, 0.004),
]
# SkaterMeshBuilder's torso stations the chest runs on through (waist, the
# ring that bunches over a tuck's pad, the ring under the pad), then the tail's
# from the belt to the hem.
const _RIG_STATIONS: Array[int] = [4, 5, 6]
const _BELT_STATION: int = SkaterMeshBuilder.TORSO_BELT_STATION
const _LAST_TORSO_STATION: int = SkaterMeshBuilder.TORSO_HEM_STATION
const _ARMHOLE_TOP: int = 1
# The chest's column under each arm (its vertex at ±90°), left then right; the
# armhole is the 2 × 4 facets round it.
const _ARMHOLE_COLUMN: Array[int] = [14, 4]
const _ARMHOLE_HALF_WIDTH: int = 2
# The armhole, bind space (right side): a hockey jersey's, its seam running
# from the shoulders' flat top down to under the arm, near upright, so the
# torso carries the shoulder's top out level from the neck and the sleeve
# leaves it at the side. A loop (centre, half sizes across and along the seam)
# tipped `_ARMHOLE_TILT` from facing straight out toward facing up.
const _ARMHOLE_CENTRE := Vector3(0.215, 0.365, 0.0)
const _ARMHOLE_RADII := Vector2(0.125, 0.100)   # across (z), along the seam
const _ARMHOLE_TILT: float = 0.15
# How far each armhole vertex rides the shoulder girdle, round the loop from the
# top's back corner (_cut_armhole's order) — all of it, so the loop turns as
# one ring and the sleeve leaving it cannot fold back over itself — and the
# chest's vertices round it: the ring above (the trapezius, which takes the
# shrug) and the one below, column by column.
const _ARMHOLE_GIRDLE: Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
const _TRAP_GIRDLE: Array[float] = [0.05, 0.1, 0.15, 0.1, 0.05]
const _FLANK_GIRDLE: Array[float] = [0.1, 0.25, 0.35, 0.25, 0.1]

# The sleeve, out from the armhole's seam: rings along the arm, each (s along
# its segment, radius, its share on the elbow's middle). The first is joined to
# the seam. The elbow folds over five rings.
# The share of the upper arm's first ring, the one joined to the seam, on the
# arm rather than the shoulder's middle: over the top of the arm, and under it,
# where it hangs back as armpit cloth does, so an arm raised overhead does not
# swing it up past the seam and fold the band between them over.
const _FIRST_RING_ARM_SHARE := Vector2(0.55, 0.15)
# The share of the seam's lowest point (the armpit) on the shoulder's middle
# rather than the girdle, easing to none at the seam's middle height.
const _ARMPIT_SHOULDER: float = 0.5
const _UPPER_RINGS: Array[Vector3] = [
	Vector3(0.12, 0.100, 0.0), Vector3(0.17, 0.091, 0.0), Vector3(0.22, 0.084, 0.0),
	Vector3(0.27, 0.079, 0.25), Vector3(0.305, 0.080, 0.6),
]
const _ELBOW_RADIUS_M: float = 0.081
# The pad under the sleeve, out the back of the bend, at its point.
const _ELBOW_PAD_M: float = 0.020
const _FORE_RINGS: Array[Vector3] = [
	Vector3(0.03, 0.079, 0.6), Vector3(0.07, 0.077, 0.25), Vector3(0.13, 0.073, 0.0),
	Vector3(0.20, 0.066, 0.0), Vector3(0.26, 0.050, 0.0),
]
const _FORE_END_M: float = 0.28

const _UpperSurface = SkaterMeshBuilder.UpperSurface

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
	for column: int in TAIL_COLUMNS:
		for joint: int in 2:
			bones.append(SkaterBodySkeleton.connected_column_bone(column, joint))
	return bones


# Each bind's bone in the bind pose, bind space.
static func bind_rests() -> Array[Transform3D]:
	var torso := Transform3D(Basis.IDENTITY, Vector3(0.0, _TORSO_Y_M, 0.0))
	var rests: Array[Transform3D] = [torso, torso, Transform3D.IDENTITY]
	for side: float in [-1.0, 1.0]:
		rests.append(Transform3D(Basis.IDENTITY, hip(side) + Vector3.DOWN * _THIGH_DROP_M))
	for side: float in [-1.0, 1.0]:
		rests.append(Transform3D(Basis.IDENTITY,
				hip(side) + Vector3.DOWN * (_KNEE_DROP_M + _SOCK_DROP_M)))
	for side: float in [-1.0, 1.0]:
		rests.append(Transform3D(Basis.IDENTITY, _knee(side)))
	for side: float in [-1.0, 1.0]:
		rests.append_array(sleeve_frames(bind_arm(side)))
	for i: int in 2:
		for side: float in [-1.0, 1.0]:
			rests.append(Transform3D(Basis.IDENTITY, bind_arm(side)[0]))
	# The tail's columns hang, at rest, exactly where the torso holds them
	# (SkaterHemFlaps: the rest drape is the lathe's own rings).
	for i: int in 2 * TAIL_COLUMNS:
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


static func hip(side: float) -> Vector3:
	return _HIP * Vector3(side, 1.0, 1.0)


static func _knee(side: float) -> Vector3:
	return hip(side) + Vector3.DOWN * _KNEE_DROP_M


# ── The mesh ─────────────────────────────────────────────────────────────────

# One per GearModelRegistry TUCK_* option, like the rig's upper mesh: the tuck
# moves the jersey's tail and stands the pants' pad up.
static func shared_mesh(tuck: int) -> ArrayMesh:
	if not GearModelRegistry.is_valid_tuck(tuck):
		tuck = GearModelRegistry.TUCK_NONE
	var pants_only: bool = preview_pants_only
	return _shared("body_%d_%s" % [tuck, pants_only], func() -> ArrayMesh:
		var b := ConnectedSkinBuilder.new()
		if not pants_only:
			var armholes: Array[PackedInt32Array] = _build_torso(b, tuck)
			for i: int in 2:
				_build_sleeve(b, -1.0 if i == 0 else 1.0, armholes[i])
		SkaterConnectedPants.build(b, tuck)
		return b.commit())


static func _shared(key: String, builder: Callable) -> ArrayMesh:
	var built: ArrayMesh = _cache.get(key)
	if built == null:
		built = builder.call()
		_cache[key] = built
	return built


static func zone(surface: int) -> int:
	return SkaterMeshBuilder.UPPER_ZONE_BASE + surface


# The jersey from the collar to the hem, with an armhole each side. Returns the
# armholes' loops (left, right).
static func _build_torso(b: ConnectedSkinBuilder, tuck: int) -> Array[PackedInt32Array]:
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	var lift := Vector3(0.0, _TORSO_Y_M, 0.0)
	var y_top: float = _CHEST[0].x
	var span: float = SkaterMeshBuilder.TORSO_SIDE_HEIGHT_M
	var profile: Array[Vector3] = _chest_profile()
	var rings: Array[PackedInt32Array] = []
	var ys := PackedFloat32Array()
	for station: Vector3 in profile:
		var pts: PackedVector3Array = SkaterJerseyHem.tuck_ring(
				_lathe_ring(station, _CHEST_SIDES, phase), station.x, station.y, station.z, tuck,
				phase, SkaterMeshBuilder.PELVIS_XZ_SCALE.x, SkaterMeshBuilder.PELVIS_XZ_SCALE.y)
		var ids := PackedInt32Array()
		for j: int in _CHEST_SIDES:
			var theta: float = TAU * float(j) / float(_CHEST_SIDES) + phase
			ids.append(_torso_vertex(b, pts[j] + lift, station.x, theta, tuck, -1))
		rings.append(ids)
		ys.append(station.x)
	for station: int in range(_BELT_STATION, _LAST_TORSO_STATION + 1):
		var rest_y: float = _rig_station(station).x
		var pts: PackedVector3Array = tail_ring(station, tuck)
		var ids := PackedInt32Array()
		for k: int in TAIL_COLUMNS:
			var theta: float = TAU * float(k) / float(TAIL_COLUMNS) + phase
			ids.append(_torso_vertex(b, pts[k] + lift, rest_y, theta, tuck, k))
		rings.append(ids)
		ys.append(rest_y)
	var holes: Array[PackedInt32Array] = []
	for i: int in _ARMHOLE_COLUMN.size():
		holes.append(_cut_armhole(b, rings, _ARMHOLE_COLUMN[i], -1.0 if i == 0 else 1.0))

	var torso_zone: int = zone(_UpperSurface.TORSO)
	for i: int in rings.size() - 1:
		var v0: float = 0.5 * (y_top - ys[i]) / span
		var v1: float = 0.5 * (y_top - ys[i + 1]) / span
		var inside := Vector3(0.0, (ys[i] + ys[i + 1]) * 0.5, 0.0) + lift
		var n: int = rings[i].size()
		for k: int in n:
			if _in_armhole(i, k):
				continue
			var k1: int = (k + 1) % n
			var u0: float = float(k) / float(n)
			var u1: float = float(k + 1) / float(n)
			b.quad(rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k],
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1),
					torso_zone, inside)
	# The collar and the hem close as the rig's lathe closes them, with its cap UVs.
	var collar: int = b.vertex(Vector3(0.0, y_top, 0.0) + lift, [Bind.TORSO], [1.0])
	fan(b, rings[0], collar, Vector2(0.25, 0.75), torso_zone, Vector3(0.0, y_top - 0.1, 0.0) + lift)
	var hem_y: float = ys[ys.size() - 1]
	var hem_centre := Vector3.ZERO
	for id: int in rings[rings.size() - 1]:
		hem_centre += b.position(id) / float(TAIL_COLUMNS)
	var mean_tuck: float = 0.0
	for k: int in 36:
		mean_tuck += SkaterJerseyHem.tuck_share(tuck, TAU * float(k) / 36.0) / 36.0
	var hips: float = lerpf((1.0 + SkaterJerseyHem.CARRY_BACK) * 0.5, 1.0, mean_tuck)
	var hem: int = b.vertex(hem_centre, [Bind.TORSO, Bind.TAIL], [1.0 - hips, hips])
	fan(b, rings[rings.size() - 1], hem, Vector2(0.75, 0.75), torso_zone,
			Vector3(0.0, hem_y + 0.1, 0.0) + lift)
	return holes


# The chest's rings, then the rig's waist stations with a ring halfway between
# each two, as (y, radius, sway) torso-local.
static func _chest_profile() -> Array[Vector3]:
	var out: Array[Vector3] = _CHEST.duplicate()
	var last := Vector3.INF
	for station: int in _RIG_STATIONS:
		var here: Vector3 = _rig_station(station)
		if last != Vector3.INF:
			out.append((last + here) * 0.5)
		out.append(here)
		last = here
	return out


# One of SkaterMeshBuilder's torso stations as (y, radius, sway), torso-local,
# read off the rig's own ring.
static func _rig_station(station: int) -> Vector3:
	var ring: PackedVector3Array = SkaterMeshBuilder.torso_ring(station, GearModelRegistry.TUCK_NONE)
	var sides: int = ring.size() - 1
	var sway: float = 0.0
	for k: int in sides:
		sway += ring[k].z / float(sides)
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	return Vector3(ring[0].y, ring[0].x / (sin(phase) * SkaterMeshBuilder.PELVIS_XZ_SCALE.x), sway)


# A tail ring at one of the rig's torso stations, as `tuck` drapes it, at this
# jersey's TAIL_COLUMNS sides: SkaterMeshBuilder.torso_ring's layout (sides + 1
# points, torso-local) with twice its columns, the rig's at every other one.
# SkaterHemFlaps hangs the connected tail from these.
static func tail_ring(station: int, tuck: int) -> PackedVector3Array:
	var phase: float = TAU * SkaterMeshBuilder.TORSO_U_PHASE
	var s: Vector3 = _rig_station(station)
	return SkaterJerseyHem.tuck_ring(_lathe_ring(s, TAIL_COLUMNS, phase), s.x, s.y, s.z, tuck,
			phase, SkaterMeshBuilder.PELVIS_XZ_SCALE.x, SkaterMeshBuilder.PELVIS_XZ_SCALE.y)


# A ring of the rig's section (SkaterMeshBuilder._ring's layout: `sides` + 1
# points from `phase`, the last repeating the first) at (y, radius, sway).
static func _lathe_ring(station: Vector3, sides: int, phase: float) -> PackedVector3Array:
	var xz: Vector2 = SkaterMeshBuilder.PELVIS_XZ_SCALE
	var pts := PackedVector3Array()
	for j: int in sides + 1:
		var theta: float = TAU * float(j) / float(sides) + phase
		pts.append(Vector3(sin(theta) * station.y * xz.x, station.x,
				station.z + cos(theta) * station.y * xz.y))
	return pts


# The armhole round `column`: the chest vertices round its facets, laid on the
# tipped loop, and the shoulder round it put partly on the girdle. Returns the loop, from the top's back corner round.
static func _cut_armhole(b: ConnectedSkinBuilder, rings: Array[PackedInt32Array], column: int,
		side: float) -> PackedInt32Array:
	var a: int = _ARMHOLE_TOP
	var w: int = _ARMHOLE_HALF_WIDTH
	var cols := PackedInt32Array()
	for c: int in range(-w, w + 1):
		cols.append(posmod(column + c, _CHEST_SIDES))
	var hole := PackedInt32Array()
	for c: int in cols:
		hole.append(rings[a][c])
	hole.append(rings[a + 1][cols[cols.size() - 1]])
	for i: int in range(cols.size() - 1, -1, -1):
		hole.append(rings[a + 2][cols[i]])
	hole.append(rings[a + 1][cols[0]])
	var girdle: int = Bind.GIRDLE_L if side < 0.0 else Bind.GIRDLE_R
	var centre: Vector3 = _ARMHOLE_CENTRE * Vector3(side, 1.0, 1.0)
	var along := Vector3(-side * sin(_ARMHOLE_TILT), cos(_ARMHOLE_TILT), 0.0)
	var psi := PackedFloat32Array()
	for id: int in hole:
		var d: Vector3 = b.position(id) - centre
		var angle: float = atan2(d.dot(along), d.z)
		if not psi.is_empty():
			angle = psi[psi.size() - 1] + wrapf(angle - psi[psi.size() - 1], -PI, PI)
		psi.append(angle)
	var step: float = signf(psi[psi.size() - 1] - psi[0]) * TAU / float(hole.size())
	var offset: float = 0.0
	for i: int in hole.size():
		offset += (psi[i] - step * float(i)) / float(hole.size())
	for i: int in hole.size():
		var angle: float = offset + step * float(i)
		b.move(hole[i], centre + along * sin(angle) * _ARMHOLE_RADII.y
				+ Vector3.BACK * cos(angle) * _ARMHOLE_RADII.x)
		b.reweight(hole[i], [Bind.TORSO, girdle],
				[1.0 - _ARMHOLE_GIRDLE[i], _ARMHOLE_GIRDLE[i]])
	for edge: Array in [[a - 1, _TRAP_GIRDLE], [a + 3, _FLANK_GIRDLE]]:
		var ring: PackedInt32Array = rings[edge[0]]
		var shares: Array[float] = edge[1]
		for c: int in cols.size():
			b.reweight(ring[cols[c]], [Bind.TORSO, girdle], [1.0 - shares[c], shares[c]])
	return hole


static func _in_armhole(ring: int, column: int) -> bool:
	if ring != _ARMHOLE_TOP and ring != _ARMHOLE_TOP + 1:
		return false
	for centre: int in _ARMHOLE_COLUMN:
		if posmod(column - centre + _ARMHOLE_HALF_WIDTH, _CHEST_SIDES) < 2 * _ARMHOLE_HALF_WIDTH:
			return true
	return false


# A torso vertex, weighted as SkaterJerseyHem.append_torso weights the rig's: on
# the chest above the tail, onto TAIL as the hips carry it, and from the belt
# down on its facet column's segment (`column`, of TAIL_COLUMNS).
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
static func fan(b: ConnectedSkinBuilder, ring: PackedInt32Array, centre: int,
		uv_centre: Vector2, fan_zone: int, inside: Vector3) -> void:
	var n: int = ring.size()
	for k: int in n:
		var t0: float = TAU * float(k) / float(n)
		var t1: float = TAU * float(k + 1) / float(n)
		b.tri(centre, ring[k], ring[(k + 1) % n], uv_centre,
				uv_centre + Vector2(sin(t0), cos(t0)) * 0.24,
				uv_centre + Vector2(sin(t1), cos(t1)) * 0.24, fan_zone, inside)


# One sleeve on `side`, grown from its armhole loop through the elbow to the
# wrist inside the glove.
static func _build_sleeve(b: ConnectedSkinBuilder, side: float, hole: PackedInt32Array) -> void:
	var left: bool = side < 0.0
	var upper_bind: int = Bind.UPPER_L if left else Bind.UPPER_R
	var elbow_bind: int = Bind.ELBOW_L if left else Bind.ELBOW_R
	var fore_bind: int = Bind.FORE_L if left else Bind.FORE_R
	var shoulder_bind: int = Bind.SHOULDER_L if left else Bind.SHOULDER_R
	var upper_zone: int = zone(_UpperSurface.TOP_UPPER_ARM if left else _UpperSurface.BOTTOM_UPPER_ARM)
	var fore_zone: int = zone(_UpperSurface.TOP_FOREARM if left else _UpperSurface.BOTTOM_FOREARM)
	var pad_zone: int = zone(_UpperSurface.TOP_ELBOW if left else _UpperSurface.BOTTOM_ELBOW)
	var cap_zone: int = zone(_UpperSurface.SHOULDER_L if left else _UpperSurface.SHOULDER_R)
	var arm: Array[Vector3] = bind_arm(side)
	var frames: Array[Transform3D] = sleeve_frames(arm)
	var upper: Transform3D = frames[0]
	var fore: Transform3D = frames[2]

	# The upper arm's first ring is joined straight to the seam, and rides
	# halfway from the shoulder's middle to the arm so the joint does not pinch.
	var rings: Array[PackedInt32Array] = []
	var vs := PackedFloat32Array()
	for r: Vector3 in _UPPER_RINGS:
		if rings.is_empty():
			var first: PackedInt32Array = _limb_ring(b, upper, r.x, r.y, 0.0, shoulder_bind,
					upper_bind, _FIRST_RING_ARM_SHARE.x)
			_hang_underside(b, first, arm[0], [shoulder_bind, upper_bind],
					_FIRST_RING_ARM_SHARE)
			rings.append(first)
		else:
			rings.append(_limb_ring(b, upper, r.x, r.y, 0.0, upper_bind, elbow_bind, r.z))
		vs.append(0.5 * r.x / BIND_ARM_SEGMENT_M)
	var elbow: int = rings.size()
	rings.append(_limb_ring(b, frames[1], 0.0, _ELBOW_RADIUS_M, _ELBOW_PAD_M,
			elbow_bind, elbow_bind, 1.0))
	vs.append(0.5)
	for r: Vector3 in _FORE_RINGS:
		rings.append(_limb_ring(b, fore, r.x, r.y, 0.0, fore_bind, elbow_bind, r.z))
		vs.append(0.5 * r.x / BIND_ARM_SEGMENT_M)

	# Between the seam and the arm's first ring, a ring on the straight line
	# joining them: no shape of its own at rest, but riding halfway from the
	# girdle to the shoulder's middle, so the turn between the chest and the arm
	# bends over two bands, not one that stretches flat or turns inside out.
	var seam: PackedInt32Array = _aligned(b, hole, rings[0])
	var girdle_bind: int = Bind.GIRDLE_L if left else Bind.GIRDLE_R
	var between := PackedInt32Array()
	for m: int in LIMB_SIDES:
		between.append(b.vertex(b.position(seam[m]).lerp(b.position(rings[0][m]), 0.5),
				[girdle_bind, shoulder_bind], [0.5, 0.5]))
	# The seam's armpit edge goes partly with the shoulder, so a raised arm
	# lifts it rather than folding the band under the arm over itself.
	for m: int in LIMB_SIDES:
		var under: float = smoothstep(0.0, -_ARMHOLE_RADII.y,
				b.position(seam[m]).y - _ARMHOLE_CENTRE.y)
		if under > 0.0:
			b.reweight(seam[m], [girdle_bind, shoulder_bind],
					[1.0 - _ARMPIT_SHOULDER * under, _ARMPIT_SHOULDER * under])
	var uv: Callable = _shoulder_uv.bind(side)
	_join(b, seam, between, cap_zone, uv, (b.centroid(seam) + b.centroid(between)) * 0.5)
	_join(b, between, rings[0], cap_zone, uv, (b.centroid(between) + b.centroid(rings[0])) * 0.5)
	for i: int in rings.size() - 1:
		var inside: Vector3 = (b.centroid(rings[i]) + b.centroid(rings[i + 1])) * 0.5
		var v0: float = 0.0 if i == elbow else vs[i]
		var v1: float = vs[i + 1]
		var band_zone: int = upper_zone if i < elbow else fore_zone
		for m: int in LIMB_SIDES:
			var m1: int = (m + 1) % LIMB_SIDES
			if i == 0:
				b.quad(rings[0][m], rings[0][m1], rings[1][m1], rings[1][m],
						_shoulder_uv(b.position(rings[0][m]), side),
						_shoulder_uv(b.position(rings[0][m1]), side),
						_shoulder_uv(b.position(rings[1][m1]), side),
						_shoulder_uv(b.position(rings[1][m]), side), cap_zone, inside, true)
				continue
			var face_zone: int = band_zone
			if (i == elbow - 1 or i == elbow) and (m == 0 or m == LIMB_SIDES - 1):
				face_zone = pad_zone
			var u0: float = float(m) / float(LIMB_SIDES)
			var u1: float = float(m + 1) / float(LIMB_SIDES)
			b.quad(rings[i][m], rings[i][m1], rings[i + 1][m1], rings[i + 1][m],
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1),
					face_zone, inside)
	var tip: int = b.vertex(fore * Vector3(0.0, _FORE_END_M, 0.0), [fore_bind], [1.0])
	var last: PackedInt32Array = rings[rings.size() - 1]
	for m: int in LIMB_SIDES:
		b.tri(tip, last[m], last[(m + 1) % LIMB_SIDES], Vector2(0.5, 0.45),
				Vector2(float(m) / LIMB_SIDES, 0.4), Vector2(float(m + 1) / LIMB_SIDES, 0.4),
				fore_zone, fore * Vector3(0.0, _FORE_END_M - 0.05, 0.0))


# A ring round a limb segment `s` down `frame`'s Y, `radius` across, with
# `bulge` more at its +Z point falling off round it, riding `own` and
# `elbow_share` of it on `elbow`.
static func _limb_ring(b: ConnectedSkinBuilder, frame: Transform3D, s: float, radius: float,
		bulge: float, own: int, elbow: int, elbow_share: float) -> PackedInt32Array:
	var binds: Array = [own]
	var weights: Array = [1.0]
	if elbow_share >= 1.0:
		binds = [elbow]
	elif elbow_share > 0.0:
		binds = [own, elbow]
		weights = [1.0 - elbow_share, elbow_share]
	var ids := PackedInt32Array()
	for m: int in LIMB_SIDES:
		var phi: float = TAU * float(m) / float(LIMB_SIDES)
		var r: float = radius + bulge * maxf(cos(phi), 0.0) ** 3
		ids.append(b.vertex(frame * Vector3(sin(phi) * r, s, cos(phi) * r), binds, weights))
	return ids


# Re-weights `ring` from `shares.x` on its second bind over the top of it to
# `shares.y` under it — facing down from `joint` in the bind pose.
static func _hang_underside(b: ConnectedSkinBuilder, ring: PackedInt32Array, joint: Vector3,
		binds: Array, shares: Vector2) -> void:
	for id: int in ring:
		var under: float = smoothstep(0.1, -0.9, (b.position(id) - joint).normalized().y)
		var share: float = lerpf(shares.x, shares.y, under)
		b.reweight(id, binds, [1.0 - share, share])


# `a_loop` turned and run to match `b_loop` vertex for vertex: each of
# `b_loop`'s against the one of `a_loop` that turns with it least.
static func _aligned(b: ConnectedSkinBuilder, a_loop: PackedInt32Array,
		b_loop: PackedInt32Array) -> PackedInt32Array:
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
	var out := PackedInt32Array()
	for m: int in n:
		out.append(a_loop[posmod(best_shift + best_dir * m, n)])
	return out


# Joins two closed loops already run vertex for vertex with quads.
static func _join(b: ConnectedSkinBuilder, a_loop: PackedInt32Array, b_loop: PackedInt32Array,
		join_zone: int, uv: Callable, inside: Vector3) -> void:
	var n: int = a_loop.size()
	for m: int in n:
		var a0: int = a_loop[m]
		var a1: int = a_loop[(m + 1) % n]
		var b0: int = b_loop[m]
		var b1: int = b_loop[(m + 1) % n]
		b.quad(a0, a1, b1, b0, uv.call(b.position(a0)), uv.call(b.position(a1)),
				uv.call(b.position(b1)), uv.call(b.position(b0)), join_zone, inside, true)


# The shoulder's paint is ShoulderDecal's, laid round the upper arm as it was
# round the cap: U about the arm's axis from the world's +Z toward +X (so each
# side's material turns the number outboard), V down the arm from the yoke, at
# the cap's metres per V, with the number's band across the seam.
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
