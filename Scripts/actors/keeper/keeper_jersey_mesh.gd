class_name KeeperJerseyMesh
extends RefCounted

# The keeper's jersey as ONE connected skin (ConnectedSkinBuilder), as the
# skaters' is (SkaterConnectedMesh): the body over the chest protector, and each
# sleeve grown out of an armhole in its side, over the shoulder floater, the arm
# pad and the elbow pad into the glove's cuff, every joint blended across the
# bones either side of it. So the sleeve is one tube SleeveDecal paints whole
# from the shoulder to the cuff, and the body one JerseyDecal paints. The tail
# below the hem is cloth of its own (KeeperJerseyTail).
#
# It is authored in a bind pose in the chest protector's box frame
# (KeeperGear.box), the arms out, forward and down (_BIND_*), and symmetric, so
# a right-catcher wears the same mesh with his arms' binds on the other hand's
# bones (bind_bones). Each bind's inverse rest is its bone's pose there
# (bind_rests); the bones are KeeperBodyRig's: the chest's and each arm piece's
# box, and a deform bone at each shoulder and each elbow (deform_pose).

const P := KeeperGear.Part
const _B := KeeperSkeleton.Bone

# KeeperBodyRig's bones past the gear's, per hand: the shoulder's middle, a
# share of the arm's swing off the chest (SHOULDER_SWING_SHARE), so the joint
# does not fold flat; the elbow's middle, half the bend, so it does not collapse.
enum Deform { SHOULDER_G, ELBOW_G, SHOULDER_B, ELBOW_B }
const DEFORM_COUNT: int = 4
const SHOULDER_SWING_SHARE: float = 0.5

# The skin's binds, by the side each arm is on: L at −X, R at +X.
enum Bind { CHEST, UPPER_L, FORE_L, SHOULDER_L, ELBOW_L, UPPER_R, FORE_R, SHOULDER_R, ELBOW_R }
const BIND_COUNT: int = 9
const _ARM_BINDS: int = 4

# Its paint zones in the keeper's BodyZonePaint: the body on the JERSEY slot,
# which no gear piece wears any more, and both sleeves on one past the slots.
const ZONE_TORSO: int = KeeperMeshKit.Slot.JERSEY
const ZONE_SLEEVE: int = KeeperMeshKit.SLOT_COUNT
const ZONE_COUNT: int = KeeperMeshKit.SLOT_COUNT + 1

# The yoke over his shoulders, down from the collar: the crest and the name
# hang below it.
const YOKE_DEPTH_M: float = 0.09
# How much of the chest's width a name may take, leaving a margin each side.
const NAME_WIDTH_SHARE: float = 0.85

# The arms' bind hang, +X side (−X mirrors it): the middle of the range his
# stances and saves ask for, hanging by his pads to out in front for the glove.
const _BIND_UPPER_DIR := Vector3(0.45, -0.75, -0.45)
const _BIND_FORE_DIR := Vector3(0.1, -0.35, -0.93)

# The body: the protector's sections (KeeperGearMeshes.jersey_ring) from the
# collar down to the hem, each walked round in TORSO_SIDES columns.
const TORSO_PER_EDGE: int = 4
const TORSO_SIDES: int = 8 * TORSO_PER_EDGE
# The armhole: the 2 × 4 facets round each side's middle column (L, R) below
# ring _ARMHOLE_TOP (the shoulders' top, where the slope to the collar begins),
# (a quarter of the way round from the back's middle is the +X side's), their
# loop laid on an ellipse (centre, half sizes across and along the seam)
# tipped _ARMHOLE_TILT toward the collar, so it faces out and up round the
# floater the sleeve leaves from.
const _ARMHOLE_TOP: int = 2
const _ARMHOLE_COLUMN: Array[int] = [24, 8]
const _ARMHOLE_HALF_WIDTH: int = 2
const _ARMHOLE_CENTRE := Vector3(0.25, 0.105, -0.01)
const _ARMHOLE_RADII := Vector2(0.11, 0.085)
const _ARMHOLE_TILT: float = 0.25
# How far the seam rides the shoulder's middle, and the chest's columns round it
# in the ring above and below the armhole (the shrug), column by column.
const _SEAM_SHOULDER: float = 0.5
const _TRAP_SHOULDER: Array[float] = [0.05, 0.1, 0.15, 0.1, 0.05]
const _FLANK_SHOULDER: Array[float] = [0.05, 0.1, 0.15, 0.1, 0.05]
# The sleeve's first ring on the arm rather than the shoulder's middle: over
# the top of the arm, and under it, where it hangs back as armpit cloth does.
const _FIRST_RING_ARM_SHARE := Vector2(0.55, 0.15)

# The sleeve, out from the seam: rings along the arm, each (s down its segment
# from the shoulder or the elbow, radius, its share on the elbow's middle), the
# elbow's turn spread over them as the skater's is (SkaterConnectedMesh). Over
# the floater and the arm pad inside the upper arm's box, through the elbow pad
# inside the forearm's, and in under the glove's cuff.
const _UPPER_RINGS: Array[Vector3] = [
	Vector3(0.10, 0.096, 0.0), Vector3(0.17, 0.090, 0.0), Vector3(0.23, 0.084, 0.08),
	Vector3(0.27, 0.081, 0.25), Vector3(0.31, 0.079, 0.5), Vector3(0.34, 0.078, 0.8),
]
const _ELBOW_RADIUS_M: float = 0.076
const _ELBOW_PAD_M: float = 0.006
const _FORE_RINGS: Array[Vector3] = [
	Vector3(0.02, 0.077, 0.8), Vector3(0.045, 0.076, 0.5), Vector3(0.075, 0.075, 0.25),
	Vector3(0.11, 0.073, 0.08), Vector3(0.16, 0.070, 0.0), Vector3(0.21, 0.066, 0.0),
]
const _FORE_END_M: float = 0.25

static var _mesh: ArrayMesh = null


# ── The bones ─────────────────────────────────────────────────────────────────

static func deform_bone(d: int) -> int:
	return KeeperGear.PART_COUNT + d


# A deform bone's pose on `skel`, keeper space: at the shoulder joint turned
# that share of the way from the chest to the upper arm, or at the elbow halfway
# from the upper arm to the forearm.
static func deform_pose(skel: KeeperSkeleton, d: int) -> Transform3D:
	var upper_bone: int = _B.UPPER_ARM_G if d < Deform.SHOULDER_B else _B.UPPER_ARM_B
	var upper: Transform3D = skel.xf[upper_bone]
	if d == Deform.SHOULDER_G or d == Deform.SHOULDER_B:
		return Transform3D(skel.xf[_B.CHEST].basis.slerp(upper.basis, SHOULDER_SWING_SHARE),
				upper.origin)
	var fore: Transform3D = skel.xf[upper_bone + 1]
	return Transform3D(upper.basis.slerp(fore.basis, 0.5), fore.origin)


# KeeperBodyRig's bone per bind: a right-catcher's glove arm is the +X one.
static func bind_bones(mirrored: bool) -> PackedInt32Array:
	var out := PackedInt32Array([P.CHEST])
	for side: int in 2:
		var glove: bool = (side == 0) != mirrored
		out.append(P.UPPER_ARM_G if glove else P.UPPER_ARM_B)
		out.append(P.FOREARM_G if glove else P.FOREARM_B)
		out.append(deform_bone(Deform.SHOULDER_G if glove else Deform.SHOULDER_B))
		out.append(deform_bone(Deform.ELBOW_G if glove else Deform.ELBOW_B))
	return out


# Each bind's bone in the bind pose, bind space (the chest's box frame). The
# bind is symmetric, so the −X arm's rests serve whichever hand it is.
static func bind_rests() -> Array[Transform3D]:
	var skel: KeeperSkeleton = _bind_skeleton()
	var rests: Array[Transform3D] = [KeeperGear.box(skel, P.CHEST)]
	for side: int in 2:
		rests.append(KeeperGear.box(skel, P.UPPER_ARM_G if side == 0 else P.UPPER_ARM_B))
		rests.append(KeeperGear.box(skel, P.FOREARM_G if side == 0 else P.FOREARM_B))
		rests.append(deform_pose(skel, Deform.SHOULDER_G if side == 0 else Deform.SHOULDER_B))
		rests.append(deform_pose(skel, Deform.ELBOW_G if side == 0 else Deform.ELBOW_B))
	return rests


# The bones the jersey rides, posed in the bind: the chest's box at the origin,
# the arms solved as KeeperSkeleton solves them, the glove's on −X.
static func _bind_skeleton() -> KeeperSkeleton:
	var skel := KeeperSkeleton.new()
	var chest := Transform3D(Basis.IDENTITY, -KeeperGear.center_on_bone(P.CHEST))
	skel.xf[_B.CHEST] = chest
	for side: int in 2:
		var flip := Vector3(-1.0 if side == 0 else 1.0, 1.0, 1.0)
		var shoulder: Vector3 = chest * Vector3(flip.x * KeeperAnatomy.SHOULDER_HALF_SPACING_M,
				KeeperAnatomy.SHOULDER_ABOVE_CHEST_M, 0.0)
		var elbow: Vector3 = shoulder + (_BIND_UPPER_DIR * flip).normalized() * KeeperAnatomy.UPPER_ARM_M
		var wrist: Vector3 = elbow + (_BIND_FORE_DIR * flip).normalized() * KeeperAnatomy.FOREARM_M
		var upper: int = _B.UPPER_ARM_G if side == 0 else _B.UPPER_ARM_B
		skel.xf[upper] = Transform3D(KeeperSkeleton.limb_basis(shoulder - elbow, Vector3.FORWARD),
				shoulder)
		skel.xf[upper + 1] = Transform3D(KeeperSkeleton.limb_basis(elbow - wrist, Vector3.FORWARD),
				elbow)
	return skel


# ── The paint's frame ─────────────────────────────────────────────────────────

# Round him, where the name and number sit: the sections from the belly to the
# chest, averaged.
static func girth_m() -> float:
	var h: Vector3 = KeeperGear.half_extents(P.CHEST)
	var total: float = 0.0
	for station: int in [1, 2, 3]:
		var ring: PackedVector3Array = KeeperGearMeshes.jersey_section(h, station)
		for i: int in ring.size():
			total += ring[i].distance_to(ring[(i + 1) % ring.size()])
	return total / 3.0


static func name_max_width_m() -> float:
	return KeeperAnatomy.CHEST_WIDTH_M * NAME_WIDTH_SHARE


# A JerseyDecal laid out for him.
static func lay_out(decal: JerseyDecal) -> void:
	decal.side_height_m = KeeperJerseyTail.jersey_length_m()
	decal.girth_m = girth_m()
	decal.yoke_depth_m = YOKE_DEPTH_M
	decal.name_max_width_m = name_max_width_m()


# The body's texture U at the back's middle (JerseyDecal's back-centre column):
# U runs on round him from there toward +X, as far round as it is of the way.
static func back_u() -> float:
	return float(JerseyDecal.BACK_CENTER_X) / float(JerseyDecal.IMG_W)


# The texture V `depth_m` below the collar: the side region is the decal's top
# half.
static func torso_v(depth_m: float) -> float:
	return 0.5 * depth_m / KeeperJerseyTail.jersey_length_m()


# ── The mesh ──────────────────────────────────────────────────────────────────

static func shared_mesh() -> ArrayMesh:
	if _mesh == null:
		var b := ConnectedSkinBuilder.new()
		var holes: Array[PackedInt32Array] = _build_torso(b)
		var skel: KeeperSkeleton = _bind_skeleton()
		for side: int in 2:
			_build_sleeve(b, side, holes[side], skel)
		_mesh = b.commit()
	return _mesh


# The body from the collar to the hem, an armhole each side. Returns the
# armholes' loops (L, R).
static func _build_torso(b: ConnectedSkinBuilder) -> Array[PackedInt32Array]:
	var h: Vector3 = KeeperGear.half_extents(P.CHEST)
	var rings: Array[PackedInt32Array] = []
	var us: Array[PackedFloat32Array] = []
	var vs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for r: int in KeeperGearMeshes.JERSEY_STATIONS:
		var pts: PackedVector3Array = KeeperGearMeshes.jersey_ring(h,
				KeeperGearMeshes.JERSEY_STATIONS - 1 - r, TORSO_PER_EDGE)
		var ids := PackedInt32Array()
		var u := PackedFloat32Array()
		for j: int in TORSO_SIDES:
			ids.append(b.vertex(pts[j], [Bind.CHEST], [1.0]))
			u.append(back_u() + KeeperGearMeshes.round_share(pts, pts[j]))
		rings.append(ids)
		us.append(u)
		ys.append(pts[0].y)
		vs.append(torso_v(h.y - pts[0].y))
	var holes: Array[PackedInt32Array] = []
	for side: int in 2:
		holes.append(_cut_armhole(b, rings, side))

	for r: int in rings.size() - 1:
		var inside := Vector3(0.0, (ys[r] + ys[r + 1]) * 0.5, 0.0)
		for k: int in TORSO_SIDES:
			if _in_armhole(r, k):
				continue
			var k1: int = (k + 1) % TORSO_SIDES
			b.quad(rings[r][k], rings[r][k1], rings[r + 1][k1], rings[r + 1][k],
					Vector2(us[r][k], vs[r]), Vector2(us[r][k1], vs[r]),
					Vector2(us[r + 1][k1], vs[r + 1]), Vector2(us[r + 1][k], vs[r + 1]),
					ZONE_TORSO, inside, true)
	# The collar: the top closed in the decal's top cap, the kit's collar.
	var top: int = b.vertex(b.centroid(rings[0]), [Bind.CHEST], [1.0])
	b.fan(rings[0], top, Vector2(JerseyDecal.UV_OFFSET_X + 0.25, 0.75), ZONE_TORSO,
			Vector3(0.0, ys[0] - 0.1, 0.0))
	# The hem closed under the tail, in the hem's own paint.
	var last: int = rings.size() - 1
	var hem: int = b.vertex(b.centroid(rings[last]), [Bind.CHEST], [1.0])
	for k: int in TORSO_SIDES:
		var k1: int = (k + 1) % TORSO_SIDES
		b.tri(hem, rings[last][k], rings[last][k1], Vector2(us[last][k], vs[last]),
				Vector2(us[last][k], vs[last]), Vector2(us[last][k1], vs[last]), ZONE_TORSO,
				Vector3(0.0, ys[last] + 0.1, 0.0), true)
	return holes


# The armhole on `side` (0 the −X one): the body's vertices round its facets,
# laid on the tipped loop and put partly on the shoulder's middle, and the
# chest round it a little. Returns the loop, from the top's back corner round.
static func _cut_armhole(b: ConnectedSkinBuilder, rings: Array[PackedInt32Array],
		side: int) -> PackedInt32Array:
	var sx: float = -1.0 if side == 0 else 1.0
	var a: int = _ARMHOLE_TOP
	var w: int = _ARMHOLE_HALF_WIDTH
	var cols := PackedInt32Array()
	for c: int in range(-w, w + 1):
		cols.append(posmod(_ARMHOLE_COLUMN[side] + c, TORSO_SIDES))
	var hole := PackedInt32Array()
	for c: int in cols:
		hole.append(rings[a][c])
	hole.append(rings[a + 1][cols[cols.size() - 1]])
	for i: int in range(cols.size() - 1, -1, -1):
		hole.append(rings[a + 2][cols[i]])
	hole.append(rings[a + 1][cols[0]])
	var shoulder: int = _bind(side, Bind.SHOULDER_L)
	var centre: Vector3 = _ARMHOLE_CENTRE * Vector3(sx, 1.0, 1.0)
	var along := Vector3(-sx * sin(_ARMHOLE_TILT), cos(_ARMHOLE_TILT), 0.0)
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
		b.reweight(hole[i], [Bind.CHEST, shoulder], [1.0 - _SEAM_SHOULDER, _SEAM_SHOULDER])
	for edge: Array in [[a - 1, _TRAP_SHOULDER], [a + 3, _FLANK_SHOULDER]]:
		var ring: PackedInt32Array = rings[edge[0]]
		var shares: Array[float] = edge[1]
		for c: int in cols.size():
			b.reweight(ring[cols[c]], [Bind.CHEST, shoulder], [1.0 - shares[c], shares[c]])
	return hole


static func _in_armhole(ring: int, column: int) -> bool:
	if ring != _ARMHOLE_TOP and ring != _ARMHOLE_TOP + 1:
		return false
	for centre: int in _ARMHOLE_COLUMN:
		if posmod(column - centre + _ARMHOLE_HALF_WIDTH, TORSO_SIDES) < 2 * _ARMHOLE_HALF_WIDTH:
			return true
	return false


# The bind `which` (an L one) on `side`.
static func _bind(side: int, which: int) -> int:
	return which + side * _ARM_BINDS


# One sleeve on `side` (0 the −X one), grown from its armhole loop through the
# elbow to the wrist inside the glove's cuff, on `skel`'s bind arm.
static func _build_sleeve(b: ConnectedSkinBuilder, side: int, hole: PackedInt32Array,
		skel: KeeperSkeleton) -> void:
	var sx: float = -1.0 if side == 0 else 1.0
	var upper_bind: int = _bind(side, Bind.UPPER_L)
	var fore_bind: int = _bind(side, Bind.FORE_L)
	var shoulder_bind: int = _bind(side, Bind.SHOULDER_L)
	var elbow_bind: int = _bind(side, Bind.ELBOW_L)
	var upper_bone: int = _B.UPPER_ARM_G if side == 0 else _B.UPPER_ARM_B
	var shoulder: Vector3 = skel.xf[upper_bone].origin
	var elbow: Vector3 = skel.xf[upper_bone + 1].origin
	var wrist: Vector3 = elbow - skel.xf[upper_bone + 1].basis.y * KeeperAnatomy.FOREARM_M
	var along: Vector3 = (wrist - shoulder).normalized()
	var out: Vector3 = elbow - shoulder
	out = (out - along * out.dot(along)).normalized()
	var frames: Array[Transform3D] = SkaterConnectedMesh.sleeve_frames(
			[shoulder, elbow, wrist, along.cross(out)])
	var upper: Transform3D = frames[0]
	var fore: Transform3D = frames[2]

	var rings: Array[PackedInt32Array] = []
	var axes: Array[Transform3D] = []
	var vs := PackedFloat32Array()
	for r: Vector3 in _UPPER_RINGS:
		var frame: Transform3D = SkaterConnectedMesh.round_elbow(frames, r.z * 0.5)
		if rings.is_empty():
			frame = upper
			var first: PackedInt32Array = SkaterConnectedMesh.limb_ring(b, upper, r.x, r.y, 0.0,
					shoulder_bind, upper_bind, _FIRST_RING_ARM_SHARE.x)
			SkaterConnectedMesh.hang_underside(b, first, shoulder, [shoulder_bind, upper_bind],
					_FIRST_RING_ARM_SHARE)
			rings.append(first)
		else:
			rings.append(SkaterConnectedMesh.limb_ring(b, frame, r.x - KeeperAnatomy.UPPER_ARM_M,
					r.y, _ELBOW_PAD_M * r.z, upper_bind, elbow_bind, r.z))
		axes.append(frame)
		vs.append(_upper_v(r.x))
	rings.append(SkaterConnectedMesh.limb_ring(b, frames[1], 0.0, _ELBOW_RADIUS_M, _ELBOW_PAD_M,
			elbow_bind, elbow_bind, 1.0))
	axes.append(frames[1])
	vs.append(_upper_v(KeeperAnatomy.UPPER_ARM_M))
	for r: Vector3 in _FORE_RINGS:
		var frame: Transform3D = SkaterConnectedMesh.round_elbow(frames, 1.0 - r.z * 0.5)
		rings.append(SkaterConnectedMesh.limb_ring(b, frame, r.x, r.y, _ELBOW_PAD_M * r.z,
				fore_bind, elbow_bind, r.z))
		axes.append(frame)
		vs.append(_fore_v(r.x))

	# Between the seam and the arm's first ring, a ring halfway along the line
	# joining them, wholly on the shoulder's middle, so the turn between the
	# chest and the arm bends over two bands, not one.
	var seam: PackedInt32Array = b.aligned(hole, rings[0])
	var between := PackedInt32Array()
	for m: int in SkaterConnectedMesh.LIMB_SIDES:
		between.append(b.vertex(b.position(seam[m]).lerp(b.position(rings[0][m]), 0.5),
				[shoulder_bind], [1.0]))
	var uv: Callable = func(p: Vector3) -> Vector2:
		return Vector2(_sleeve_u(p, upper, sx),
				_upper_v(maxf((p - shoulder).dot(upper.basis.y), 0.0)))
	b.join(seam, between, ZONE_SLEEVE, uv, (b.centroid(seam) + b.centroid(between)) * 0.5)
	b.join(between, rings[0], ZONE_SLEEVE, uv, (b.centroid(between) + b.centroid(rings[0])) * 0.5)
	var n: int = SkaterConnectedMesh.LIMB_SIDES
	for i: int in rings.size() - 1:
		var inside: Vector3 = (b.centroid(rings[i]) + b.centroid(rings[i + 1])) * 0.5
		for m: int in n:
			var m1: int = (m + 1) % n
			var corners: Array[int] = [rings[i][m], rings[i][m1], rings[i + 1][m1], rings[i + 1][m]]
			var uvs: Array[Vector2] = []
			for c: int in 4:
				var ring: int = i if c < 2 else i + 1
				uvs.append(Vector2(_sleeve_u(b.position(corners[c]), axes[ring], sx), vs[ring]))
			b.quad(corners[0], corners[1], corners[2], corners[3], uvs[0], uvs[1], uvs[2], uvs[3],
					ZONE_SLEEVE, inside, true)
	var tip: int = b.vertex(fore * Vector3(0.0, _FORE_END_M, 0.0), [fore_bind], [1.0])
	var end: PackedInt32Array = rings[rings.size() - 1]
	var end_v: float = vs[vs.size() - 1]
	for m: int in n:
		b.tri(tip, end[m], end[(m + 1) % n], Vector2(0.5, end_v), Vector2(float(m) / n, end_v),
				Vector2(float(m + 1) / n, end_v), ZONE_SLEEVE,
				fore * Vector3(0.0, _FORE_END_M - 0.05, 0.0))


# The sleeve's V (SleevePaint's share of it) `s` down the upper arm from the
# shoulder joint, or down the forearm from the elbow: the elbow where the
# skater's is down the paint, and the cuff's top at its end.
static func _upper_v(s: float) -> float:
	return SleevePaint.pos_of(s * SleevePaint.ELBOW_M / KeeperAnatomy.UPPER_ARM_M)


static func _fore_v(s: float) -> float:
	return SleevePaint.pos_of(SleevePaint.ELBOW_M + s * (SleevePaint.LENGTH_M - SleevePaint.ELBOW_M)
			/ (KeeperAnatomy.FOREARM_M - KeeperGearMeshes.GLOVE_CUFF_TOP_M))


# U round the sleeve about `frame`'s Y: 0.5 (where SleeveDecal sets the number)
# straight out from him, rising toward his front on the +X arm and his back on
# the −X one, so seen from beside either arm it runs left to right.
static func _sleeve_u(p: Vector3, frame: Transform3D, sx: float) -> float:
	var axis: Vector3 = frame.basis.y.normalized()
	var d: Vector3 = p - frame.origin
	var out: Vector3 = (Vector3(sx, 0.0, 0.0) - axis * (axis.x * sx)).normalized()
	var right: Vector3 = axis.cross(out)
	if right.z * sx > 0.0:
		right = -right
	return fposmod(0.5 + atan2(d.dot(right), d.dot(out)) / TAU, 1.0)
