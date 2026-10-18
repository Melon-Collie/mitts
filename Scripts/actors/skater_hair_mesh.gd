class_name SkaterHairMesh
extends RefCounted

# Hair and facial hair: thin shells laid over the head ball's own facets (and
# the neck below it), in the helmet's frame so they ride the HELMET bone like
# the face gear. One shell per HairStyleRegistry style, built once and shared.
#
# A shell is sampled on a grid of (azimuth, height) and stood off the surface
# under it by a lift. The azimuth samples include every facet column edge, so a
# shell never spans a ridge between columns and sinks behind it; the lift tapers
# toward the edges so a hairline meets the skin instead of ending in a step.
#
# Scalp hair only has to exist where the helmet does not cover it, but its top
# edge must never show: above the rim the lift goes negative and the shell sinks
# into the head, so the edge is hidden by the head and the shell together.
# Facial hair sits under the face gear, so its lift is bounded the same way the
# face's features are (test_skater_hair_mesh.gd holds both).

# Azimuth: θ = 0 is +Z (the back), increasing toward +X, as _build_ball and
# _build_helmet sample it. Facial keys are measured from dead front instead.
const _COLUMNS: int = SkaterMeshBuilder.HEAD_LON
const _ROWS: int = SkaterMeshBuilder.HEAD_LAT
const _SUBCOLUMNS: int = 3

# How far above the helmet rim the scalp shell carries on before it is fully
# sunk, and how deep it sinks. The rim hides everything above it.
const _RIM_OVERLAP_M: float = 0.012
const _SINK_M: float = 0.003
# Lift an edge tapers down to, and over what share of the shell it tapers.
const _EDGE_LIFT_M: float = 0.0015
const _EDGE_TAPER: float = 0.3

# Below the head ball the shell rides the neck, so its lift turns from
# radial (off the head's centre) to horizontal (off the neck) over this band.
const _NECK_BLEND_TOP_Y: float = -0.09
const _NECK_BLEND_BOTTOM_Y: float = -0.125

# Scalp styles, keyed by azimuth from dead back (degrees, mirrored): (θ, the
# hairline's height, the lift). The last key's θ is where the hair ends, which
# is the sideburn's front edge.
const _SHORT: Array[Vector3] = [
	Vector3(0.0, -0.128, 0.004),
	Vector3(60.0, -0.104, 0.004),
	Vector3(90.0, -0.052, 0.003),
	Vector3(108.0, -0.040, 0.003),
	Vector3(125.0, -0.032, 0.002),
]
const _MEDIUM: Array[Vector3] = [
	Vector3(0.0, -0.145, 0.008),
	Vector3(60.0, -0.130, 0.008),
	Vector3(90.0, -0.080, 0.007),
	Vector3(108.0, -0.062, 0.005),
	Vector3(125.0, -0.040, 0.003),
]
# The flow hangs past the helmet over the collar and kicks out at the ends.
const _FLOW: Array[Vector3] = [
	Vector3(0.0, -0.175, 0.010),
	Vector3(50.0, -0.168, 0.010),
	Vector3(85.0, -0.135, 0.009),
	Vector3(105.0, -0.080, 0.006),
	Vector3(125.0, -0.045, 0.003),
]
const _FLOW_FLARE_M: float = 0.028
const _FLOW_FLARE_TOP_Y: float = -0.11
const _FLOW_FLARE_BOTTOM_Y: float = -0.175

# Facial patches, keyed by azimuth from dead front (degrees, mirrored):
# (φ, top height, bottom height, lift). The mouth (about ±9° at y −0.055 to
# −0.062) stays bare.
const _MUSTACHE: Array[Vector4] = [
	Vector4(0.0, -0.036, -0.052, 0.006),
	Vector4(8.0, -0.037, -0.053, 0.006),
	Vector4(13.0, -0.041, -0.057, 0.005),
]
# Chin and the strips either side of the mouth that join it to the mustache.
const _CHIN: Array[Vector4] = [
	Vector4(0.0, -0.064, -0.114, 0.011),
	Vector4(11.0, -0.064, -0.110, 0.009),
	Vector4(14.0, -0.040, -0.106, 0.0085),
	Vector4(19.0, -0.038, -0.098, 0.0075),
]
# Chin, jaw and cheeks up to the sideburn.
const _JAW: Array[Vector4] = [
	Vector4(0.0, -0.064, -0.122, 0.012),
	Vector4(10.0, -0.064, -0.120, 0.011),
	Vector4(14.0, -0.040, -0.118, 0.010),
	Vector4(24.0, -0.030, -0.114, 0.009),
	Vector4(40.0, -0.018, -0.104, 0.008),
	Vector4(52.0, -0.008, -0.090, 0.006),
	Vector4(56.0, -0.004, -0.084, 0.005),
]
# Stubble is the beard's footprint at a near-flush lift, drawn translucent.
const _STUBBLE_LIFT_M: float = 0.0022
const STUBBLE_ALPHA: float = 0.42

const _HAIR_ROUGHNESS: float = 0.8

static var _cache: Dictionary = {}


# The scalp shell for one HairStyleRegistry HAIR_* style — null for bald (and
# for a forged index, matching the registry's clamp).
static func shared_hair(style: int) -> ArrayMesh:
	match style:
		HairStyleRegistry.HAIR_SHORT:
			return _shared("hair_short", func() -> ArrayMesh: return _build_scalp(_SHORT, 0.0))
		HairStyleRegistry.HAIR_MEDIUM:
			return _shared("hair_medium", func() -> ArrayMesh: return _build_scalp(_MEDIUM, 0.0))
		HairStyleRegistry.HAIR_FLOW:
			return _shared("hair_flow",
					func() -> ArrayMesh: return _build_scalp(_FLOW, _FLOW_FLARE_M))
		_:
			return null


# The facial shell for one FACIAL_* style — null for clean-shaven.
static func shared_facial_hair(style: int) -> ArrayMesh:
	match style:
		HairStyleRegistry.FACIAL_STUBBLE:
			return _shared("facial_stubble", func() -> ArrayMesh:
				return _build_facial([_MUSTACHE, _JAW], _STUBBLE_LIFT_M))
		HairStyleRegistry.FACIAL_MUSTACHE:
			return _shared("facial_mustache", func() -> ArrayMesh:
				return _build_facial([_MUSTACHE], -1.0))
		HairStyleRegistry.FACIAL_GOATEE:
			return _shared("facial_goatee", func() -> ArrayMesh:
				return _build_facial([_MUSTACHE, _CHIN], -1.0))
		HairStyleRegistry.FACIAL_BEARD:
			return _shared("facial_beard", func() -> ArrayMesh:
				return _build_facial([_MUSTACHE, _JAW], -1.0))
		_:
			return null


# Hair is open sheets seen from both sides (under the flow, behind a sideburn),
# so it renders two-sided. Stubble is a shadow on the skin rather than a
# volume, so it is translucent by design — like the face gear, a ghost fade
# has to rebuild it from here rather than restore alpha 1.
static func make_material(color_index: int, translucent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HairStyleRegistry.color_for(color_index)
	mat.roughness = _HAIR_ROUGHNESS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if translucent:
		mat.albedo_color.a = STUBBLE_ALPHA
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	BodyRim.apply(mat)
	return mat


static func is_translucent(facial_style: int) -> bool:
	return facial_style == HairStyleRegistry.FACIAL_STUBBLE


static func _shared(key: String, builder: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]


# ── Builders ────────────────────────────────────────────────────────────────

static func _build_scalp(keys: Array[Vector3], flare: float) -> ArrayMesh:
	var reach: float = deg_to_rad(keys[keys.size() - 1].x)
	var span := func(theta: float, rim: float) -> Vector2:
		return Vector2(rim + _RIM_OVERLAP_M, _scalp_key(keys, absf(_wrap_pi(theta))).x)
	var lift := func(theta: float, t: float, y: float, rim: float) -> float:
		var a: float = absf(_wrap_pi(theta))
		var side: float = _ramp(a, reach, reach * (1.0 - _EDGE_TAPER * 0.5))
		var edge: float = minf(_ramp(t, 1.0, 1.0 - _EDGE_TAPER), side)
		# The flare is the flow's kick, so the bottom edge keeps it.
		var full: float = lerpf(_EDGE_LIFT_M, _scalp_key(keys, a).y, edge) \
				+ flare * side * _ramp(y, _FLOW_FLARE_TOP_Y, _FLOW_FLARE_BOTTOM_Y)
		return lerpf(-_SINK_M, full, _ramp(y, rim + _RIM_OVERLAP_M, rim))
	var st := _begin()
	_emit_shell(st, -reach, reach, 12, span, lift)
	return _commit(st)


# `flat_lift` >= 0 replaces every patch's own lift, untapered (stubble).
static func _build_facial(patches: Array, flat_lift: float) -> ArrayMesh:
	var st := _begin()
	for patch: Array[Vector4] in patches:
		var reach: float = deg_to_rad(patch[patch.size() - 1].x)
		var span := func(theta: float, _rim: float) -> Vector2:
			var k: Vector4 = _facial_key(patch, absf(_wrap_pi(theta - PI)))
			return Vector2(k.y, k.z)
		var lift := func(theta: float, t: float, _y: float, _rim: float) -> float:
			if flat_lift >= 0.0:
				return flat_lift
			var a: float = absf(_wrap_pi(theta - PI))
			var edge: float = minf(minf(_ramp(t, 0.0, _EDGE_TAPER),
					_ramp(t, 1.0, 1.0 - _EDGE_TAPER)),
					_ramp(a, reach, reach * (1.0 - _EDGE_TAPER)))
			return lerpf(_EDGE_LIFT_M, _facial_key(patch, a).w, edge)
		_emit_shell(st, PI - reach, PI + reach, 10, span, lift)
	return _commit(st)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading, like every part
	return st


static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


# Samples the shell between azimuths th0 < th1 on `rows` height steps.
# `span(θ, rim)` gives the (top, bottom) heights at θ; `lift(θ, t, y, rim)` the
# stand-off at height fraction t (0 top, 1 bottom) and height y. `rim` is the
# helmet rim's height over the strip.
static func _emit_shell(st: SurfaceTool, th0: float, th1: float, rows: int,
		span: Callable, lift: Callable) -> void:
	var cols: Array[Vector2] = _azimuth_samples(th0, th1)
	var grid: Array[PackedVector3Array] = []
	for c: Vector2 in cols:
		var theta: float = _sample_azimuth(c)
		var rim: float = SkaterMeshBuilder.helmet_rim_y(_helmet_azimuth(c))
		var range_y: Vector2 = span.call(theta, rim)
		var strip := PackedVector3Array()
		for i: int in rows + 1:
			var t: float = float(i) / float(rows)
			var y: float = lerpf(range_y.x, range_y.y, t)
			strip.append(_point(c, y, lift.call(theta, t, y, rim)))
		grid.append(strip)
	for k: int in grid.size() - 1:
		for i: int in rows:
			_quad(st, grid[k][i], grid[k + 1][i], grid[k + 1][i + 1], grid[k][i + 1])


# (column, fraction across it) samples from th0 to th1: every column edge in
# between, _SUBCOLUMNS steps inside each column, and the two ends exactly.
static func _azimuth_samples(th0: float, th1: float) -> Array[Vector2]:
	var step: float = TAU / float(_COLUMNS)
	var out: Array[Vector2] = []
	var k: float = floorf(th0 / step)
	while k * step < th1:
		var a: float = maxf(th0 - k * step, 0.0)
		var b: float = minf(th1 - k * step, step)
		var u0: float = _u_for(a, step)
		var u1: float = _u_for(b, step)
		var first: int = 0 if out.is_empty() else 1
		for i: int in range(first, _SUBCOLUMNS + 1):
			out.append(Vector2(k, lerpf(u0, u1, float(i) / float(_SUBCOLUMNS))))
		k += 1.0
	return out


# Fraction along a column's chord at which the azimuth reaches `phi` from the
# column's first edge (law of sines on the chord's triangle).
static func _u_for(phi: float, step: float) -> float:
	var a: float = sin(phi)
	return a / (a + sin(step - phi))


static func _sample_azimuth(c: Vector2) -> float:
	var w: Vector3 = _chord_dir(c)
	return atan2(w.x, w.z)


# The sample's azimuth about the helmet's own axis — the head's is
# HEAD_FORWARD_M ahead of it — taken at the head's equator.
static func _helmet_azimuth(c: Vector2) -> float:
	var p: Vector3 = _chord_dir(c).normalized() * SkaterMeshBuilder.HEAD_RADIUS \
			+ Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	return atan2(p.x, p.z)


# Horizontal chord point between the column's two edge directions (not unit).
static func _chord_dir(c: Vector2) -> Vector3:
	var step: float = TAU / float(_COLUMNS)
	var a: float = c.x * step
	return Vector3(sin(a), 0.0, cos(a)).lerp(Vector3(sin(a + step), 0.0, cos(a + step)), c.y)


# The surface under (column sample, height) — the head ball's facet, or the
# neck where it stands further out — stood off it by `lift`. Helmet-local.
static func _point(c: Vector2, y: float, lift: float) -> Vector3:
	var centre := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var w: Vector3 = _chord_dir(c)
	var dir: Vector3 = w.normalized()
	var reach: float = maxf(w.length() * _ball_ring_radius(y), _neck_reach(dir, y))
	var surface: Vector3 = centre + dir * reach + Vector3(0.0, y, 0.0)
	var radial: Vector3 = (surface - centre).normalized()
	var out: Vector3 = radial.lerp(dir, _ramp(y, _NECK_BLEND_TOP_Y, _NECK_BLEND_BOTTOM_Y))
	return surface + out.normalized() * lift


# The ball's ring radius at height y, linear between its rings as the facets are.
static func _ball_ring_radius(y: float) -> float:
	var r: float = SkaterMeshBuilder.HEAD_RADIUS
	var yc: float = clampf(y, -r, r)
	for j: int in _ROWS:
		var y0: float = r * cos(PI * float(j) / float(_ROWS))
		var y1: float = r * cos(PI * float(j + 1) / float(_ROWS))
		if yc >= y1:
			return lerpf(r * sin(PI * float(j) / float(_ROWS)),
					r * sin(PI * float(j + 1) / float(_ROWS)), (y0 - yc) / (y0 - y1))
	return 0.0


# How far along `dir` from the head's axis the neck's surface is at height y —
# its vertex radius, so the shell clears the faceted tube everywhere. Zero above
# the neck's top, where it is inside the head.
static func _neck_reach(dir: Vector3, y: float) -> float:
	var profile: Array[Vector2] = SkaterMeshBuilder.NECK_PROFILE
	if y > profile[0].x:
		return 0.0
	var rho: float = profile[profile.size() - 1].y
	for i: int in profile.size() - 1:
		if y >= profile[i + 1].x:
			rho = lerpf(profile[i].y, profile[i + 1].y,
					(profile[i].x - y) / (profile[i].x - profile[i + 1].x))
			break
	# The neck is centred on the helmet's axis, the head ball HEAD_FORWARD_M
	# ahead of it: solve |offset + s·dir| = rho for s.
	var offset := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var b: float = offset.dot(dir)
	return -b + sqrt(maxf(b * b - offset.length_squared() + rho * rho, 0.0))


# A quad wound to face away from the head's centre.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var out: Vector3 = (a + b + c + d) * 0.25 - Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	_tri(st, a, b, c, out)
	_tri(st, a, c, d, out)


# Godot's front faces are clockwise: the normal is (c − a) × (b − a).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var t: Vector3 = b
		b = c
		c = t
	st.set_uv(Vector2.ZERO)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# (hairline height, lift) at |azimuth| `a` from dead back.
static func _scalp_key(keys: Array[Vector3], a: float) -> Vector2:
	var deg: float = rad_to_deg(a)
	for i: int in keys.size() - 1:
		if deg <= keys[i + 1].x:
			var f: float = (deg - keys[i].x) / (keys[i + 1].x - keys[i].x)
			return Vector2(lerpf(keys[i].y, keys[i + 1].y, f), lerpf(keys[i].z, keys[i + 1].z, f))
	var last: Vector3 = keys[keys.size() - 1]
	return Vector2(last.y, last.z)


static func _facial_key(keys: Array[Vector4], a: float) -> Vector4:
	var deg: float = rad_to_deg(a)
	for i: int in keys.size() - 1:
		if deg <= keys[i + 1].x:
			return keys[i].lerp(keys[i + 1], (deg - keys[i].x) / (keys[i + 1].x - keys[i].x))
	return keys[keys.size() - 1]


# 0 at `from`, 1 at `to`, smoothstepped between; either order.
static func _ramp(x: float, from: float, to: float) -> float:
	var t: float = clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _wrap_pi(a: float) -> float:
	return wrapf(a, -PI, PI)
