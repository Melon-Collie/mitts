class_name SkaterConnectedPants
extends RefCounted

# PROTOTYPE: the connected body's pants and legs (SkaterConnectedMesh builds the
# rest and owns the binds): the waist and seat round both hips, splitting at the
# crotch into the legs, each on through the hem and the knee into the sock.

# The pants, waist-space (the PELVIS bone's, which rests at bind identity):
# (y, half width, half depth, rear sway). The top four are round and scaled like
# the rig's pelvis lathe, which the jersey tucks into
# (SkaterMeshBuilder._PELVIS_PROFILE: the third value is unused, the width is
# the radius): its lip and waistband, the belt under them and its waist; below
# them the hips widen over the hip joints to the seat, and the last ring is the
# crotch, where the legs split.
const _PANTS: Array[Vector4] = [
	Vector4(0.056, 0.184, 0.0, 0.006),
	Vector4(0.050, 0.186, 0.0, 0.006),
	Vector4(0.030, 0.187, 0.0, 0.007),
	Vector4(0.000, 0.190, 0.0, 0.010),
	Vector4(-0.040, 0.214, 0.176, 0.013),
	Vector4(-0.080, 0.240, 0.183, 0.020),
	Vector4(-0.120, 0.258, 0.188, 0.028),   # the seat, over the hip joints
	Vector4(-0.160, 0.266, 0.184, 0.022),
	Vector4(-0.200, 0.268, 0.176, 0.012),   # the crotch
]
const _PANTS_ROUND: int = 4
# Where the jersey is tucked in, the pants' padded top stands up as a rim: the
# lip rises this far and out to just inside the jersey going in over it (no
# well between them), the waistband under it this far and out this far,
# rolling back in to the belt, so the rim is a padded band proud of the jersey
# going in behind it. Above it the jersey blouses out by TUCK_BLOUSE_M, wider than the
# rim, so it overhangs the rim before it goes in (test_connected_body.gd).
const _RIM_LIP_RISE_M: float = 0.045
const _RIM_LIP_FLARE_M: float = 0.026
const _RIM_RISE_M: float = 0.022
const _RIM_FLARE_M: float = 0.035
const TUCK_BLOUSE_M: float = 0.030
# How far tucked a column is before the rim under it starts to flare.
const _RIM_FLARE_FROM: float = 0.6
const _LOOSE_TOP_INSET_M: float = 0.015
# The kidney pads, each side of the spine under the belt: how far each ring
# stands out at their middles, 45° off the back, easing to none at the spine
# and the hips. They stand only where the jersey is tucked, as the rim does:
# under a loose jersey they would show only where they poked through it.
const _KIDNEY_M: Array[float] = [0.0, 0.0, 0.006, 0.016, 0.020, 0.010, 0.0, 0.0, 0.0]
# How far each ring rides its side's thigh rather than the pelvis: (at the
# middle, more out at the side by |sin θ|). Over the hips the pants start to go
# with the legs, most at the crotch.
const _THIGH_SHARE: Array[Vector2] = [
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2(0.0, 0.1), Vector2(0.0, 0.3), Vector2(0.0, 0.5), Vector2(0.35, 0.35),
]
# The thigh as the tail collides with it: round its hip's axis far enough to
# hold the pants' front at the crotch, which rides the thigh up into the tail
# in a crouch.
const COLLIDER_THIGH_RADIUS_M: float = 0.18
const _SIDES: int = 16
const _FRONT: int = 8   # the front centre of a ring, which runs from the back centre
# The inseam, front to back, at the bottom of the crotch's V: each on the pelvis
# and both thighs.
const _INSEAM: Array[Vector3] = [
	Vector3(0.0, -0.250, -0.060), Vector3(0.0, -0.262, 0.005), Vector3(0.0, -0.250, 0.070),
]

# Each leg below the crotch, bind space: (y, radius, its swell to the outside,
# its swell to the back), with the knee guard's cap through the sock, the calf,
# and the ring's blend over (thigh, knee, sock). The breezers flare a little to
# their hem, which turns in under itself to the sock; the sock runs over the
# shin guard's cap, down the calf and into the skate's collar. The knee folds
# over five rings so its turn is spread rather than taken at one.
const _LEG_RINGS: Array[Vector4] = [
	Vector4(-0.290, 0.128, 0.024, 0.006),
	Vector4(-0.320, 0.130, 0.023, 0.005),
	Vector4(-0.355, 0.133, 0.021, 0.003),
	Vector4(-0.395, 0.138, 0.018, 0.0),    # the pants' hem
	Vector4(-0.402, 0.104, 0.0, 0.0),      # under it, the sock's top
	Vector4(-0.418, 0.102, 0.0, 0.0),
	Vector4(-0.430, 0.101, 0.0, 0.0),
	Vector4(-0.440, 0.100, 0.0, 0.0),      # the knee
	Vector4(-0.455, 0.098, 0.0, 0.0),
	Vector4(-0.475, 0.097, 0.0, 0.0),
	Vector4(-0.510, 0.095, 0.0, 0.0),
	Vector4(-0.550, 0.093, 0.0, 0.0),
	Vector4(-0.600, 0.091, 0.0, 0.0),
	Vector4(-0.650, 0.088, 0.0, 0.0),
	Vector4(-0.700, 0.084, 0.0, 0.0),
	Vector4(-0.745, 0.080, 0.0, 0.0),
	Vector4(-0.780, 0.076, 0.0, 0.0),
]
const _KNEE_CAP: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.0, 0.006, 0.016, 0.024, 0.020, 0.012, 0.004, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const _CALF: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.004, 0.008, 0.007, 0.004, 0.0, 0.0, 0.0]
const _LEG_BLEND: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0),
	Vector3(0.7, 0.3, 0.0), Vector3(0.35, 0.65, 0.0), Vector3(0, 1, 0),
	Vector3(0.0, 0.6, 0.4), Vector3(0.0, 0.3, 0.7),
	Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
	Vector3(0, 0, 1), Vector3(0, 0, 1),
]
# The first sock ring: the hem's underside above it is the pants'.
const _FIRST_SOCK_RING: int = 5
const _KNEE_ZONE_CAP_M: float = 0.012
# Where the old sock lathe's top was: the sock's stripes are laid from there.
const _SOCK_TOP_Y_M: float = -0.48
const _SOCK_SIDE_M: float = 0.30

const _LegSurface = SkaterMeshBuilder.LegSurface


static func build(b: ConnectedSkinBuilder, tuck: int) -> void:
	var bind_pelvis: int = SkaterConnectedMesh.Bind.PELVIS
	var bind_thigh := PackedInt32Array([SkaterConnectedMesh.Bind.THIGH_L,
			SkaterConnectedMesh.Bind.THIGH_R])
	var xz: Vector2 = SkaterMeshBuilder.PELVIS_XZ_SCALE
	var rings: Array[PackedInt32Array] = []
	for i: int in _PANTS.size():
		var s: Vector4 = _PANTS[i]
		var half_w: float = s.y * xz.x if i < _PANTS_ROUND else s.y
		var half_d: float = s.y * xz.y if i < _PANTS_ROUND else s.z
		var pts := PackedVector3Array()
		for k: int in _SIDES + 1:
			var theta: float = TAU * float(k) / float(_SIDES)
			var kidney: float = 0.0
			if cos(theta) > 0.0:
				kidney = _KIDNEY_M[i] * sin(2.0 * theta) ** 2 * smoothstep(_RIM_FLARE_FROM, 1.0,
						SkaterJerseyHem.tuck_share(tuck, theta))
			pts.append(Vector3(sin(theta) * (half_w + kidney), s.x,
					s.w + cos(theta) * (half_d + kidney)))
		if i < 2:
			_stand_rim(pts, s, tuck, _RIM_LIP_RISE_M if i == 0 else _RIM_RISE_M,
					_RIM_LIP_FLARE_M if i == 0 else _RIM_FLARE_M)
		var ids := PackedInt32Array()
		for k: int in _SIDES:
			var across: float = absf(sin(TAU * float(k) / float(_SIDES)))
			var share: float = _THIGH_SHARE[i].x + _THIGH_SHARE[i].y * across
			if share <= 0.0:
				ids.append(b.vertex(pts[k], [bind_pelvis], [1.0]))
			elif across < 1e-4:
				ids.append(b.vertex(pts[k], [bind_pelvis, bind_thigh[0], bind_thigh[1]],
						[1.0 - share, share * 0.5, share * 0.5]))
			else:
				ids.append(b.vertex(pts[k], [bind_pelvis, bind_thigh[1 if k < _FRONT else 0]],
						[1.0 - share, share]))
		rings.append(ids)
	for i: int in rings.size() - 1:
		var inside := Vector3(0.0, (_PANTS[i].x + _PANTS[i + 1].x) * 0.5, 0.0)
		for k: int in _SIDES:
			var k1: int = (k + 1) % _SIDES
			var ids: Array[int] = [rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]]
			var side: float = 1.0 if b.position(ids[0]).x + b.position(ids[1]).x > 0.0 else -1.0
			var zone: int = _LegSurface.THIGH_R if side > 0.0 else _LegSurface.THIGH_L
			b.quad(ids[0], ids[1], ids[2], ids[3], _pants_uv(side, b.position(ids[0])),
					_pants_uv(side, b.position(ids[1])), _pants_uv(side, b.position(ids[2])),
					_pants_uv(side, b.position(ids[3])), zone, inside, true)
	var waist: int = b.vertex(Vector3(0.0, _PANTS[0].x, _PANTS[0].w), [bind_pelvis], [1.0])
	SkaterConnectedMesh.fan(b, rings[0], waist, Vector2(0.25, 0.75),
			SkaterConnectedMesh.zone(SkaterMeshBuilder.UpperSurface.PELVIS),
			Vector3(0.0, _PANTS[0].x - 0.1, 0.0))

	var crotch: PackedInt32Array = rings[rings.size() - 1]
	var inseam := PackedInt32Array()
	for p: Vector3 in _INSEAM:
		inseam.append(b.vertex(p, [bind_pelvis, bind_thigh[0], bind_thigh[1]], [0.5, 0.25, 0.25]))
	for side: float in [-1.0, 1.0]:
		# Round the leg from the back centre: its half of the crotch ring, the
		# front centre, then the inseam back up the middle.
		var top := PackedInt32Array([crotch[0]])
		for j: int in range(1, _FRONT):
			top.append(crotch[j] if side > 0.0 else crotch[_SIDES - j])
		top.append(crotch[_FRONT])
		top.append_array(inseam)
		_build_leg(b, side, top)


# The pants as the jersey's tail collides with them (SkaterHemColliders):
# (y, radius, rear sway) per ring, waist-space, a lathe at PELVIS_XZ_SCALE wide
# enough to hold each ring, kidney pads and all. The legs below the crotch are
# the thigh capsules', COLLIDER_THIGH_RADIUS_M round.
static func collider_stations() -> PackedFloat64Array:
	var xz: Vector2 = SkaterMeshBuilder.PELVIS_XZ_SCALE
	var out := PackedFloat64Array()
	for i: int in _PANTS.size():
		var s: Vector4 = _PANTS[i]
		var r: float = s.y if i < _PANTS_ROUND \
				else maxf(s.y / xz.x, (s.z + _KIDNEY_M[i]) / xz.y)
		out.append_array([s.x, r, s.w])
	return out


# A rim ring (`s`, as _PANTS) stood up where `tuck` takes the jersey in: risen
# as far in as the jersey is, so the rim eases up toward a tucked corner rather
# than standing in a spike at it, and flared only where the jersey is all but
# tucked — a loose hem lifted toward the belt still hangs outside the flare.
# Where the jersey is loose it is drawn in instead: no one sees it there, and a
# fold that pulls the jersey's back taut over the seat would push it through.
static func _stand_rim(pts: PackedVector3Array, s: Vector4, tuck: int, rise: float,
		flare: float) -> void:
	var xz: Vector2 = SkaterMeshBuilder.PELVIS_XZ_SCALE
	for k: int in pts.size():
		var theta: float = TAU * float(k) / float(_SIDES)
		var t: float = SkaterJerseyHem.tuck_share(tuck, theta)
		var stood: float = smoothstep(_RIM_FLARE_FROM, 1.0, t)
		var r: float = s.y + flare * stood - _LOOSE_TOP_INSET_M * (1.0 - stood)
		pts[k] = Vector3(sin(theta) * r * xz.x, s.x + rise * t, s.w + cos(theta) * r * xz.y)


# The pants' stripe column is laid round each leg (U from +Z toward +X about the
# leg's axis, as the rig's thighs were) so it runs up over the hip to the waist.
static func _pants_uv(side: float, p: Vector3) -> Vector2:
	var axis: Vector3 = SkaterConnectedMesh.hip(side)
	return Vector2(fposmod(atan2(p.x - axis.x, p.z - axis.z) / TAU, 1.0), 0.25)


# One leg below the crotch, from its top loop (`top`, a leg ring's count of
# vertices round the leg: the crotch ring's half and the inseam).
static func _build_leg(b: ConnectedSkinBuilder, side: float, top: PackedInt32Array) -> void:
	var left: bool = side < 0.0
	var binds := PackedInt32Array([
		SkaterConnectedMesh.Bind.THIGH_L if left else SkaterConnectedMesh.Bind.THIGH_R,
		SkaterConnectedMesh.Bind.KNEE_L if left else SkaterConnectedMesh.Bind.KNEE_R,
		SkaterConnectedMesh.Bind.SOCK_L if left else SkaterConnectedMesh.Bind.SOCK_R,
	])
	var thigh_zone: int = _LegSurface.THIGH_L if left else _LegSurface.THIGH_R
	var sock_zone: int = _LegSurface.SOCK_L if left else _LegSurface.SOCK_R
	var knee_zone: int = _LegSurface.KNEE_L if left else _LegSurface.KNEE_R
	var sides: int = SkaterConnectedMesh.LIMB_SIDES
	var axis: Vector3 = SkaterConnectedMesh.hip(side)
	# The top loop's azimuths about the leg, mirrored so +φ is outward on both
	# sides, unwrapped to run one way round; the rings below ease them to even.
	var top_phi := PackedFloat32Array()
	for id: int in top:
		var d: Vector3 = b.position(id) - axis
		var phi: float = atan2(d.x * side, d.z)
		if not top_phi.is_empty():
			phi = top_phi[top_phi.size() - 1] + wrapf(phi - top_phi[top_phi.size() - 1], -PI, PI)
		top_phi.append(phi)
	var step: float = signf(top_phi[top_phi.size() - 1] - top_phi[0]) * TAU / float(sides)
	var offset: float = 0.0
	for j: int in sides:
		offset += (top_phi[j] - step * float(j)) / float(sides)
	var rings: Array[PackedInt32Array] = [top]
	for i: int in _LEG_RINGS.size():
		var s: Vector4 = _LEG_RINGS[i]
		var even: float = 0.65 if i == 0 else 1.0
		var blend: Vector3 = _LEG_BLEND[i]
		var ring_binds: Array = []
		var ring_weights: Array = []
		for c: int in 3:
			if blend[c] > 0.0:
				ring_binds.append(binds[c])
				ring_weights.append(blend[c])
		var ids := PackedInt32Array()
		for j: int in sides:
			var phi: float = lerpf(top_phi[j], offset + step * float(j), even)
			var r: float = s.y + s.z * sin(phi) + s.w * cos(phi) \
					+ _KNEE_CAP[i] * maxf(-cos(phi), 0.0) ** 3 + _CALF[i] * maxf(cos(phi), 0.0) ** 2
			ids.append(b.vertex(Vector3(axis.x + side * sin(phi) * r, s.x, cos(phi) * r),
					ring_binds, ring_weights))
		rings.append(ids)
	for i: int in rings.size() - 1:
		var y_mid: float = (b.centroid(rings[i]).y + b.centroid(rings[i + 1]).y) * 0.5
		var inside := Vector3(axis.x, y_mid, 0.0)
		# Band i runs from leg ring i − 1 (the top loop for i = 0) to leg ring i.
		var sock: bool = i >= _FIRST_SOCK_RING
		var knee: bool = sock and maxf(_KNEE_CAP[i], _KNEE_CAP[i - 1]) >= _KNEE_ZONE_CAP_M
		for j: int in sides:
			var j1: int = (j + 1) % sides
			var ids: Array[int] = [rings[i][j], rings[i][j1], rings[i + 1][j1], rings[i + 1][j]]
			var uvs: Array[Vector2] = []
			for id: int in ids:
				var p: Vector3 = b.position(id)
				var u: float = fposmod(atan2(p.x - axis.x, p.z - axis.z) / TAU, 1.0)
				var v: float = 0.25
				if sock:
					v = 0.5 * clampf((_SOCK_TOP_Y_M - p.y) / _SOCK_SIDE_M, 0.0, 1.0)
				uvs.append(Vector2(u, v))
			var zone: int = sock_zone if sock else thigh_zone
			if knee:
				var front: float = -(b.position(ids[0]) + b.position(ids[1])
						- Vector3(axis.x, 0.0, 0.0) * 2.0).normalized().z
				if front > 0.5:
					zone = knee_zone
			b.quad(ids[0], ids[1], ids[2], ids[3], uvs[0], uvs[1], uvs[2], uvs[3],
					zone, inside, true)
	var last: PackedInt32Array = rings[rings.size() - 1]
	var bottom_y: float = _LEG_RINGS[_LEG_RINGS.size() - 1].x
	var foot: int = b.vertex(Vector3(axis.x, bottom_y, 0.0), [binds[2]], [1.0])
	for j: int in sides:
		b.tri(foot, last[j], last[(j + 1) % sides], Vector2(0.75, 0.75),
				Vector2(0.75, 0.75), Vector2(0.75, 0.75), sock_zone,
				Vector3(axis.x, bottom_y + 0.1, 0.0))
