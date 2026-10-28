class_name SkaterHairMesh
extends RefCounted

# Hair, facial hair and brows: thin shells laid over the head ball's own facets
# (and the neck below it), in the helmet's frame so they ride the HELMET bone
# like the face gear. One shell per HairStyleRegistry style, built once and
# shared; all three wear the one hair colour.
#
# A shell is sampled on a grid of (azimuth, height) and stood off the surface
# under it by a lift. The grid has a column on every facet column edge and a row
# on every ring the head and neck crease at, so no quad spans a ridge and sinks
# behind it — the skin would show through as a row of teeth. The lift tapers
# toward the edges so a hairline meets the skin instead of ending in a step.
#
# Scalp hair is a whole head of hair, crown to hairline, as it would be with
# the helmet off: the locker and a replay camera can look up under the rim.
# Under the shell it is held inside it (test_skater_hair_mesh.gd holds that).
# Facial hair is one sheet per style with the mouth cut out of it, so a
# translucent style never doubles up; it sits under the face gear, so its lift
# is bounded the same way the face's features are, and it rises over the chin
# rather than letting the chin through.

# Azimuth: θ = 0 is +Z (the back), increasing toward +X, as _build_ball and
# _build_helmet sample it. Facial keys are measured from dead front instead.
const _COLUMNS: int = SkaterMeshBuilder.HEAD_LON
const _ROWS: int = SkaterMeshBuilder.HEAD_LAT
# Largest azimuth (rad) and height (m) step between grid lines.
const _MAX_TH_STEP: float = TAU / float(SkaterMeshBuilder.HEAD_LON) / 3.0
const _FACIAL_ROW_M: float = 0.006
const _SCALP_ROW_M: float = 0.01

# Lift an edge tapers down to; the facial sheet tapers over this share of its
# reach, the scalp over this far from its hairline.
const _EDGE_LIFT_M: float = 0.0015
const _EDGE_TAPER: float = 0.3
const _HAIRLINE_TAPER_M: float = 0.01
# Under the helmet the scalp keeps at least this far inside the shell.
const _SHELL_GAP_M: float = 0.002
# Over the crown every style's lift blends to its crown lift between these
# heights, so the columns meet at the pole.
const _CROWN_BLEND_Y := Vector2(0.04, 0.12)

# Below the head ball the shell rides the neck, so its lift turns from
# radial (off the head's centre) to horizontal (off the neck) over this band.
const _NECK_BLEND_TOP_Y: float = -0.09
const _NECK_BLEND_BOTTOM_Y: float = -0.125

# Scalp styles, keyed by azimuth from dead back (degrees, mirrored to dead
# front): (θ, the hairline's height, the lift). The keys run the nape, round
# the ear to the sideburn, up its front edge to the temple and across the
# forehead, which the helmet's brow covers. Each style's crown lift follows it.
const _SHORT: Array[Vector3] = [
	Vector3(0.0, -0.128, 0.004),
	Vector3(60.0, -0.104, 0.004),
	Vector3(90.0, -0.052, 0.003),
	Vector3(108.0, -0.040, 0.003),
	Vector3(125.0, -0.032, 0.003),
	Vector3(128.0, 0.022, 0.003),
	Vector3(140.0, 0.050, 0.004),
	Vector3(155.0, 0.068, 0.004),
	Vector3(168.0, 0.076, 0.004),
	Vector3(180.0, 0.078, 0.004),
]
const _SHORT_CROWN_M: float = 0.005
const _MEDIUM: Array[Vector3] = [
	Vector3(0.0, -0.145, 0.008),
	Vector3(60.0, -0.130, 0.008),
	Vector3(90.0, -0.080, 0.007),
	Vector3(108.0, -0.062, 0.005),
	Vector3(125.0, -0.040, 0.004),
	Vector3(128.0, 0.018, 0.004),
	Vector3(140.0, 0.046, 0.006),
	Vector3(155.0, 0.064, 0.007),
	Vector3(168.0, 0.072, 0.008),
	Vector3(180.0, 0.074, 0.008),
]
const _MEDIUM_CROWN_M: float = 0.009
# Short's sides and sideburns, hanging past the helmet over the collar at the
# back: the drop happens behind the ear.
const _MULLET: Array[Vector3] = [
	Vector3(0.0, -0.182, 0.010),
	Vector3(35.0, -0.176, 0.010),
	Vector3(62.0, -0.128, 0.006),
	Vector3(82.0, -0.062, 0.004),
	Vector3(108.0, -0.040, 0.003),
	Vector3(125.0, -0.032, 0.003),
	Vector3(128.0, 0.022, 0.003),
	Vector3(140.0, 0.050, 0.004),
	Vector3(155.0, 0.068, 0.004),
	Vector3(168.0, 0.076, 0.004),
	Vector3(180.0, 0.078, 0.004),
]
const _MULLET_CROWN_M: float = 0.005
# Clipped high and tight, with a short sideburn; drawn translucent like stubble.
const _BUZZ: Array[Vector3] = [
	Vector3(0.0, -0.112, 0.0025),
	Vector3(60.0, -0.094, 0.0025),
	Vector3(90.0, -0.046, 0.0022),
	Vector3(108.0, -0.036, 0.0022),
	Vector3(118.0, -0.030, 0.0022),
	Vector3(121.0, 0.026, 0.0022),
	Vector3(140.0, 0.054, 0.0022),
	Vector3(155.0, 0.070, 0.0022),
	Vector3(168.0, 0.078, 0.0022),
	Vector3(180.0, 0.080, 0.0022),
]
const _BUZZ_CROWN_M: float = 0.0022
# Thick over the ears and the nape, hanging to a blunt edge over the collar.
const _SHAGGY: Array[Vector3] = [
	Vector3(0.0, -0.158, 0.011),
	Vector3(60.0, -0.150, 0.011),
	Vector3(72.0, -0.144, 0.011),
	Vector3(84.0, -0.118, 0.010),
	Vector3(96.0, -0.110, 0.010),
	Vector3(108.0, -0.084, 0.008),
	Vector3(118.0, -0.074, 0.006),
	Vector3(128.0, -0.048, 0.005),
	Vector3(131.0, 0.012, 0.006),
	Vector3(142.0, 0.040, 0.009),
	Vector3(155.0, 0.058, 0.010),
	Vector3(168.0, 0.066, 0.011),
	Vector3(180.0, 0.068, 0.011),
]
const _SHAGGY_CROWN_M: float = 0.012
# How fast a style's hair may close in toward the neck as it falls below the
# head's widest point (m in per m down): what falls faster hangs instead of
# wrapping under the skull. Zero hugs the head all the way down.
const _HUG: float = 0.0
const _SHAGGY_HANG: float = 0.4
# Between these azimuths from dead back (degrees) the hang gives way: in front
# of the ear hair lies on the cheek, inside the face gear.
const _HANG_FADE_DEG := Vector2(80.0, 100.0)
# A style's kick at its ends, added to its lift below its first key: (height,
# how far out), descending, eased between keys and held past the last.
const _NO_FLARE: Array[Vector2] = []
const _MULLET_FLARE: Array[Vector2] = [Vector2(-0.12, 0.0), Vector2(-0.18, 0.024)]
const _SHAGGY_FLARE: Array[Vector2] = [Vector2(-0.10, 0.0), Vector2(-0.17, 0.012)]

# Facial outlines, keyed by azimuth from dead front (degrees, mirrored):
# (φ, top height, bottom height, lift). The last key's φ is where the sheet
# ends. Every style leaves the mouth bare (SkaterFaceMesh.mouth_rect, plus
# _MOUTH_MARGIN_M).
const _MUSTACHE: Array[Vector4] = [
	Vector4(0.0, -0.036, -0.0545, 0.006),
	Vector4(8.0, -0.037, -0.0545, 0.006),
	Vector4(13.0, -0.041, -0.057, 0.005),
]
# Mustache, the strips beside the mouth, and the chin under it.
const _GOATEE: Array[Vector4] = [
	Vector4(0.0, -0.036, -0.114, 0.011),
	Vector4(8.0, -0.037, -0.112, 0.010),
	Vector4(13.0, -0.040, -0.108, 0.009),
	Vector4(19.0, -0.042, -0.098, 0.007),
]
# Mustache, chin, jaw and cheeks up to the sideburn.
const _BEARD: Array[Vector4] = [
	Vector4(0.0, -0.036, -0.122, 0.012),
	Vector4(10.0, -0.037, -0.120, 0.011),
	Vector4(14.0, -0.038, -0.118, 0.010),
	Vector4(24.0, -0.030, -0.114, 0.009),
	Vector4(40.0, -0.018, -0.104, 0.008),
	Vector4(52.0, -0.008, -0.090, 0.006),
	Vector4(56.0, -0.004, -0.084, 0.005),
]
# A mustache running past the corners of the mouth, and a strip from each end
# down to the jaw. The strips start clear of the chin (SkaterFaceMesh's relief),
# or they frame it and it reads as an open mouth.
const _HORSESHOE: Array[Vector4] = [
	Vector4(0.0, -0.036, -0.0545, 0.007),
	Vector4(14.0, -0.038, -0.0545, 0.007),
	Vector4(14.3, -0.038, -0.090, 0.008),
	Vector4(21.0, -0.040, -0.088, 0.006),
]
# The beard's footprint carried down off the chin to just above the collar,
# square across the front and rising steeply to the jaw at the sides.
const _LONG_BEARD: Array[Vector4] = [
	Vector4(0.0, -0.035, -0.174, 0.013),
	Vector4(14.0, -0.036, -0.172, 0.013),
	Vector4(24.0, -0.032, -0.165, 0.012),
	Vector4(34.0, -0.024, -0.145, 0.011),
	Vector4(44.0, -0.013, -0.122, 0.010),
	Vector4(52.0, -0.006, -0.106, 0.008),
	Vector4(57.0, -0.002, -0.096, 0.006),
]
# Below the chin the surface under the sheet is the throat, ~3 cm behind it; the
# flare stands the sheet out to hang straight down from the chin.
const _LONG_BEARD_FLARE: Array[Vector2] = [
	Vector2(-0.098, 0.0),
	Vector2(-0.118, 0.030),
	Vector2(-0.174, 0.036),
]
# Under a fishbowl, whose chin edge curls in under the jaw: held to what fits
# inside the shield down to that edge, then out.
const _LONG_BEARD_TUCKED_FLARE: Array[Vector2] = [
	Vector2(-0.108, 0.0),
	Vector2(-0.122, 0.016),
	Vector2(-0.150, 0.030),
	Vector2(-0.174, 0.034),
]
# A full sheet is thinner over the lip than at the chin.
const _UPPER_LIFT_SHARE: float = 0.55
# A facial flare stands the sheet off the throat across the front, then fades
# out between these shares of the sheet's reach, so the sides close onto the
# neck: a flare carried round to the jaw leaves the sheet open at the side, a
# flap seen edge on.
const _FLARE_SIDE_FADE := Vector2(0.4, 0.7)
const _MOUTH_MARGIN_M: float = 0.0015
# How far round the mouth's edge a sheet tapers down to the skin.
const _MOUTH_TAPER_M: float = 0.006
# Stubble is the beard's footprint at a near-flush lift, drawn translucent. Any
# sheet stands at least this far over the face's own features.
const _STUBBLE_LIFT_M: float = 0.0022
const STUBBLE_ALPHA: float = 0.42

const _HAIR_ROUGHNESS: float = 0.8

static var _cache: Dictionary = {}


# The scalp shell for one HairStyleRegistry HAIR_* style, a retired one's
# stand-in for it — null for bald (and for a forged index, matching the
# registry's clamp).
static func shared_hair(style: int) -> ArrayMesh:
	match HairStyleRegistry.worn_hair(style):
		HairStyleRegistry.HAIR_SHORT:
			return _shared("hair_short", func() -> ArrayMesh:
				return _build_scalp(_SHORT, _SHORT_CROWN_M, _HUG, _NO_FLARE))
		HairStyleRegistry.HAIR_MEDIUM:
			return _shared("hair_medium", func() -> ArrayMesh:
				return _build_scalp(_MEDIUM, _MEDIUM_CROWN_M, _HUG, _NO_FLARE))
		HairStyleRegistry.HAIR_MULLET:
			return _shared("hair_mullet", func() -> ArrayMesh:
				return _build_scalp(_MULLET, _MULLET_CROWN_M, _HUG, _MULLET_FLARE))
		HairStyleRegistry.HAIR_BUZZ:
			return _shared("hair_buzz", func() -> ArrayMesh:
				return _build_scalp(_BUZZ, _BUZZ_CROWN_M, _HUG, _NO_FLARE))
		HairStyleRegistry.HAIR_SHAGGY:
			return _shared("hair_shaggy", func() -> ArrayMesh:
				return _build_scalp(_SHAGGY, _SHAGGY_CROWN_M, _SHAGGY_HANG, _SHAGGY_FLARE))
		_:
			return null


# The brows in hair colour, over the face's own skin-tinted ones. Every skater
# wears them, bald or not.
static func shared_brows() -> ArrayMesh:
	return _shared("brows", func() -> ArrayMesh:
		var st := _begin()
		st.append_from(SkaterFaceMesh.build_brows(SkaterMeshBuilder.HEAD_RADIUS,
				_COLUMNS, _ROWS), 0, Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)))
		return st.commit())


# The facial shell for one FACIAL_* style worn under one GearModelRegistry
# FACE_* piece — null for none.
static func shared_facial_hair(style: int, helmet_face: int) -> ArrayMesh:
	match style:
		HairStyleRegistry.FACIAL_STUBBLE:
			return _shared("facial_stubble", func() -> ArrayMesh:
				return _build_facial(_BEARD, _STUBBLE_LIFT_M, _NO_FLARE))
		HairStyleRegistry.FACIAL_MUSTACHE:
			return _shared("facial_mustache", func() -> ArrayMesh:
				return _build_facial(_MUSTACHE, -1.0, _NO_FLARE))
		HairStyleRegistry.FACIAL_GOATEE:
			return _shared("facial_goatee", func() -> ArrayMesh:
				return _build_facial(_GOATEE, -1.0, _NO_FLARE))
		HairStyleRegistry.FACIAL_BEARD:
			return _shared("facial_beard", func() -> ArrayMesh:
				return _build_facial(_BEARD, -1.0, _NO_FLARE))
		HairStyleRegistry.FACIAL_HORSESHOE:
			return _shared("facial_horseshoe", func() -> ArrayMesh:
				return _build_facial(_HORSESHOE, -1.0, _NO_FLARE))
		HairStyleRegistry.FACIAL_LONG_BEARD:
			if helmet_face == GearModelRegistry.FACE_FISHBOWL:
				return _shared("facial_long_beard_tucked", func() -> ArrayMesh:
					return _build_facial(_LONG_BEARD, -1.0, _LONG_BEARD_TUCKED_FLARE))
			return _shared("facial_long_beard", func() -> ArrayMesh:
				return _build_facial(_LONG_BEARD, -1.0, _LONG_BEARD_FLARE))
		_:
			return null


# Hair is open sheets seen from both sides (under long hair, behind a sideburn),
# so it renders two-sided. Stubble and a buzz cut are a shadow on the skin
# rather than a volume, so they are translucent by design — like the face gear,
# a ghost fade has to rebuild them from here rather than restore alpha 1 — and
# one-sided, or the sheet's own far side doubles it wherever it turns away.
static func make_material(color_index: int, translucent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = HairStyleRegistry.color_for(color_index)
	mat.roughness = _HAIR_ROUGHNESS
	mat.cull_mode = BaseMaterial3D.CULL_BACK if translucent else BaseMaterial3D.CULL_DISABLED
	if translucent:
		mat.albedo_color.a = STUBBLE_ALPHA
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	BodyRim.apply(mat)
	return mat


static func is_translucent(facial_style: int) -> bool:
	return facial_style == HairStyleRegistry.FACIAL_STUBBLE


static func is_scalp_translucent(hair_style: int) -> bool:
	return hair_style == HairStyleRegistry.HAIR_BUZZ


static func _shared(key: String, builder: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]


# ── Builders ────────────────────────────────────────────────────────────────

static func _build_scalp(keys: Array[Vector3], crown: float, hang: float,
		flare: Array[Vector2]) -> ArrayMesh:
	var hairline := PackedVector2Array()
	for deg: int in range(-180, 181):
		var th: float = deg_to_rad(float(deg))
		hairline.append(Vector2(th, _scalp_key(keys, absf(th)).x))
	var shell: PackedVector3Array = SkaterMeshBuilder.helmet_shell_triangles()
	var span := func(theta: float, _rim: float) -> Vector2:
		return Vector2(SkaterMeshBuilder.HEAD_RADIUS, _scalp_key(keys, absf(_wrap_pi(theta))).x)
	var lift := func(theta: float, _t: float, y: float, _rim: float, at: Vector3) -> float:
		var edge: float = _ramp(_hairline_distance(hairline, theta, y), 0.0, _HAIRLINE_TAPER_M)
		var own: float = lerpf(_scalp_key(keys, absf(_wrap_pi(theta))).y, crown,
				_ramp(y, _CROWN_BLEND_Y.x, _CROWN_BLEND_Y.y))
		# The flare is the hair's kick, so the bottom edge keeps it.
		var full: float = lerpf(_EDGE_LIFT_M, own, edge) + _flare(flare, y)
		return minf(full, _shell_room(shell, at, _out_dir(at, y)) - _SHELL_GAP_M)
	var key_th := PackedFloat32Array()
	for k: Vector3 in keys:
		key_th.append_array(_mirrored(0.0, k.x))
	var settle := Callable()
	if hang > 0.0:
		settle = func(strip: PackedVector3Array) -> PackedVector3Array:
			return _hang(strip, hang, shell)
	var st := _begin()
	_emit_shell(st, -PI, PI, _SCALP_ROW_M, span, lift, key_th, PackedFloat32Array(),
			Rect2(), settle)
	return st.commit()


# One column of a scalp, crown down, with each point held out from the head's
# axis to no less than the point above it less `hang` per metre fallen — unless
# that would carry it through the helmet shell.
static func _hang(strip: PackedVector3Array, hang: float,
		shell: PackedVector3Array) -> PackedVector3Array:
	var centre := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var last: Vector3 = strip[strip.size() - 1] - centre
	var held: float = _ramp(rad_to_deg(absf(atan2(last.x, last.z))),
			_HANG_FADE_DEG.y, _HANG_FADE_DEG.x)
	if held <= 0.0:
		return strip
	hang /= held
	for i: int in range(1, strip.size()):
		var above: Vector3 = strip[i - 1] - centre
		var p: Vector3 = strip[i] - centre
		var across := Vector2(p.x, p.z)
		var floor_m: float = Vector2(above.x, above.z).length() - hang * (above.y - p.y)
		if across.length() >= floor_m or across.length_squared() < 1e-12:
			continue
		across = across.normalized() * floor_m
		var hung: Vector3 = centre + Vector3(across.x, p.y, across.y)
		if _shell_room(shell, Vector3.ZERO, hung.normalized()) - hung.length() < _SHELL_GAP_M:
			continue
		strip[i] = hung
	return strip


# How far (m, over the head's surface) the point at (θ, y) is from the
# hairline, sampled as (θ, height) a degree apart; held at the taper past it.
static func _hairline_distance(hairline: PackedVector2Array, theta: float, y: float) -> float:
	var across: float = maxf(_ball_ring_radius(y), SkaterMeshBuilder.NECK_PROFILE[0].y)
	var reach: int = ceili(rad_to_deg(_HAIRLINE_TAPER_M / across)) + 1
	var centre: int = roundi(rad_to_deg(_wrap_pi(theta))) + 180
	var best: float = _HAIRLINE_TAPER_M
	for i: int in range(centre - reach, centre + reach + 1):
		var p: Vector2 = hairline[posmod(i, hairline.size() - 1)]
		var d := Vector2(_wrap_pi(theta - p.x) * across, y - p.y)
		best = minf(best, d.length())
	return best


# Distance along `dir` from `at` to the helmet shell, INF where it misses.
static func _shell_room(shell: PackedVector3Array, at: Vector3, dir: Vector3) -> float:
	var best: float = INF
	for i: int in range(0, shell.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(at, dir,
				shell[i], shell[i + 1], shell[i + 2])
		if hit != null:
			best = minf(best, ((hit as Vector3) - at).length())
	return best


# `flat_lift` >= 0 replaces the outline's own lift, untapered (stubble).
static func _build_facial(outline: Array[Vector4], flat_lift: float,
		flare: Array[Vector2]) -> ArrayMesh:
	var reach: float = deg_to_rad(outline[outline.size() - 1].x)
	var mouth: Rect2 = SkaterFaceMesh.mouth_rect().grow(_MOUTH_MARGIN_M)
	var centre := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var span := func(theta: float, _rim: float) -> Vector2:
		var k: Vector4 = _facial_key(outline, absf(_wrap_pi(theta - PI)))
		return Vector2(k.y, k.z)
	var lift := func(theta: float, t: float, y: float, _rim: float, at: Vector3) -> float:
		var face := Vector2(at.x - centre.x, at.y - centre.y)
		var own: float = flat_lift
		if flat_lift < 0.0:
			var a: float = absf(_wrap_pi(theta - PI))
			var side: float = _ramp(a, reach, reach * (1.0 - _EDGE_TAPER))
			var edge: float = minf(minf(_ramp(t, 0.0, _EDGE_TAPER),
					_ramp(t, 1.0, 1.0 - _EDGE_TAPER)), side)
			edge = minf(edge, _ramp(_rect_distance(mouth, face), 0.0, _MOUTH_TAPER_M))
			own = lerpf(_EDGE_LIFT_M, _facial_key(outline, a).w
					* lerpf(_UPPER_LIFT_SHARE, 1.0, t), edge) \
					+ _flare(flare, y) * _ramp(a, reach * _FLARE_SIDE_FADE.y, reach * _FLARE_SIDE_FADE.x)
		return maxf(own, SkaterFaceMesh.relief(face.x, face.y) + _STUBBLE_LIFT_M)
	# Grid lines on the mouth's edges cut its hole clean; on the chin's, the
	# sheet follows the relief it rises over.
	var cut_th: PackedFloat32Array = _azimuths_for_x(
			PackedFloat32Array([mouth.position.x, mouth.end.x]), mouth.get_center().y)
	var chin_ys: PackedFloat32Array = SkaterFaceMesh.relief_ys()
	cut_th.append_array(_azimuths_for_x(SkaterFaceMesh.relief_xs(), chin_ys[1]))
	for k: Vector4 in outline:
		cut_th.append_array(_mirrored(PI, k.x))
	var cut_y := PackedFloat32Array([mouth.position.y, mouth.end.y])
	cut_y.append_array(chin_ys)
	var st := _begin()
	_emit_shell(st, PI - reach, PI + reach, _FACIAL_ROW_M, span, lift, cut_th, cut_y, mouth)
	return st.commit()


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading, like every part
	return st


# Samples the shell between azimuths th0 < th1. `span(θ, rim)` gives the
# (top, bottom) heights at θ; `lift(θ, t, y, rim, at)` the stand-off at height
# fraction t (0 top, 1 bottom), height y and unlifted surface point `at`.
# `rim` is the helmet rim's height over the strip. The rows are one set of
# heights shared by every strip, clamped into each strip's own span, so a
# crease's row lines up across them. `cut_th` and `cut_y` add grid lines, and
# quads whose surface centre falls in `hole` (head-local x, y) are left out.
# `settle(strip)`, if given, has the last word on each column's points.
static func _emit_shell(st: SurfaceTool, th0: float, th1: float, row_m: float,
		span: Callable, lift: Callable, cut_th := PackedFloat32Array(),
		cut_y := PackedFloat32Array(), hole := Rect2(), settle := Callable()) -> void:
	var cols: Array[Vector2] = _azimuth_samples(th0, th1, cut_th)
	var thetas := PackedFloat32Array()
	var rims := PackedFloat32Array()
	var spans: Array[Vector2] = []
	var y_hi: float = -INF
	var y_lo: float = INF
	for c: Vector2 in cols:
		var theta: float = _sample_azimuth(c)
		var rim: float = SkaterMeshBuilder.helmet_rim_y(_helmet_azimuth(c))
		var range_y: Vector2 = span.call(theta, rim)
		thetas.append(theta)
		rims.append(rim)
		spans.append(range_y)
		y_hi = maxf(y_hi, range_y.x)
		y_lo = minf(y_lo, range_y.y)
	var heights: PackedFloat32Array = _row_heights(y_hi, y_lo, row_m, cut_y)
	var centre := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var grid: Array[PackedVector3Array] = []
	var bare: Array[PackedVector3Array] = []
	for k: int in cols.size():
		var strip := PackedVector3Array()
		var under := PackedVector3Array()
		var top: float = spans[k].x
		var bottom: float = spans[k].y
		for h: float in heights:
			var y: float = clampf(h, bottom, top)
			var t: float = (top - y) / maxf(top - bottom, 1e-6)
			var at: Vector3 = _point(cols[k], y, 0.0)
			under.append(at)
			strip.append(_point(cols[k], y, lift.call(thetas[k], t, y, rims[k], at)))
		grid.append(settle.call(strip) if settle.is_valid() else strip)
		bare.append(under)
	for k: int in grid.size() - 1:
		for i: int in heights.size() - 1:
			if hole.has_area():
				var mid: Vector3 = (bare[k][i] + bare[k + 1][i + 1]) * 0.5 - centre
				if hole.has_point(Vector2(mid.x, mid.y)):
					continue
			_quad(st, grid[k][i], grid[k + 1][i], grid[k + 1][i + 1], grid[k][i + 1])


# Shared row heights from y_hi down to y_lo: every crease of the head ball's
# rings and the neck's stations in that range, every cut, and evenly spaced
# fill between them no further apart than row_m.
static func _row_heights(y_hi: float, y_lo: float, row_m: float,
		cut_y: PackedFloat32Array) -> PackedFloat32Array:
	var marks := PackedFloat32Array([y_hi, y_lo])
	var r: float = SkaterMeshBuilder.HEAD_RADIUS
	for j: int in range(1, _ROWS):
		marks.append(r * cos(PI * float(j) / float(_ROWS)))
	for station: Vector2 in SkaterMeshBuilder.NECK_PROFILE:
		marks.append(station.x)
	marks.append_array(cut_y)
	var inside := PackedFloat32Array()
	for m: float in marks:
		if m <= y_hi and m >= y_lo:
			inside.append(m)
	inside.sort()
	inside.reverse()
	var out := PackedFloat32Array()
	for i: int in inside.size() - 1:
		var gap: float = inside[i] - inside[i + 1]
		if gap < 1e-5:
			continue
		var n: int = maxi(ceili(gap / row_m), 1)
		for s: int in n:
			out.append(lerpf(inside[i], inside[i + 1], float(s) / float(n)))
	out.append(y_lo)
	return out


# (column, fraction across it) samples from th0 to th1: the two ends, every
# column edge and cut between them, and evenly spaced fill no further apart
# than _MAX_TH_STEP.
static func _azimuth_samples(th0: float, th1: float,
		cut_th: PackedFloat32Array) -> Array[Vector2]:
	var step: float = TAU / float(_COLUMNS)
	var marks := PackedFloat32Array([th0, th1])
	var k: float = ceilf(th0 / step)
	while k * step < th1:
		marks.append(k * step)
		k += 1.0
	for cut: float in cut_th:
		if cut > th0 and cut < th1:
			marks.append(cut)
	marks.sort()
	var thetas := PackedFloat32Array()
	for i: int in marks.size() - 1:
		var gap: float = marks[i + 1] - marks[i]
		if gap < 1e-6:
			continue
		var n: int = maxi(ceili(gap / _MAX_TH_STEP), 1)
		for s: int in n:
			thetas.append(lerpf(marks[i], marks[i + 1], float(s) / float(n)))
	thetas.append(th1)
	var out: Array[Vector2] = []
	for i: int in thetas.size():
		var col: float = floorf(thetas[i] / step)
		# A sample on a column edge belongs to the column it ends, except the first.
		if i > 0 and is_equal_approx(thetas[i], col * step):
			col -= 1.0
		out.append(Vector2(col, _u_for(thetas[i] - col * step, step)))
	return out


# The azimuths (head-local, about the head's centre) at which the facets reach
# each lateral offset in `xs` at height y, near the front.
static func _azimuths_for_x(xs: PackedFloat32Array, y: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x: float in xs:
		var lo: float = PI - 1.2
		var hi: float = PI + 1.2
		for i: int in 40:
			var mid: float = (lo + hi) * 0.5
			var c: Vector2 = _azimuth_samples(mid, mid + 1e-4, PackedFloat32Array())[0]
			if _point(c, y, 0.0).x < x:
				hi = mid
			else:
				lo = mid
		out.append((lo + hi) * 0.5)
	return out


# Distance from p to the rectangle, 0 inside it.
static func _rect_distance(rect: Rect2, p: Vector2) -> float:
	var d := Vector2(maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0),
			maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0))
	return d.length()


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
	return surface + _out_dir(surface, y) * lift


# The way a lift stands a surface point at height y off: radial from the head's
# centre, turning horizontal down the neck.
static func _out_dir(surface: Vector3, y: float) -> Vector3:
	var centre := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var radial: Vector3 = (surface - centre).normalized()
	var across := Vector3(surface.x - centre.x, 0.0, surface.z - centre.z).normalized()
	return radial.lerp(across, _ramp(y, _NECK_BLEND_TOP_Y, _NECK_BLEND_BOTTOM_Y)).normalized()


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


# A quad wound to face away from the head's centre, both its triangles lit by
# the normal of the quad as a whole (across its diagonals): a cell bent across
# a diagonal would otherwise show as two differently lit triangles.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var out: Vector3 = (a + b + c + d) * 0.25 - Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)
	var n: Vector3 = (c - a).cross(d - b)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot(out) < 0.0:
		n = -n
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


# Godot's front faces are clockwise: the face normal is (c − a) × (b − a).
# Rows clamped into a strip's span collapse at its edges; their slivers go.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var face: Vector3 = (c - a).cross(b - a)
	if face.length_squared() < 1e-14:
		return
	if face.dot(n) < 0.0:
		var t: Vector3 = b
		b = c
		c = t
	st.set_normal(n)
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


# Azimuths `deg` either side of `about`: a key's column on both sides, so the
# outline's corners are grid lines rather than smeared across a quad.
static func _mirrored(about: float, deg: float) -> PackedFloat32Array:
	var r: float = deg_to_rad(deg)
	return PackedFloat32Array([about - r, about + r])


static func _flare(flare: Array[Vector2], y: float) -> float:
	if flare.is_empty() or y >= flare[0].x:
		return 0.0
	for i: int in flare.size() - 1:
		if y >= flare[i + 1].x:
			return lerpf(flare[i].y, flare[i + 1].y, _ramp(y, flare[i].x, flare[i + 1].x))
	return flare[flare.size() - 1].y


# 0 at `from`, 1 at `to`, smoothstepped between; either order.
static func _ramp(x: float, from: float, to: float) -> float:
	var t: float = clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _wrap_pi(a: float) -> float:
	return wrapf(a, -PI, PI)
