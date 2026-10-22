class_name KeeperGearMeshes
extends RefCounted

# The keeper's gear as meshes, one per KeeperGear part, each built in its part's
# own box frame (centred on the box, X across, Y along, −Z toward the shooter)
# and kept inside the box the puck meets, so what he looks like is what he
# saves with. Built once and shared by every keeper.

const S := KeeperMeshKit.Slot
const P := KeeperGear.Part
const _CREASE := Color(0.82, 0.82, 0.84)
const _DEEP := Color(0.62, 0.62, 0.66)

# The pad's outer roll: how far its section's corners are cut back, of the half
# width; and how far under the pad's top the knee stack's full section sits.
const PAD_CUT: float = 0.28
const PAD_STACK_TOP_M: float = 0.04

static var _cache: Array[ArrayMesh] = []


static func mesh(part: int) -> ArrayMesh:
	if _cache.is_empty():
		_cache.resize(KeeperGear.PART_COUNT)
	if _cache[part] == null:
		_cache[part] = _build(part)
	return _cache[part]


static func _build(part: int) -> ArrayMesh:
	var k := KeeperMeshKit.new()
	var h: Vector3 = KeeperGear.half_extents(part)
	match part:
		P.PAD_G, P.PAD_B:
			_pad(k, h)
		P.RISE_G, P.RISE_B:
			_rise(k, h)
		P.BOOT_G, P.BOOT_B:
			_boot(k, h)
		P.SKATE_G, P.SKATE_B:
			_skate(k, h)
		P.THIGH_G, P.THIGH_B:
			_thigh(k, h)
		P.PANTS:
			_pants(k, h)
		P.CHEST:
			_chest(k, h)
		P.UPPER_ARM_G, P.UPPER_ARM_B:
			_sleeve(k, h)
		P.FOREARM_G, P.FOREARM_B:
			_forearm(k, h)
		P.GLOVE:
			_trapper(k, h)
		P.BLOCKER:
			_blocker(k, h)
		P.MASK:
			_mask(k, h)
		P.BLADE:
			_blade(k, h)
		P.PADDLE:
			k.box(S.STICK, Vector3.ZERO, h)
		P.SHAFT:
			k.box(S.STICK, Vector3.ZERO, h)
			k.box(S.STICK_TAPE, Vector3(0.0, h.y - 0.05, 0.0), Vector3(h.x + 0.004, 0.05, h.z + 0.004))
	return k.commit()


# The leg pad: a faceted face proud of the leg channel, rolled on its outer
# edges, the knee stack standing out at the top and the boot slanting back over
# the skate at the bottom. Two creases run down the face and the breaks above
# and below the knee cross it.
static func _pad(k: KeeperMeshKit, h: Vector3) -> void:
	var cut: float = h.x * PAD_CUT
	var stations: Array[Vector3] = [
		Vector3(-h.y, 0.78, 0.45),
		Vector3(-h.y + 0.06, 0.94, 0.80),
		Vector3(-h.y + 0.14, 1.0, 0.86),
		Vector3(h.y - 0.20, 1.0, 0.86),
		Vector3(h.y - 0.17, 0.98, 1.0),
		Vector3(h.y - PAD_STACK_TOP_M, 1.0, 1.0),
		Vector3(h.y, 0.88, 0.85),
	]
	var rings: Array[PackedVector3Array] = []
	for s: Vector3 in stations:
		rings.append(KeeperMeshKit.octagon(s.x, h.x * s.y, h.z, cut * s.y, s.z))
	k.sweep(S.PADS, rings, Vector3.ZERO)
	k.tint = _CREASE
	for x: float in [-h.x * 0.40, h.x * 0.40]:
		k.box(S.PADS, Vector3(x, -0.02, -h.z * 0.86 - 0.002),
				Vector3(0.004, h.y - 0.17, 0.003))
	for y: float in [h.y - 0.185, h.y - 0.24]:
		k.box(S.PADS, Vector3(0.0, y, -h.z * 0.86 - 0.002), Vector3(h.x * 0.92, 0.006, 0.003))
	k.tint = Color.WHITE


# The knee stack's full section, just under the pad's top, in the pad's box
# frame: where the break above the knee starts (KeeperKneeBreak).
static func pad_top_ring(h: Vector3) -> PackedVector3Array:
	return KeeperMeshKit.octagon(h.y - PAD_STACK_TOP_M, h.x, h.z, h.x * PAD_CUT)


# The thigh rise's bottom section, in its box frame: where the break ends.
static func rise_bottom_ring(h: Vector3) -> PackedVector3Array:
	return KeeperMeshKit.octagon(-h.y, h.x * 0.92, h.z, h.x * 0.2)


static func _rise(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = [
		rise_bottom_ring(h),
		KeeperMeshKit.octagon(h.y - 0.05, h.x, h.z, h.x * 0.25),
		KeeperMeshKit.octagon(h.y, h.x * 0.7, h.z * 0.7, h.x * 0.25),
	]
	k.sweep(S.PADS, rings, Vector3.ZERO)


# The pad's boot over the skate, back (+Z, under the pad) to toe: (where as a
# share of the box's half length, half width as a share of the pad's, top
# above the boot's bottom in metres). It runs on from the pad's sides, stands
# over the skate's cowling to past its toe, and closes down in front of it.
const _BOOT_STATIONS: Array[Vector3] = [
	Vector3(1.0, 0.86, 0.156), Vector3(0.0, 0.95, 0.145), Vector3(-0.6, 0.93, 0.125),
	Vector3(-0.82, 0.86, 0.11), Vector3(-1.0, 0.66, 0.065),
]


static func _boot(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = []
	for st: Vector3 in _BOOT_STATIONS:
		rings.append(_boot_section(h.z * st.x, h.x * st.y, -h.y, -h.y + st.z))
	k.sweep(S.PADS, rings, Vector3(0.0, -h.y * 0.4, 0.0))


# A boot section square to Z at `z`: flat on the bottom, its top shoulders cut.
static func _boot_section(z: float, w: float, bottom: float, top: float) -> PackedVector3Array:
	var shoulder: float = minf(w * 0.3, (top - bottom) * 0.4)
	return PackedVector3Array([
		Vector3(-w, bottom, z), Vector3(w, bottom, z), Vector3(w, top - shoulder, z),
		Vector3(w - shoulder, top, z), Vector3(-w + shoulder, top, z), Vector3(-w, top - shoulder, z),
	])


# How far the skate's cowling stands above its sole: what the pad's boot covers.
const SKATE_COWLING_TOP_M: float = 0.05


# A goalie skate: the steel and its holder under a low plastic cowling, the
# boot rising out of it round the ankle.
static func _skate(k: KeeperMeshKit, h: Vector3) -> void:
	var ice: float = -h.y
	k.box(S.SKATE_STEEL, Vector3(0.0, ice + 0.011, 0.0), Vector3(0.0035, 0.011, h.z))
	k.box(S.SKATE_BOOT, Vector3(0.0, ice + 0.034, 0.0), Vector3(0.012, 0.013, h.z * 0.92))
	var sole: float = ice + KeeperAnatomy.SKATE_LIFT_M
	var rings: Array[PackedVector3Array] = [
		KeeperMeshKit.octagon(sole - 0.02, h.x * 0.85, h.z * 0.92, 0.02),
		KeeperMeshKit.octagon(sole + 0.035, h.x, h.z, 0.025),
		KeeperMeshKit.octagon(sole + SKATE_COWLING_TOP_M, h.x * 0.9, h.z * 0.6, 0.025, 1.0, 0.0,
				h.z * 0.35),
	]
	k.sweep(S.SKATE_STEEL, rings, Vector3(0.0, sole, 0.0))
	k.tint = _DEEP
	var cuff: Array[PackedVector3Array] = [
		KeeperMeshKit.ellipse(1, Vector3(0.0, sole + 0.04, h.z * 0.45), h.x * 0.85, 0.06, 8),
		KeeperMeshKit.ellipse(1, Vector3(0.0, h.y, h.z * 0.40), h.x * 0.80, 0.055, 8),
	]
	k.sweep(S.SKATE_BOOT, cuff, Vector3(0.0, (sole + h.y) * 0.5, h.z * 0.4))
	k.tint = Color.WHITE


# The pants' legs' and body's sections, bottom to top: height as a share of the
# box's half height; half width, front depth and back depth as shares of the
# box's. Each is a rounded box of PANTS_ROUNDNESS, flat enough across the front
# for the thigh guard under the leg. The jersey's tail drapes against the same
# shapes (KeeperJerseyTail).
const PANTS_ROUNDNESS: float = 3.0
# A leg: the opening just above the knee, roomy up the thigh, and a domed top
# tucked up into the body, so a flexed hip shows a rounded crease.
const THIGH_SECTIONS: Array[Vector4] = [
	Vector4(-1.0, 0.92, 0.82, 0.82), Vector4(-0.6, 0.94, 0.88, 0.86),
	Vector4(0.2, 0.98, 0.96, 0.96), Vector4(0.75, 0.96, 0.94, 0.92),
	Vector4(1.0, 0.70, 0.62, 0.62),
]
# The body: the seat full and low behind, the hip pads widest, narrowing to the
# belt at the belly.
const PANTS_SECTIONS: Array[Vector4] = [
	Vector4(-1.0, 0.90, 0.68, 0.92), Vector4(-0.55, 1.0, 0.84, 1.0),
	Vector4(0.0, 0.98, 0.92, 0.95), Vector4(0.5, 0.90, 0.86, 0.80),
	Vector4(1.0, 0.80, 0.70, 0.62),
]
const _PANTS_SEGMENTS: int = 16


# A piece's half width, front depth and back depth at height `y` in its box
# frame, from its sections; zero outside it.
static func section_at(sections: Array[Vector4], h: Vector3, y: float) -> Vector3:
	var t: float = y / h.y
	if t < sections[0].x or t > sections[sections.size() - 1].x:
		return Vector3.ZERO
	for i: int in sections.size() - 1:
		var a: Vector4 = sections[i]
		var b: Vector4 = sections[i + 1]
		if t <= b.x:
			var f: float = (t - a.x) / (b.x - a.x)
			return Vector3(h.x * lerpf(a.y, b.y, f), h.z * lerpf(a.z, b.z, f),
					h.z * lerpf(a.w, b.w, f))
	return Vector3.ZERO


static func _pants_rings(sections: Array[Vector4], h: Vector3) -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	for st: Vector4 in sections:
		rings.append(KeeperMeshKit.rounded(h.y * st.x, h.x * st.y, h.z * st.z, h.z * st.w,
				_PANTS_SEGMENTS, PANTS_ROUNDNESS))
	return rings


# Round a pants leg at its fullest: what the kit's pants stripe widths are
# shares of.
static func thigh_girth_m() -> float:
	var h: Vector3 = KeeperGear.half_extents(P.THIGH_G)
	var st: Vector4 = THIGH_SECTIONS[2]
	var ring: PackedVector3Array = KeeperMeshKit.rounded(0.0, h.x * st.y, h.z * st.z, h.z * st.w,
			_PANTS_SEGMENTS, PANTS_ROUNDNESS)
	var out: float = 0.0
	for i: int in ring.size():
		out += ring[i].distance_to(ring[(i + 1) % ring.size()])
	return out


# A pants leg over the thigh guard, its opening dark inside.
static func _thigh(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = _pants_rings(THIGH_SECTIONS, h)
	k.sweep(S.PANTS, rings, Vector3.ZERO, false, true)
	var opening: Vector4 = THIGH_SECTIONS[0]
	var inside: Array[PackedVector3Array] = [rings[0], KeeperMeshKit.rounded(-h.y + 0.03,
			h.x * opening.y * 0.8, h.z * opening.z * 0.8, h.z * opening.w * 0.8,
			_PANTS_SEGMENTS, PANTS_ROUNDNESS)]
	k.tint = _DEEP
	k.sweep(S.PANTS, inside, Vector3(0.0, -h.y + 0.1, 0.0), false, true)
	k.tint = Color.WHITE


# The pants' body round the hips and seat, the belt dark round its top.
static func _pants(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = _pants_rings(PANTS_SECTIONS, h)
	k.sweep(S.PANTS, rings, Vector3.ZERO)
	var top: Vector4 = PANTS_SECTIONS[PANTS_SECTIONS.size() - 1]
	var belt: Array[PackedVector3Array] = []
	for y: float in [h.y - 0.025, h.y]:
		belt.append(KeeperMeshKit.rounded(y, h.x * top.y + 0.003, h.z * top.z + 0.003,
				h.z * top.w + 0.003, _PANTS_SEGMENTS, PANTS_ROUNDNESS))
	k.tint = _DEEP
	k.sweep(S.PANTS, belt, Vector3(0.0, h.y - 0.0125, 0.0), false, false)
	k.tint = Color.WHITE


# The jersey over the chest protector (its paint is the kit's, by height: see
# KeeperGearView), bottom to top: height from the hem (or,
# negative, down from the top), half width and depth as shares of the box, and
# how far its corners are cut. It hangs straight and loose from the floaters to
# a hem past the belt, and slopes from the shoulders up to the collar.
const _CHEST_STATIONS: Array[Vector4] = [
	Vector4(0.0, 0.90, 1.0, 0.22),
	Vector4(0.12, 0.89, 0.98, 0.22),
	Vector4(0.28, 0.91, 0.98, 0.22),
	Vector4(-0.12, 0.97, 1.0, 0.22),
	Vector4(-0.065, 0.95, 0.95, 0.35),
	Vector4(-0.03, 0.55, 0.72, 0.30),
	Vector4(0.0, 0.32, 0.55, 0.25),
]
# The shoulder cap at the top of the upper arm's sleeve, turning with the arm as
# the skater's does: (height above the joint, radius). A blunt base tucked
# under the jersey's slope, the equator carrying the number, and down to the
# sleeve's own radius.
const SHOULDER_CAP_PROFILE: Array[Vector2] = [
	Vector2(KeeperGear.SHOULDER_CAP_ABOVE_JOINT_M, 0.060),
	Vector2(0.025, 0.088),
	Vector2(-0.015, KeeperGear.SHOULDER_CAP_RADIUS_M - 0.002),
	Vector2(-0.060, 0.096),
	Vector2(-0.105, 0.090),
	Vector2(-0.150, 0.080),
]
# Where the cap's colour gives way to the sleeve's, below the joint, and where
# the yoke over its top ends, above it.
const SHOULDER_CAP_BOTTOM_M: float = -0.150
const SHOULDER_CAP_YOKE_M: float = 0.025
# The forearm's sleeve from the wrist (−1) to the elbow (+1): (where, radius as
# a share of the pad's), full at the elbow and narrowing to the wrist.
const _FOREARM_PROFILE: Array[Vector2] = [
	Vector2(-1.0, 0.78), Vector2(0.2, 0.86), Vector2(0.75, 0.95), Vector2(1.0, 0.92),
]
# The glove's cuff round the forearm's end, the arm pad going into it: (up the
# forearm from the wrist, radius as a share of the elbow pad's, which bounds the
# box), closing onto the sleeve at its open end.
const _GLOVE_CUFF: Array[Vector2] = [
	Vector2(0.0, 0.94), Vector2(0.05, 0.98), Vector2(0.08, 0.86),
]


# The jersey's section `i` up the protector, in the chest box's frame. The
# bottom one is its hem, where its tail hangs from (KeeperJerseyTail).
static func jersey_section(h: Vector3, i: int) -> PackedVector3Array:
	var st: Vector4 = _CHEST_STATIONS[i]
	var y: float = -h.y + st.x if st.x > 0.0 or i == 0 else h.y + st.x
	return KeeperMeshKit.octagon(y, h.x * st.y, h.z * st.z, h.x * st.w * st.y)


static func _chest(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = []
	for i: int in _CHEST_STATIONS.size():
		rings.append(jersey_section(h, i))
	k.sweep(S.JERSEY, rings, Vector3.ZERO)


# The elbow joint in the forearm box's frame: the box runs on above it to hold
# the elbow pad.
static func elbow_in_forearm(h: Vector3) -> Vector3:
	return Vector3(0.0, h.y - KeeperGear.ELBOW_PAD_RADIUS_M, 0.0)


# The forearm's sleeve over its pad, the elbow pad round the joint, and the
# glove's cuff over its end.
static func _forearm(k: KeeperMeshKit, h: Vector3) -> void:
	var elbow: Vector3 = elbow_in_forearm(h)
	var r: float = KeeperGear.FOREARM_PAD_RADIUS_M
	var rings: Array[PackedVector3Array] = []
	for st: Vector2 in _FOREARM_PROFILE:
		var y: float = lerpf(-h.y, elbow.y, (st.x + 1.0) * 0.5)
		rings.append(KeeperMeshKit.ellipse(1, Vector3(0.0, y, 0.0), r * st.y, r * st.y, 10, PI / 10.0))
	k.sweep(S.JERSEY, rings, Vector3.ZERO)
	k.ellipsoid(S.JERSEY, elbow, Vector3.ONE * KeeperGear.ELBOW_PAD_RADIUS_M, 8, 10, PI / 10.0)
	var band: Array[PackedVector3Array] = []
	for st: Vector2 in _GLOVE_CUFF:
		band.append(KeeperMeshKit.ellipse(1, Vector3(0.0, -h.y + st.x, 0.0), h.x * st.y, h.x * st.y,
				10, PI / 10.0))
	k.sweep(S.GLOVES, band, Vector3(0.0, -h.y + 0.04, 0.0))


# The upper arm's sleeve over its pad, beginning in its shoulder cap over the
# joint and narrowing down the bone.
static func _sleeve(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = []
	var joint: float = h.y - KeeperGear.SHOULDER_CAP_ABOVE_JOINT_M
	var profile: Array[Vector2] = SHOULDER_CAP_PROFILE.duplicate()
	profile.append(Vector2(-0.25, 0.078))
	profile.append(Vector2(-h.y - joint, 0.072))
	for st: Vector2 in profile:
		rings.append(KeeperMeshKit.ellipse(1, Vector3(0.0, joint + st.x, 0.0), st.y, st.y, 10, PI / 10.0))
	k.sweep(S.JERSEY, rings, Vector3(0.0, joint - 0.1, 0.0))


# The trapper, held open: the palm to −Z, the fingers to −Y, the cuff over the
# wrist at +Y and the thumb at −X. Outlines are (across, up the glove from the
# cuff's end) in metres; depths run from the palm's face back.
# The cuff round the wrist, from its end up into the catching body: (up the
# glove, half width, half depth). Rounded and turned in at its end, so the
# glove runs on into the arm going into it rather than ending square.
const _TRAPPER_CUFF: Array[Vector3] = [
	Vector3(0.0, 0.068, 0.034), Vector3(0.012, 0.088, 0.046), Vector3(0.026, 0.097, 0.052),
	Vector3(0.06, 0.10, 0.054), Vector3(0.10, 0.096, 0.052),
]
# How many of the cuff's sections from its end carry the accent band.
const _TRAPPER_CUFF_BAND: int = 2
const _TRAPPER_CUFF_ROUNDNESS: float = 2.6
# The catching body above the cuff: the finger section full on the outer side
# and rounding over the top, falling to the web between it and the thumb.
const _TRAPPER_BODY: Array[Vector2] = [
	Vector2(-0.07, 0.07), Vector2(0.10, 0.07), Vector2(0.12, 0.15), Vector2(0.125, 0.22),
	Vector2(0.112, 0.268), Vector2(0.078, 0.302), Vector2(0.03, 0.32), Vector2(-0.015, 0.316),
	Vector2(-0.055, 0.296),
]
# The cheater: the cuff carried on up the thumb side as a flat panel.
const _TRAPPER_CHEATER: Array[Vector2] = [
	Vector2(-0.105, 0.035), Vector2(-0.075, 0.035), Vector2(-0.06, 0.055), Vector2(-0.06, 0.225),
	Vector2(-0.08, 0.245), Vector2(-0.11, 0.245), Vector2(-0.125, 0.225), Vector2(-0.125, 0.06),
]
# The web between the thumb's top and the finger section, laced in a T.
const _TRAPPER_WEB: Array[Vector2] = [
	Vector2(-0.115, 0.215), Vector2(-0.05, 0.215), Vector2(-0.045, 0.30), Vector2(-0.075, 0.318),
	Vector2(-0.115, 0.30),
]


# The trapper: the cuff over the wrist, the cheater up the thumb side, the
# catching body with its pocket on the palm, the T-trap laced across the web at
# the top, and finger rolls down the back.
static func _trapper(k: KeeperMeshKit, h: Vector3) -> void:
	var cuff: Array[PackedVector3Array] = []
	for st: Vector3 in _TRAPPER_CUFF:
		var ring: PackedVector3Array = KeeperMeshKit.rounded(h.y - st.x, st.y, st.z, st.z, 16,
				_TRAPPER_CUFF_ROUNDNESS)
		for i: int in ring.size():
			ring[i].z += h.z * 0.075
		cuff.append(ring)
	var mid: Vector3 = Vector3(0.0, h.y - 0.05, h.z * 0.075)
	k.sweep(S.GLOVE_ACCENT, cuff.slice(0, _TRAPPER_CUFF_BAND), mid, true, false)
	k.sweep(S.GLOVES, cuff.slice(_TRAPPER_CUFF_BAND - 1), mid, false, true)
	k.slab(S.GLOVES, _trapper_outline(h, _TRAPPER_BODY), -h.z * 0.62, h.z)
	k.slab(S.GLOVES, _trapper_outline(h, _TRAPPER_CHEATER), -h.z, h.z * 0.5)
	k.slab(S.GLOVE_ACCENT, _trapper_outline(h, _TRAPPER_CHEATER, 0.75), -h.z - 0.003, -h.z)
	# The pocket: shaded, not a hole, in the middle of the palm.
	k.tint = Color(0.82, 0.82, 0.85)
	var pocket := PackedVector2Array()
	for i: int in 12:
		var t: float = TAU * float(i) / 12.0
		pocket.append(Vector2(0.035 + cos(t) * 0.062, h.y - 0.19 + sin(t) * 0.085))
	k.slab(S.GLOVES, pocket, -h.z * 0.62 - 0.003, -h.z * 0.62 + 0.01)
	k.tint = _DEEP
	k.slab(S.GLOVES, _trapper_outline(h, _TRAPPER_WEB), -h.z * 0.45, -h.z * 0.1)
	k.tint = Color.WHITE
	# The T-trap's laces: its stem down the web from the top, its bar across.
	var z: float = -h.z * 0.45 - 0.004
	k.box(S.GLOVE_ACCENT, Vector3(-0.08, h.y - 0.265, z), Vector3(0.008, 0.045, 0.004))
	k.box(S.GLOVE_ACCENT, Vector3(-0.08, h.y - 0.30, z), Vector3(0.04, 0.008, 0.004))
	# The finger rolls down the back of the catching body.
	for x: float in [0.0, 0.045, 0.09]:
		k.box(S.GLOVES, Vector3(x, h.y - 0.235, h.z - 0.004), Vector3(0.016, 0.065, 0.006))


# An outline (across, up the glove from the cuff's end) in the box's X-Y,
# scaled about its centre by `scale`.
static func _trapper_outline(h: Vector3, pts: Array, scale: float = 1.0) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p: Vector2 in pts:
		c += p
	c /= float(pts.size())
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		var q: Vector2 = c + (p - c) * scale
		out.append(Vector2(q.x, h.y - q.y))
	return out


# The blocker's top side, the board's top carried back over the fingers, in
# profile: (behind the board's back, down from its top). Its top face is flat.
const _BLOCKER_TOP_SIDE: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(0.065, 0.02), Vector2(0.065, 0.085), Vector2(0.0, 0.15),
]
# The fist round the grip, bottom to top: (height, width, depth) as shares of
# BLOCKER_FIST_HALF. A rounded box, as the skaters' gloves are.
const _BLOCKER_FIST: Array[Vector3] = [
	Vector3(-1.0, 0.70, 0.70), Vector3(-0.7, 0.96, 0.96), Vector3(0.35, 1.0, 1.0),
	Vector3(0.8, 0.92, 0.92), Vector3(1.0, 0.62, 0.62),
]


# The blocker: a flat board on the back of the hand, a panel down its face, its
# top side standing back over the fingers, and the gloved fist under that on
# the stick.
static func _blocker(k: KeeperMeshKit, h: Vector3) -> void:
	var grip: Vector3 = -KeeperGear.center_on_bone(P.BLOCKER)
	var back: float = -h.z + KeeperAnatomy.BLOCKER_DEPTH_M
	var cut: float = 0.03
	var board := PackedVector2Array([
		Vector2(-h.x + cut, -h.y), Vector2(h.x - cut, -h.y), Vector2(h.x, -h.y + cut),
		Vector2(h.x, h.y - cut), Vector2(h.x - cut, h.y), Vector2(-h.x + cut, h.y),
		Vector2(-h.x, h.y - cut), Vector2(-h.x, -h.y + cut),
	])
	k.slab(S.GLOVES, board, -h.z, back)
	k.box(S.GLOVE_ACCENT, Vector3(-h.x * 0.35, 0.0, -h.z - 0.003), Vector3(h.x * 0.22, h.y * 0.88, 0.003))
	var near := PackedVector3Array()
	var far := PackedVector3Array()
	for p: Vector2 in _BLOCKER_TOP_SIDE:
		near.append(Vector3(-h.x + cut, h.y - p.y, back + p.x))
		far.append(Vector3(h.x - cut, h.y - p.y, back + p.x))
	var top_side: Array[PackedVector3Array] = [near, far]
	k.sweep(S.GLOVES, top_side, Vector3(0.0, h.y - 0.07, back + 0.03))
	var f: Vector3 = grip + KeeperAnatomy.BLOCKER_FIST_CENTER
	var fh: Vector3 = KeeperAnatomy.BLOCKER_FIST_HALF
	var fist: Array[PackedVector3Array] = []
	for st: Vector3 in _BLOCKER_FIST:
		var ring: PackedVector3Array = KeeperMeshKit.rounded(f.y + fh.y * st.x, fh.x * st.y,
				fh.z * st.z, fh.z * st.z, 12, PANTS_ROUNDNESS)
		for i: int in ring.size():
			ring[i] += Vector3(f.x, 0.0, f.z)
		fist.append(ring)
	k.sweep(S.GLOVES, fist, f)


# The mask's shell, in the head's frame (origin on the neck's line at chin
# height, −Z forward), bottom to top: height, half width, front, back. A long
# chin and jaw jut forward under the cage, the cheeks run back to the
# backplate, the brow stands out over the cage and the dome closes over the
# skull.
const _MASK_SECTIONS: Array[Vector4] = [
	Vector4(-0.040, 0.035, -0.135, -0.090),
	Vector4(-0.005, 0.075, -0.150, -0.020),
	Vector4(0.040, 0.100, -0.152, 0.055),
	Vector4(0.080, 0.115, -0.148, 0.095),
	Vector4(0.110, 0.120, -0.125, 0.115),
	Vector4(0.160, 0.120, -0.120, 0.125),
	Vector4(0.205, 0.118, -0.138, 0.125),
	Vector4(0.235, 0.100, -0.120, 0.115),
	Vector4(0.258, 0.068, -0.080, 0.085),
	Vector4(KeeperGear.MASK_TOP_M, 0.020, -0.020, 0.030),
]
# The face opening, from the mouth to the brow: the shell's front sits back to
# the face there and the cage spans it.
const _MASK_FACE := Vector2(0.095, 0.195)
const _MASK_FACE_Z: float = -0.095
const _MASK_SEGMENTS: int = 16
# The skaters' head and face (SkaterMeshBuilder.shared_head) inside the mask:
# narrowed and flattened to fit the shell, its eyes on the cage's middle row
# and its face 4 cm behind the cage, ahead of the dark inside of the shell.
const _FACE_SCALE := Vector3(0.85, 0.85, 0.75)
const _FACE_CENTER := Vector3(0.0, 0.147, -0.024)
# The cage: straight bars, short and wide, flat across the front and wrapped
# back to the shell at its sides.
const _CAGE_HALF_WIDTH: float = 0.088
const _CAGE_FRONT_Z: float = -0.166
const _CAGE_FLAT_HALF: float = 0.05
const _CAGE_ROWS: Array[float] = [0.09, 0.127, 0.163, 0.20]
const _CAGE_BARS: int = 8
# How sharply the cage wraps back past its flat front: its edge lands on the
# shell's cheek, about where the face opening's side is.
const _CAGE_WRAP: float = 46.0


# The mask: a fibreglass shell over the skull and down the jaw, a bar cage
# across the face opening, his face behind it.
static func _mask(k: KeeperMeshKit, h: Vector3) -> void:
	var o := Vector3(0.0, -h.y + KeeperGear.MASK_BELOW_CHIN_M, h.z - KeeperGear.MASK_BACK_M)
	var rings: Array[PackedVector3Array] = []
	for s: Vector4 in _MASK_SECTIONS:
		rings.append(_mask_ring(o, s))
	k.sweep(S.HELMET, rings, o + Vector3(0.0, 0.12, 0.0))
	var bottom: float = _CAGE_ROWS[0]
	var top: float = _CAGE_ROWS[_CAGE_ROWS.size() - 1]
	k.append(S.SKIN, SkaterMeshBuilder.shared_head(),
			Transform3D(Basis.from_scale(_FACE_SCALE), o + _FACE_CENTER))
	var inside := PackedVector2Array([
		Vector2(-_CAGE_HALF_WIDTH, o.y + bottom), Vector2(_CAGE_HALF_WIDTH, o.y + bottom),
		Vector2(_CAGE_HALF_WIDTH, o.y + top), Vector2(-_CAGE_HALF_WIDTH, o.y + top),
	])
	k.slab(S.STRAP, inside, o.z + _MASK_FACE_Z - 0.006, o.z + _MASK_FACE_Z - 0.003)
	for y: float in _CAGE_ROWS:
		_cage_bar(k, o, Vector2(-_CAGE_HALF_WIDTH, y), Vector2(_CAGE_HALF_WIDTH, y))
	for i: int in _CAGE_BARS:
		var x: float = _CAGE_HALF_WIDTH * (2.0 * (float(i) + 0.5) / float(_CAGE_BARS) - 1.0)
		_cage_bar(k, o, Vector2(x, bottom), Vector2(x, top))
	# The clips holding the cage's sides to the shell.
	for side: float in [-1.0, 1.0]:
		k.box(S.CAGE, o + Vector3(side * (_CAGE_HALF_WIDTH + 0.003), (bottom + top) * 0.5, -0.105),
				Vector3(0.003, (top - bottom) * 0.5 + 0.004, 0.014))


# One section of the shell: a squarish loop (a superellipse), front and back
# reached on the Z axis, its front pushed back to the face inside the opening.
static func _mask_ring(o: Vector3, s: Vector4) -> PackedVector3Array:
	var zc: float = (s.z + s.w) * 0.5
	var rz: float = (s.w - s.z) * 0.5
	var in_face: bool = s.x > _MASK_FACE.x and s.x < _MASK_FACE.y
	var out := PackedVector3Array()
	for i: int in _MASK_SEGMENTS:
		var t: float = TAU * float(i) / float(_MASK_SEGMENTS)
		var sx: float = signf(sin(t)) * pow(absf(sin(t)), 0.667)
		var cz: float = signf(cos(t)) * pow(absf(cos(t)), 0.667)
		var p := Vector3(sx * s.y, s.x, zc - cz * rz)
		if in_face and cos(t) > 0.9:
			p.z = maxf(p.z, _MASK_FACE_Z)
		out.append(o + p)
	return out


# A cage bar from `a` to `b` (x and height in the head's frame), on the cage's
# surface: flat across the front, wrapping back toward the shell past
# _CAGE_FLAT_HALF.
static func _cage_bar(k: KeeperMeshKit, o: Vector3, a: Vector2, b: Vector2) -> void:
	const STEPS: int = 8
	var prev := Vector3.ZERO
	for i: int in STEPS + 1:
		var q: Vector2 = a.lerp(b, float(i) / float(STEPS))
		var wrap: float = maxf(absf(q.x) - _CAGE_FLAT_HALF, 0.0)
		var p: Vector3 = o + Vector3(q.x, q.y, _CAGE_FRONT_Z + _CAGE_WRAP * wrap * wrap)
		if i > 0:
			k.rod(S.CAGE, prev, p, 0.0035)
		prev = p


static func _blade(k: KeeperMeshKit, h: Vector3) -> void:
	k.box(S.STICK, Vector3.ZERO, h)
	k.box(S.STICK_TAPE, Vector3(-h.x * 0.15, 0.0, 0.0), Vector3(h.x * 0.45, h.y + 0.002, h.z + 0.002))
