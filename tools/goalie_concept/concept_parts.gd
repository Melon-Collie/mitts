extends RefCounted

# Part meshes for the goalie concept, each in the frame of the Goalie.tscn node
# it hangs from, and each inside that node's collider envelope. Colour is baked
# per facet from a palette (`palette()`), so a part is one surface.

const Kit := preload("res://tools/goalie_concept/concept_mesh_kit.gd")

const DARK := Color(0.11, 0.11, 0.12)
const STRAP := Color(0.16, 0.16, 0.17)
const STEEL := Color(0.70, 0.74, 0.78)
const CAGE := Color(0.90, 0.90, 0.92)
const DANGLER := Color(0.60, 0.68, 0.76)
const SKIN_SHADOW := Color(0.20, 0.20, 0.22)


# Gear (pads, trapper, blocker) is white with team trim whatever the jersey —
# the one rule that keeps a home goalie from reading as a single colour blob.
static func palette(colors: Dictionary) -> Dictionary:
	var jersey: Color = colors.jersey
	var primary: Color = colors.primary
	var secondary: Color = colors.secondary
	var stripe: Color = colors.jersey_stripe
	if stripe.is_equal_approx(jersey):
		stripe = secondary if not secondary.is_equal_approx(jersey) else primary
	var trim: Color = primary
	if trim.is_equal_approx(Color.WHITE):
		trim = secondary
	return {
		"jersey": jersey,
		"stripe": stripe,
		"stripe2": secondary if not secondary.is_equal_approx(jersey) else primary,
		"pants": colors.pants,
		"mask": colors.helmet,
		"mask_accent": primary if not primary.is_equal_approx(colors.helmet) else Color.WHITE,
		"gear": Color(0.95, 0.95, 0.93),
		"trim": trim,
		"accent": secondary if not secondary.is_equal_approx(trim) else primary,
	}


static func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)


# ── Pads ──────────────────────────────────────────────────────────────────────
# A modern flat-face pad in the 0.28 × 0.84 × 0.20 collider: thigh rise, knee
# stack standing proud, a three-panel shin face, the boot break and the toe
# bridge over the skate; behind, the leg channel between an outer back edge and
# the calf wing on the inner side, which is what seals the ice in a butterfly.
# Stations: (y, width multiplier, front reach, back reach).
const _PAD_HALF_W: float = 0.14
const _PAD_STATIONS: Array[Vector4] = [
	Vector4(0.420, 0.78, 0.050, 0.055),
	Vector4(0.370, 0.86, 0.068, 0.072),
	Vector4(0.275, 0.90, 0.074, 0.084),
	Vector4(0.255, 0.95, 0.098, 0.090),   # knee stack
	Vector4(0.085, 1.00, 0.100, 0.095),
	Vector4(0.065, 0.96, 0.076, 0.096),   # break below the knee
	Vector4(0.040, 1.00, 0.088, 0.100),   # shin
	Vector4(-0.270, 1.00, 0.088, 0.100),
	Vector4(-0.290, 0.96, 0.070, 0.096),  # boot break
	Vector4(-0.310, 1.00, 0.096, 0.094),  # toe bridge
	Vector4(-0.395, 0.95, 0.092, 0.080),
	Vector4(-0.420, 0.84, 0.072, 0.058),
]
# Ring template, x as a fraction of the half-width with +1 the INNER side, z as
# a fraction of the station's front (−) or back (+) reach.
const _PAD_RING: Array[Vector2] = [
	Vector2(-0.82, -1.0), Vector2(-0.30, -1.0), Vector2(0.30, -1.0), Vector2(0.82, -1.0),
	Vector2(1.00, -0.45), Vector2(1.00, 0.30), Vector2(0.92, 1.0),
	Vector2(0.45, 0.62), Vector2(-0.45, 0.62),
	Vector2(-0.88, 1.0), Vector2(-1.00, 0.30), Vector2(-1.00, -0.45),
]
const _PAD_BAND_KNEE: int = 3
const _PAD_BAND_BREAKS: Array[int] = [2, 4, 5, 7, 8]
const _PAD_BAND_TOE: int = 9


static func pad(pal: Dictionary, inner_sign: float) -> ArrayMesh:
	var k := Kit.new()
	var stations: Array = []
	for s: Vector4 in _PAD_STATIONS:
		var r := PackedVector2Array()
		for t: Vector2 in _PAD_RING:
			var reach: float = s.z if t.y < 0.0 else s.w
			r.append(Vector2(t.x * inner_sign * _PAD_HALF_W * s.y, t.y * reach))
		stations.append([s.x, r])
	var gear: Color = pal.gear
	var trim: Color = pal.trim
	var accent: Color = pal.accent
	var paint := func(band: int, side: int, _c: Vector3) -> Color:
		var back: bool = side >= 5 and side <= 9
		# The top and the outer roll carry colour, so the pad's outline still
		# reads against white ice from the overhead camera.
		if side < 0 and band == 0:
			return trim
		if band in _PAD_BAND_BREAKS:
			return _shade(gear, 0.55)
		if back:
			return STRAP if side in [7, 8] else _shade(gear, 0.80)
		if band == _PAD_BAND_KNEE or band == _PAD_BAND_TOE:
			return trim
		# The outer shin panel and the outer roll carry the stripe the length
		# of the leg — the read that says which way a pad is turned.
		if band == 6 and side == 0:
			return accent
		if side in [10, 11]:
			return trim
		if band <= 1 and side == 1:
			return trim
		return gear
	k.sweep(stations, paint)
	# Knee landing on the inner side: the block that meets the ice in a butterfly.
	k.box(Vector3(inner_sign * 0.150, 0.16, 0.025), Vector3(0.035, 0.15, 0.13), STRAP)
	# Straps across the leg channel: knee, calf.
	for y: float in [0.16, -0.12]:
		k.box(Vector3(0.0, y, 0.072), Vector3(0.15, 0.028, 0.02), STRAP)
	return k.commit()


# Skate, in an ankle frame: toe toward −Z, sole down. A goalie's: a low cowling
# shell and a long flat blade.
static func skate() -> ArrayMesh:
	var k := Kit.new()
	k.box(Vector3(0.0, 0.0, 0.035), Vector3(0.095, 0.075, 0.13), DARK)          # boot upper
	k.box(Vector3(0.0, -0.045, -0.025), Vector3(0.105, 0.06, 0.27), Color(0.30, 0.31, 0.33))  # cowling
	k.box(Vector3(0.0, -0.088, -0.025), Vector3(0.022, 0.026, 0.24), DARK)      # holder
	k.box(Vector3(0.0, -0.104, -0.025), Vector3(0.007, 0.012, 0.29), STEEL)     # runner
	return k.commit()


# ── Trunk ─────────────────────────────────────────────────────────────────────
# The jersey worn over a chest protector: cut big and square, with the yoke
# across the shoulders and hem stripes. Body frame: the 0.62 × 0.72 × 0.28 box.
const _JERSEY_STATIONS: Array[Vector4] = [
	Vector4(0.420, 0.15, 0.080, 0.080),
	Vector4(0.390, 0.28, 0.125, 0.118),
	Vector4(0.310, 0.325, 0.155, 0.140),
	Vector4(0.120, 0.325, 0.162, 0.146),
	Vector4(-0.040, 0.320, 0.160, 0.148),
	Vector4(-0.090, 0.326, 0.163, 0.150),
	Vector4(-0.125, 0.330, 0.165, 0.152),
	Vector4(-0.150, 0.333, 0.167, 0.153),
	Vector4(-0.185, 0.337, 0.170, 0.155),
	Vector4(-0.250, 0.345, 0.176, 0.160),
]


static func jersey(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	var stations: Array = []
	for s: Vector4 in _JERSEY_STATIONS:
		stations.append([s.x, Kit.ring(s.y, s.z, s.w, 16, 3.2)])
	var base: Color = pal.jersey
	var stripe: Color = pal.stripe
	var stripe2: Color = pal.stripe2
	var paint := func(band: int, _side: int, _c: Vector3) -> Color:
		match band:
			0, 1:
				return stripe2
			5, 7:
				return stripe2
			6:
				return stripe
		return base
	k.sweep(stations, paint)
	# Crest on the chest: a placeholder roundel in the kit's two accents.
	k.set_transform(Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(0.0, 0.15, -0.16)))
	var crest := func(_i: int, _j: int, _c: Vector3) -> Color: return stripe
	var core := func(_i: int, _j: int, _c: Vector3) -> Color: return stripe2
	k.sweep([[0.012, Kit.ring(0.095, 0.095, 0.095, 12)], [-0.004, Kit.ring(0.095, 0.095, 0.095, 12)]], crest)
	k.sweep([[0.018, Kit.ring(0.068, 0.068, 0.068, 12)], [0.006, Kit.ring(0.068, 0.068, 0.068, 12)]], core)
	k.set_transform(Transform3D.IDENTITY)
	return k.commit()


static func floater(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	k.ellipsoid(Vector3.ZERO, Vector3(0.125, 0.075, 0.145), pal.stripe2, 10, 5)
	return k.commit()


static func pants(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	var stations: Array = [
		[-0.10, Kit.ring(0.29, 0.145, 0.135, 16, 3.0)],
		[-0.30, Kit.ring(0.315, 0.160, 0.145, 16, 3.0)],
		[-0.40, Kit.ring(0.32, 0.160, 0.145, 16, 3.0)],
	]
	var base: Color = pal.pants
	var side_stripe: Color = pal.stripe
	var paint := func(_band: int, side: int, _c: Vector3) -> Color:
		# The facet square to either hip carries a stripe.
		return side_stripe if side in [3, 11] else base
	k.sweep(stations, paint)
	return k.commit()


static func neck() -> ArrayMesh:
	var k := Kit.new()
	var solid := func(_i: int, _j: int, _c: Vector3) -> Color: return DARK
	k.sweep([[0.48, Kit.ring(0.050, 0.050, 0.050, 8, 2.0, 0.0, 0.02)],
			[0.33, Kit.ring(0.065, 0.065, 0.065, 8, 2.0, 0.0, 0.02)]], solid)
	return k.commit()


# ── Limbs ─────────────────────────────────────────────────────────────────────
# Authored from y = 0 (the near joint) down to y = −1 (the far one), so a basis
# whose Y column is (near − far) lays one between any two points at true radius.

static func sleeve_upper(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	var base: Color = pal.jersey
	var solid := func(_i: int, _j: int, _c: Vector3) -> Color: return base
	k.sweep([[0.05, Kit.ring(0.105, 0.105, 0.105, 10)],
			[-1.0, Kit.ring(0.092, 0.092, 0.092, 10)]], solid)
	return k.commit()


# The forearm sleeve carries the stripes, just past the elbow, where every
# goalie jersey has them.
static func sleeve_fore(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	var base: Color = pal.jersey
	var stripe: Color = pal.stripe
	var stripe2: Color = pal.stripe2
	var ys: Array[float] = [0.04, -0.14, -0.24, -0.31, -0.41, -1.0]
	var stations: Array = []
	for y: float in ys:
		var r: float = lerpf(0.092, 0.074, -y)
		stations.append([y, Kit.ring(r, r, r, 10)])
	var paint := func(band: int, _j: int, _c: Vector3) -> Color:
		match band:
			1, 3:
				return stripe2
			2:
				return stripe
		return base
	k.sweep(stations, paint)
	return k.commit()


static func elbow(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	k.ellipsoid(Vector3.ZERO, Vector3(0.098, 0.098, 0.098), pal.jersey, 10, 5)
	return k.commit()


# Pants leg through the thigh guard to the knee, which the pad's thigh rise
# covers.
static func thigh(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	var pants: Color = pal.pants
	var stations: Array = [
		[0.06, Kit.ring(0.140, 0.140, 0.140, 10)],
		[-0.50, Kit.ring(0.130, 0.130, 0.130, 10)],
		[-0.62, Kit.ring(0.110, 0.110, 0.110, 10)],
		[-1.05, Kit.ring(0.090, 0.090, 0.090, 10)],
	]
	var paint := func(band: int, _j: int, _c: Vector3) -> Color:
		return pants if band < 2 else _shade(pants, 0.7)
	k.sweep(stations, paint)
	return k.commit()


# ── Mask ──────────────────────────────────────────────────────────────────────
# Head frame (collider 0.24 × 0.33 × 0.28, centred 0.017 below the origin).
# Stations (y, lateral, back reach, front reach).
const _MASK_STATIONS: Array[Vector4] = [
	Vector4(0.148, 0.035, 0.045, 0.035),
	Vector4(0.130, 0.082, 0.098, 0.088),
	Vector4(0.090, 0.110, 0.130, 0.126),
	Vector4(0.040, 0.118, 0.140, 0.144),   # brow
	Vector4(0.000, 0.120, 0.140, 0.130),
	Vector4(-0.050, 0.114, 0.124, 0.136),
	Vector4(-0.080, 0.106, 0.108, 0.138),
	Vector4(-0.110, 0.096, 0.092, 0.140),  # jaw: the chin holds, the back tucks
	Vector4(-0.150, 0.070, 0.082, 0.132),
	Vector4(-0.180, 0.036, 0.058, 0.110),
]
const _MASK_SIDES: int = 16
const _CAGE_TOP_Y: float = 0.035
const _CAGE_BOT_Y: float = -0.080
const _CAGE_EDGE_DEG: float = 34.0


static func mask(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	var stations: Array = []
	for s: Vector4 in _MASK_STATIONS:
		stations.append([s.x, Kit.ring(s.y, s.w, s.z, _MASK_SIDES, 2.2)])
	var base: Color = pal.mask
	var accent: Color = pal.mask_accent
	var paint := func(_band: int, side: int, c: Vector3) -> Color:
		if side < 0:
			return base
		var ang: float = rad_to_deg(atan2(c.x, -c.z))
		if c.y < _CAGE_TOP_Y and c.y > _CAGE_BOT_Y and absf(ang) < _CAGE_EDGE_DEG:
			return SKIN_SHADOW
		# Backplate: the strapped-on rear shell, which from above is what says
		# which way he is looking.
		if absf(ang) > 140.0:
			return Color(0.92, 0.92, 0.92)
		# Two swoops back from the cage along each cheek.
		if c.y < 0.0 and c.y > -0.12 and absf(ang) > 50.0 and absf(ang) < 95.0:
			return accent
		if c.y > 0.07 and absf(c.x) < 0.03:
			return accent
		return base
	k.sweep(stations, paint)
	_cage(k)
	# Throat dangler: the plate hung under the chin, the goalie's silhouette tell.
	k.box(Vector3(0.0, -0.215, -0.105), Vector3(0.095, 0.07, 0.012), DANGLER, 3.0)
	k.box(Vector3(0.0, -0.182, -0.098), Vector3(0.04, 0.02, 0.012), DARK)
	return k.commit()


static func _mask_front(y: float) -> Vector2:
	for i: int in _MASK_STATIONS.size() - 1:
		var a: Vector4 = _MASK_STATIONS[i]
		var b: Vector4 = _MASK_STATIONS[i + 1]
		if y <= a.x and y >= b.x:
			var t: float = (a.x - y) / (a.x - b.x)
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.w, b.w, t))
	return Vector2(_MASK_STATIONS[0].y, _MASK_STATIONS[0].w)


static func _mask_point(y: float, deg: float, proud: float) -> Vector3:
	var s: Vector2 = _mask_front(y)
	var a: float = deg_to_rad(deg)
	return Vector3((s.x + proud) * sin(a), y, -(s.y + proud) * cos(a))


# Cat-eye cage: a frame round the opening, two centre bars down the nose and
# two cross bars below the eyes, leaving the eye holes open.
static func _cage(k: Kit) -> void:
	var proud: float = 0.012
	for deg: float in [-_CAGE_EDGE_DEG, -6.0, 6.0, _CAGE_EDGE_DEG]:
		var top: float = _CAGE_TOP_Y if absf(deg) > 10.0 else _CAGE_TOP_Y - 0.008
		_bar(k, _mask_point(top, deg, proud), _mask_point(_CAGE_BOT_Y, deg, proud), 0.005)
	for y: float in [_CAGE_TOP_Y, -0.032, -0.060, _CAGE_BOT_Y]:
		var span: float = _CAGE_EDGE_DEG if y != -0.032 else 20.0
		var steps: int = 6
		for i: int in steps:
			var d0: float = lerpf(-span, span, float(i) / steps)
			var d1: float = lerpf(-span, span, float(i + 1) / steps)
			_bar(k, _mask_point(y, d0, proud), _mask_point(y, d1, proud), 0.0045)


static func _bar(k: Kit, a: Vector3, b: Vector3, half: float) -> void:
	var len: float = a.distance_to(b)
	if len < 1e-5:
		return
	var y: Vector3 = (b - a) / len
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.UP).normalized()
	var z: Vector3 = x.cross(y)
	k.set_transform(Transform3D(Basis(x, y, z), (a + b) * 0.5))
	k.box(Vector3.ZERO, Vector3(half * 2.0, len + half * 2.0, half * 2.0), CAGE, 2.0)
	k.set_transform(Transform3D.IDENTITY)


# ── Trapper ───────────────────────────────────────────────────────────────────
# Glove frame: −Z toward the shooter, the glove on the goalie's −X side so +X
# is its thumb (body) side, origin at the wrist. Outline in (x, y).
const _TRAPPER_OUTLINE: Array[Vector2] = [
	Vector2(-0.020, -0.075), Vector2(0.060, -0.055), Vector2(0.105, -0.010),
	Vector2(0.122, 0.060), Vector2(0.108, 0.128), Vector2(0.070, 0.152),
	Vector2(0.046, 0.128), Vector2(0.026, 0.188), Vector2(-0.020, 0.222),
	Vector2(-0.075, 0.212), Vector2(-0.115, 0.160), Vector2(-0.130, 0.078),
	Vector2(-0.124, -0.005), Vector2(-0.092, -0.055),
]
const _TRAPPER_POCKET := Vector2(-0.005, 0.072)
# (z, scale) back to front, then down into the pocket.
const _TRAPPER_LAYERS: Array[Vector2] = [
	Vector2(0.065, 0.80), Vector2(0.030, 1.00), Vector2(-0.040, 1.00),
	Vector2(-0.062, 0.86), Vector2(-0.045, 0.66), Vector2(-0.005, 0.60),
]


static func trapper(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	# Sweep axis Y is the glove's Z; the ring's (x, z) is the outline's (x, y).
	k.set_transform(Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.UP), Vector3.ZERO))
	var stations: Array = []
	for layer: Vector2 in _TRAPPER_LAYERS:
		var r := PackedVector2Array()
		for p: Vector2 in _TRAPPER_OUTLINE:
			r.append(_TRAPPER_POCKET + (p - _TRAPPER_POCKET) * layer.y)
		stations.append([layer.x, r])
	var gear: Color = pal.gear
	var trim: Color = pal.trim
	var accent: Color = pal.accent
	var paint := func(band: int, side: int, c: Vector3) -> Color:
		if band >= 3:
			return _shade(gear, 0.62) if band == 4 or side < 0 else trim
		if band == 0:
			return _shade(gear, 0.86)
		# Thumb up the body side, the finger stall's crown across the top.
		if c.x > 0.07 and c.z > 0.0:
			return accent
		if c.z > 0.17:
			return trim
		return gear
	k.sweep(stations, paint, true, true, {3: Vector3.DOWN, 4: Vector3.DOWN})
	k.set_transform(Transform3D.IDENTITY)
	# Cuff round the wrist, where the forearm goes in.
	k.box(Vector3(0.0, -0.085, 0.035), Vector3(0.165, 0.075, 0.13), trim, 4.0)
	return k.commit()


# ── Blocker ───────────────────────────────────────────────────────────────────
# Board frame (the 0.20 × 0.39 × 0.05 Blocker collider): Y along the forearm
# toward the fingers, −Z the face presented to the shooter.
static func blocker_board(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	var gear: Color = pal.gear
	var trim: Color = pal.trim
	var accent: Color = pal.accent
	var stations: Array = []
	for y: float in [0.195, 0.175, 0.105, 0.075, -0.175, -0.195]:
		var inset: float = 0.012 if absf(y) > 0.18 else 0.0
		stations.append([y, Kit.ring(0.100 - inset, 0.024 - inset * 0.5, 0.024 - inset * 0.5, 8, 5.0)])
	var paint := func(band: int, side: int, c: Vector3) -> Color:
		if side < 0 or band == 0 or band == 4:
			return trim
		if c.z > 0.0:
			return _shade(gear, 0.8)
		if band == 2:
			return accent
		# A diagonal sash across the face.
		if absf(c.x + c.y * 0.6) < 0.025:
			return trim
		return gear
	k.sweep(stations, paint)
	# Finger protection: the raised roll down the board's outer edge.
	var roll := func(_i: int, _j: int, _c: Vector3) -> Color: return trim
	k.sweep([[0.17, Kit.ring(0.02, 0.026, 0.02, 8, 2.0, -0.108, -0.006)],
			[-0.17, Kit.ring(0.02, 0.026, 0.02, 8, 2.0, -0.108, -0.006)]], roll)
	return k.commit()


# The padded glove on the shaft, in the BlockArm (grip) frame.
static func blocker_hand(pal: Dictionary) -> ArrayMesh:
	var k := Kit.new()
	k.ellipsoid(Vector3(0.0, 0.0, 0.01), Vector3(0.055, 0.07, 0.06), _shade(pal.gear, 0.82), 8, 5)
	return k.commit()
