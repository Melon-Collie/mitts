class_name SkateUpperMesh
extends RefCounted

# The skate's upper as ONE closed shell: the cuff round the sock, the heel, the
# quarter and the toe cap, lofted through a run of cut planes so every paint
# zone shares its edge loop with the next. The blade (SkaterMeshBuilder's holder
# and runner) bolts on under the sole as its own part, as in life.
#
# Frame: the SKATE bone's (x lateral, y up, −z toward the toe), origin on the
# leg's axis. The cuff rides that bone and the foot the FOOT bone, blended
# through the ankle (foot_share), so the ankle's give-back flexes the boot
# rather than parting it.
#
# The shell is a loop per cut line of the side outline: level round the cuff,
# fanned about a line in front of the instep's crease through the ankle, and
# upright along the foot. Lines that never cross inside the outline give loops
# that never cross, so the loft cannot fold.

enum Surface { COLLAR, STRIPE, QUARTER, TOE, LACES, TONGUE }

# The FOOT bone's rest frame in the SKATE bone's (both hang from the shin in
# Scenes/Skater.tscn): toe along the foot's −Y, its +Z down.
# test_skate_upper.gd holds it against the scene.
const SKATE_FROM_FOOT := Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, -1.0, 0.0)),
		Vector3(0.0, -0.04, -0.10))

const POINTS: int = 12

# The side outline, (z, y), round from the top of the tongue down the front to
# the toe, back along the sole and up the heel. The sole is the holder's seat
# (its towers' tops at y −0.082 sink into it), and the cuff clears the sock
# (SkaterConnectedPants) where it goes in; test_skate_upper.gd holds both. The
# cuff is no taller or deeper than this: a downed skater's folded leg rests on
# its back rim (SkaterLegRig's rest on the ice), and a taller one drives it
# into the ice (test_knockdown_lies_on_the_ice.gd).
const _OUTLINE: Array[Vector2] = [
	Vector2(-0.100, 0.106),   # tongue
	Vector2(-0.097, 0.080),
	Vector2(-0.100, 0.050),
	Vector2(-0.112, 0.026),   # into the instep
	Vector2(-0.135, 0.010),
	Vector2(-0.165, -0.004),  # toe cap
	Vector2(-0.195, -0.016),
	Vector2(-0.215, -0.032),
	Vector2(-0.226, -0.052),
	Vector2(-0.222, -0.072),
	Vector2(-0.205, -0.086),
	Vector2(0.030, -0.088),   # sole
	Vector2(0.052, -0.080),   # heel
	Vector2(0.066, -0.060),
	Vector2(0.072, -0.030),
	Vector2(0.070, 0.005),    # Achilles pocket
	Vector2(0.080, 0.045),
	Vector2(0.087, 0.075),
	Vector2(0.093, 0.106),    # tendon guard
]

# The line the ankle's cut planes fan about, (z, y): in front of the crease,
# outside the shell.
const _FAN_PIVOT := Vector2(-0.14, 0.018)

enum Cut { LEVEL, FAN, UPRIGHT }

# One loop per cut, top to toe: (kind, its height / fan angle in degrees / its
# z, half-width at the far end, the near end's share of that width). Near is
# the tongue or the top of the foot, far the back or the sole.
const _CUTS: Array[Vector4] = [
	Vector4(Cut.LEVEL, 0.100, 0.095, 0.95),
	Vector4(Cut.LEVEL, 0.080, 0.093, 0.94),
	Vector4(Cut.LEVEL, 0.055, 0.090, 0.92),
	Vector4(Cut.LEVEL, 0.022, 0.082, 0.86),
	Vector4(Cut.FAN, 22.0, 0.074, 0.80),
	Vector4(Cut.FAN, 38.0, 0.070, 0.76),
	Vector4(Cut.FAN, 55.0, 0.066, 0.73),
	Vector4(Cut.FAN, 73.0, 0.065, 0.72),
	Vector4(Cut.UPRIGHT, -0.140, 0.064, 0.70),
	Vector4(Cut.UPRIGHT, -0.165, 0.062, 0.70),
	Vector4(Cut.UPRIGHT, -0.190, 0.056, 0.72),
	Vector4(Cut.UPRIGHT, -0.208, 0.048, 0.74),
	Vector4(Cut.UPRIGHT, -0.220, 0.036, 0.78),
]
# The band below cut i is this zone. The stripe rings the ankle between the
# third and fourth cuts; the toe cap is the foot's front 8 cm, from the ninth.
const _BAND_ZONE: Array[Surface] = [
	Surface.COLLAR, Surface.COLLAR, Surface.STRIPE, Surface.QUARTER, Surface.QUARTER,
	Surface.QUARTER, Surface.QUARTER, Surface.QUARTER, Surface.TOE, Surface.TOE, Surface.TOE,
	Surface.TOE,
]

# Squareness of a loop (superellipse exponent): the near half flat enough for
# the laces to lie on, the far half round at the cuff and boxy along the foot.
const _NEAR_EXPONENT: float = 4.0
const _CUFF_FAR_EXPONENT: float = 2.2
const _FOOT_FAR_EXPONENT: float = 3.5
# Along the foot the sole is flat: the far end's points within this share of
# the half-depth are pressed onto it.
const _SOLE_FLAT: float = 0.15

# The tendon guard: the rim's back point raised this far and leaned back by
# _GUARD_LEAN of it, its neighbours by the falloff (cos of their angle off the
# back, to this power).
const _GUARD_RISE_M: float = 0.03
const _GUARD_LEAN: float = 0.3
const _GUARD_FALLOFF: float = 6.0

# The tongue: a padded flap rising out of the front of the boot over the sock,
# on the leg's axis. Stations bottom to top (y, inner radius, thickness, half
# its arc round the leg in degrees); the bottom one is hidden in the boot. Its
# top leans forward off the shin by _TONGUE_LEAN_M.
const _TONGUE_STATIONS: Array[Vector4] = [
	Vector4(0.050, 0.086, 0.008, 55.0),
	Vector4(0.100, 0.087, 0.010, 52.0),
	Vector4(0.130, 0.089, 0.011, 46.0),
	Vector4(0.152, 0.091, 0.010, 38.0),
	Vector4(0.163, 0.093, 0.007, 24.0),
]
const _TONGUE_LEAN_M: float = 0.006
const _TONGUE_ARC_POINTS: int = 7

# The padded rim: the top loop turned in over the lining, down this far.
const _RIM_INSET: float = 0.86
const _RIM_DROP_M: float = 0.008

# The ankle's blend, by height in this frame: all foot at the bottom, all leg at
# the top. The sock goes in above it.
const _ANKLE_LOW_Y: float = -0.005
const _ANKLE_HIGH_Y: float = 0.055

# Laces: rungs across the front from the toe cap's edge up the tongue, spaced
# along the front's line, each a bar this wide, this long along the line, this
# proud of the surface and sunk this far into it.
const _LACE_FROM_Z: float = -0.160
const _LACE_TO_Y: float = 0.085
const _LACE_RUNGS: int = 5
const _LACE_HALF_W: float = 0.026
const _LACE_HALF_T: float = 0.0055
const _LACE_PROUD: float = 0.006
const _LACE_SINK: float = 0.006
const _LACE_COLOR := Color(0.88, 0.88, 0.86)
const _STRIPE_COLOR := Color(0.08, 0.08, 0.08)

static var _mesh: ArrayMesh = null


static func shared() -> ArrayMesh:
	if _mesh == null:
		_mesh = _build()
	return _mesh


# How much of a point (this frame) rides the FOOT bone; the rest rides the
# SKATE bone.
static func foot_share(p: Vector3) -> float:
	return 1.0 - smoothstep(_ANKLE_LOW_Y, _ANKLE_HIGH_Y, p.y)


# The shell's loops, top to toe, POINTS each, starting at the near end's middle.
static func loops() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for cut: Vector4 in _CUTS:
		out.append(_loop(cut))
	return out


static func _build() -> ArrayMesh:
	var cut_loops: Array[PackedVector3Array] = loops()
	cut_loops[0] = _with_tendon_guard(cut_loops[0])
	var top: PackedVector3Array = cut_loops[0]
	var top_center: Vector3 = _center(top)
	var rim := PackedVector3Array()
	for p: Vector3 in top:
		rim.append(top_center + (p - top_center) * _RIM_INSET + Vector3.DOWN * _RIM_DROP_M)
	var tools: Array[SurfaceTool] = []
	for s: int in Surface.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)  # flat shading, as SkaterMeshBuilder's parts
		tools.append(st)
	var collar: SurfaceTool = tools[Surface.COLLAR]
	_cap(collar, rim, _center(rim), true)
	_band(collar, rim, top)
	for i: int in cut_loops.size() - 1:
		_band(tools[_BAND_ZONE[i]], cut_loops[i], cut_loops[i + 1])
	var toe: PackedVector3Array = cut_loops[cut_loops.size() - 1]
	_cap(tools[Surface.TOE], toe, _center(toe), false)
	_add_laces(tools[Surface.LACES], cut_loops)
	_add_tongue(tools[Surface.TONGUE])
	var m := ArrayMesh.new()
	for st: SurfaceTool in tools:
		st.generate_normals()
		st.commit(m)
	m.surface_set_material(Surface.STRIPE, _material(_STRIPE_COLOR, 0.42))
	m.surface_set_material(Surface.LACES, _material(_LACE_COLOR, 0.9))
	return m


static func _with_tendon_guard(top: PackedVector3Array) -> PackedVector3Array:
	var out := top.duplicate()
	for k: int in POINTS:
		var off_back: float = TAU * float(k) / float(POINTS) - PI
		var rise: float = _GUARD_RISE_M * pow(maxf(cos(off_back), 0.0), _GUARD_FALLOFF)
		out[k] += Vector3(0.0, rise, rise * _GUARD_LEAN)
	return out


# The tongue's cross-section at each station is an arc band round the front of
# the leg: its outer arc across, then its inner arc back. Swept station to
# station, closed across each end.
static func _add_tongue(st: SurfaceTool) -> void:
	var sections: Array[PackedVector3Array] = []
	var y0: float = _TONGUE_STATIONS[1].x
	var y1: float = _TONGUE_STATIONS[_TONGUE_STATIONS.size() - 1].x
	for station: Vector4 in _TONGUE_STATIONS:
		var lean: float = -_TONGUE_LEAN_M * smoothstep(y0, y1, station.x)
		var half: float = deg_to_rad(station.w)
		var section := PackedVector3Array()
		for side: int in 2:
			var r: float = station.y + station.z if side == 0 else station.y
			for j: int in _TONGUE_ARC_POINTS:
				var t: float = float(j) / float(_TONGUE_ARC_POINTS - 1)
				var phi: float = lerpf(-half, half, t if side == 0 else 1.0 - t)
				section.append(Vector3(sin(phi) * r, station.x, -cos(phi) * r + lean))
		sections.append(section)
	for i: int in sections.size() - 1:
		_band(st, sections[i + 1], sections[i])
	_close_band(st, sections[0], true)
	_close_band(st, sections[sections.size() - 1], false)


# Closes an arc-band section (outer arc, then inner arc back) with the strip
# across it, facing down the sweep at its start or up it at its end.
static func _close_band(st: SurfaceTool, section: PackedVector3Array, start: bool) -> void:
	var n: int = _TONGUE_ARC_POINTS
	for j: int in n - 1:
		var a: Vector3 = section[j]
		var b: Vector3 = section[j + 1]
		var c: Vector3 = section[2 * n - 2 - j]
		var d: Vector3 = section[2 * n - 1 - j]
		if start:
			_tri(st, a, b, c)
			_tri(st, a, c, d)
		else:
			_tri(st, a, c, b)
			_tri(st, a, d, c)


# A cut's line in the side view: a point on it and its direction from the near
# end to the far, both (z, y).
static func _line(cut: Vector4) -> Array[Vector2]:
	match int(cut.x):
		Cut.LEVEL:
			return [Vector2(0.0, cut.y), Vector2(1.0, 0.0)]
		Cut.FAN:
			var a: float = deg_to_rad(cut.y)
			return [_FAN_PIVOT, Vector2(cos(a), -sin(a))]
	return [Vector2(cut.y, 0.0), Vector2(0.0, -1.0)]


static func _loop(cut: Vector4) -> PackedVector3Array:
	var line: Array[Vector2] = _line(cut)
	var span: Vector2 = _crossing(line[0], line[1])
	var near: Vector2 = line[0] + line[1] * span.x
	var mid: Vector2 = line[0] + line[1] * (span.x + span.y) * 0.5
	var half_depth: float = (span.y - span.x) * 0.5
	var dir := Vector3(0.0, line[1].y, line[1].x)
	var centre := Vector3(0.0, mid.y, mid.x)
	var upright: bool = int(cut.x) == Cut.UPRIGHT
	var far_exponent: float = _FOOT_FAR_EXPONENT if int(cut.x) != Cut.LEVEL else _CUFF_FAR_EXPONENT
	var pts := PackedVector3Array()
	for k: int in POINTS:
		var theta: float = TAU * float(k) / float(POINTS)
		var c: float = -cos(theta)   # −1 at the near end, +1 at the far
		var s: float = sin(theta)
		var e: float = _NEAR_EXPONENT if c < 0.0 else far_exponent
		var along: float = signf(c) * pow(absf(c), 2.0 / e)
		var lat: float = signf(s) * pow(absf(s), 2.0 / e)
		if upright and along > 0.0:
			along = minf(along * (1.0 + _SOLE_FLAT), 1.0)
		var width: float = cut.z * lerpf(cut.w, 1.0, (along + 1.0) * 0.5)
		pts.append(centre + dir * along * half_depth + Vector3.RIGHT * lat * width)
	assert(pts[0].distance_to(Vector3(0.0, near.y, near.x)) < 1e-4)
	return pts


# Where the line enters and leaves the outline: its nearest and farthest
# crossings, as distances along it.
static func _crossing(origin: Vector2, dir: Vector2) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	var n: int = _OUTLINE.size()
	for i: int in n:
		var a: Vector2 = _OUTLINE[i]
		var b: Vector2 = _OUTLINE[(i + 1) % n]
		var edge: Vector2 = b - a
		var denom: float = dir.cross(edge)
		if absf(denom) < 1e-9:
			continue
		var t: float = (a - origin).cross(edge) / denom
		var u: float = (a - origin).cross(dir) / denom
		if u >= 0.0 and u <= 1.0:
			lo = minf(lo, t)
			hi = maxf(hi, t)
	return Vector2(lo, hi)


static func _center(loop: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p: Vector3 in loop:
		sum += p
	return sum / float(loop.size())


# The quads between two loops, each wound outward.
static func _band(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array) -> void:
	for k: int in a.size():
		var k1: int = (k + 1) % a.size()
		_tri(st, a[k], b[k1], a[k1])
		_tri(st, a[k], b[k], b[k1])


static func _cap(st: SurfaceTool, loop: PackedVector3Array, center: Vector3, start: bool) -> void:
	for k: int in loop.size():
		var k1: int = (k + 1) % loop.size()
		if start:
			_tri(st, center, loop[k], loop[k1])
		else:
			_tri(st, center, loop[k1], loop[k])


# The rungs, spaced evenly along the front's line (the loops' near points) from
# the toe cap's edge to the tongue's top, each a bar lying on the line there.
static func _add_laces(st: SurfaceTool, cut_loops: Array[PackedVector3Array]) -> void:
	var front := PackedVector3Array()
	for i: int in range(cut_loops.size() - 1, -1, -1):
		front.append(cut_loops[i][0])
	var lengths := PackedFloat32Array([0.0])
	for i: int in range(1, front.size()):
		lengths.append(lengths[i - 1] + front[i].distance_to(front[i - 1]))
	var from: float = _arc_at(front, lengths, func(p: Vector3) -> bool: return p.z > _LACE_FROM_Z)
	var to: float = _arc_at(front, lengths, func(p: Vector3) -> bool: return p.y > _LACE_TO_Y)
	for r: int in _LACE_RUNGS:
		var at: float = lerpf(from, to, (float(r) + 0.5) / float(_LACE_RUNGS))
		var i: int = 1
		while i < front.size() - 1 and lengths[i] < at:
			i += 1
		var seg: Vector3 = front[i] - front[i - 1]
		var tangent: Vector3 = seg.normalized()
		var p: Vector3 = front[i - 1] + seg * ((at - lengths[i - 1]) / seg.length())
		# Out of the shell: the front line runs toe → tongue, so its normal turns
		# from it toward the toe and up.
		var normal := Vector3(0.0, tangent.z, -tangent.y)
		_bar(st, p, Vector3.RIGHT * _LACE_HALF_W, tangent * _LACE_HALF_T, normal)


# The arc length along `front` where `past` first holds, interpolated.
static func _arc_at(front: PackedVector3Array, lengths: PackedFloat32Array,
		past: Callable) -> float:
	for i: int in range(1, front.size()):
		if past.call(front[i]):
			var a: Vector3 = front[i - 1]
			var b: Vector3 = front[i]
			var lo: float = 0.0
			var hi: float = 1.0
			for _step: int in 20:
				var mid: float = (lo + hi) * 0.5
				if past.call(a.lerp(b, mid)):
					hi = mid
				else:
					lo = mid
			return lerpf(lengths[i - 1], lengths[i], hi)
	return lengths[lengths.size() - 1]


# A box on `centre`: ±`across`, ±`along`, and from `_LACE_SINK` under to
# `_LACE_PROUD` over the surface along `normal`.
static func _bar(st: SurfaceTool, centre: Vector3, across: Vector3, along: Vector3,
		normal: Vector3) -> void:
	var corners := PackedVector3Array()
	for c: int in 8:
		corners.append(centre + across * (1.0 if c & 1 else -1.0)
				+ along * (1.0 if c & 2 else -1.0)
				+ normal * (_LACE_PROUD if c & 4 else -_LACE_SINK))
	# Each face as four corner indices, wound as the shell's faces are.
	for face: Array in [[4, 5, 7, 6], [0, 2, 3, 1], [1, 3, 7, 5], [0, 4, 6, 2],
			[2, 6, 7, 3], [0, 1, 5, 4]]:
		_tri(st, corners[face[0]], corners[face[1]], corners[face[2]])
		_tri(st, corners[face[0]], corners[face[2]], corners[face[3]])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for p: Vector3 in [a, b, c]:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(p)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	BodyRim.apply(mat)
	return mat
