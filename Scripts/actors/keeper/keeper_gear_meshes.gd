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
			_sleeve(k, h, false)
		P.FOREARM_G, P.FOREARM_B:
			_sleeve(k, h, true)
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


# The pad's boot over the skate: flat along the ice, tall where it meets the
# pad and sloping down to the toe, the toe bridge strapped across it.
static func _boot(k: KeeperMeshKit, h: Vector3) -> void:
	var stations: Array[Vector3] = [
		Vector3(h.z, 0.85, 1.0),
		Vector3(0.0, 1.0, 0.55),
		Vector3(-h.z * 0.7, 0.92, -0.15),
		Vector3(-h.z, 0.72, -0.55),
	]
	var rings: Array[PackedVector3Array] = []
	for st: Vector3 in stations:
		rings.append(_boot_section(st.x, h.x * st.y, -h.y, h.y * st.z))
	k.sweep(S.PADS, rings, Vector3(0.0, -h.y * 0.4, 0.0))
	k.box(S.STRAP, Vector3(0.0, -h.y * 0.15, -h.z * 0.25), Vector3(h.x * 1.01, h.y * 0.62, 0.014))


# A boot section square to Z at `z`: flat on the bottom, its top shoulders cut.
static func _boot_section(z: float, w: float, bottom: float, top: float) -> PackedVector3Array:
	var shoulder: float = minf(w * 0.3, (top - bottom) * 0.4)
	return PackedVector3Array([
		Vector3(-w, bottom, z), Vector3(w, bottom, z), Vector3(w, top - shoulder, z),
		Vector3(w - shoulder, top, z), Vector3(-w + shoulder, top, z), Vector3(-w, top - shoulder, z),
	])


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
		KeeperMeshKit.octagon(sole + 0.05, h.x * 0.9, h.z * 0.6, 0.025, 1.0, 0.0, h.z * 0.35),
	]
	k.sweep(S.SKATE_STEEL, rings, Vector3(0.0, sole, 0.0))
	k.tint = _DEEP
	var cuff: Array[PackedVector3Array] = [
		KeeperMeshKit.ellipse(1, Vector3(0.0, sole + 0.04, h.z * 0.45), h.x * 0.85, 0.06, 8),
		KeeperMeshKit.ellipse(1, Vector3(0.0, h.y, h.z * 0.40), h.x * 0.80, 0.055, 8),
	]
	k.sweep(S.SKATE_BOOT, cuff, Vector3(0.0, (sole + h.y) * 0.5, h.z * 0.4))
	k.tint = Color.WHITE


# The pants leg over the thigh guard: a broad, flat-faced panel across the front
# of the thigh, narrowing a little to the knee, the pants' stripe round it.
static func _thigh(k: KeeperMeshKit, h: Vector3) -> void:
	var cut: float = h.x * 0.3
	var rings: Array[PackedVector3Array] = [
		KeeperMeshKit.octagon(-h.y, h.x * 0.88, h.z * 0.85, cut * 0.88),
		KeeperMeshKit.octagon(-h.y * 0.15, h.x * 0.97, h.z * 0.97, cut),
		KeeperMeshKit.octagon(h.y, h.x, h.z, cut),
	]
	k.sweep(S.PANTS, rings, Vector3.ZERO)
	var band: Array[PackedVector3Array] = [
		KeeperMeshKit.octagon(-h.y * 0.25, h.x * 0.975, h.z * 0.975, cut),
		KeeperMeshKit.octagon(-h.y * 0.05, h.x * 0.985, h.z * 0.985, cut),
	]
	k.sweep(S.PANTS_STRIPE, band, Vector3(0.0, -h.y * 0.15, 0.0), false, false)


static func _pants(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = [
		KeeperMeshKit.octagon(-h.y, h.x, h.z, h.x * 0.25),
		KeeperMeshKit.octagon(0.0, h.x * 0.98, h.z * 0.95, h.x * 0.28),
		KeeperMeshKit.octagon(h.y, h.x * 0.80, h.z * 0.62, h.x * 0.3),
	]
	k.sweep(S.PANTS, rings, Vector3.ZERO)
	k.tint = _DEEP
	k.box(S.PANTS, Vector3(0.0, h.y - 0.02, 0.0), Vector3(h.x * 0.87, 0.02, h.z * 0.86))
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
# The elbow cap behind the forearm's top, as shares of the forearm box's half
# extents: centre and radii.
const ELBOW_CAP_CENTER := Vector3(0.0, 0.82, 0.45)
const ELBOW_CAP_RADII := Vector3(0.7, 0.22, 0.5)


# The jersey's bottom section on the protector, in the chest box's frame: where
# its tail hangs from (KeeperJerseyTail).
static func jersey_hem_ring(h: Vector3) -> PackedVector3Array:
	var st: Vector4 = _CHEST_STATIONS[0]
	return KeeperMeshKit.octagon(-h.y, h.x * st.y, h.z * st.z, h.x * st.w * st.y)


static func _chest(k: KeeperMeshKit, h: Vector3) -> void:
	var rings: Array[PackedVector3Array] = []
	for st: Vector4 in _CHEST_STATIONS:
		var y: float = -h.y + st.x if st.x > 0.0 or st == _CHEST_STATIONS[0] else h.y + st.x
		rings.append(KeeperMeshKit.octagon(y, h.x * st.y, h.z * st.z, h.x * st.w * st.y))
	k.sweep(S.JERSEY, rings, Vector3.ZERO)


# A sleeve over an arm pad, narrowing down the bone. The upper arm's begins in
# its shoulder cap over the joint; the forearm's is full at the elbow, its
# elbow cap standing out behind the joint.
static func _sleeve(k: KeeperMeshKit, h: Vector3, fore: bool) -> void:
	var rings: Array[PackedVector3Array] = []
	if fore:
		for sh: Vector2 in [Vector2(-1.0, 0.78), Vector2(0.2, 0.86), Vector2(0.75, 0.95), Vector2(1.0, 0.92)]:
			rings.append(KeeperMeshKit.ellipse(1, Vector3(0.0, h.y * sh.x, 0.0), h.x * sh.y,
					h.z * sh.y, 10, PI / 10.0))
		k.sweep(S.JERSEY, rings, Vector3.ZERO)
		k.ellipsoid(S.JERSEY, ELBOW_CAP_CENTER * h, ELBOW_CAP_RADII * h, 4, 8)
		return
	var joint: float = h.y - KeeperGear.SHOULDER_CAP_ABOVE_JOINT_M
	var profile: Array[Vector2] = SHOULDER_CAP_PROFILE.duplicate()
	profile.append(Vector2(-0.25, 0.078))
	profile.append(Vector2(-h.y - joint, 0.072))
	for st: Vector2 in profile:
		rings.append(KeeperMeshKit.ellipse(1, Vector3(0.0, joint + st.x, 0.0), st.y, st.y, 10, PI / 10.0))
	k.sweep(S.JERSEY, rings, Vector3(0.0, joint - 0.1, 0.0))


# The trapper: a cuff at the wrist, the catching body widening above it and
# rounding off past the fingertips, the pocket deep on the palm side and the
# T-trap laced across its top.
static func _trapper(k: KeeperMeshKit, h: Vector3) -> void:
	var cuff := PackedVector2Array([
		Vector2(-h.x * 0.80, h.y), Vector2(h.x * 0.80, h.y),
		Vector2(h.x * 0.80, h.y - 0.10), Vector2(-h.x * 0.80, h.y - 0.10),
	])
	k.slab(S.GLOVE_ACCENT, cuff, -h.z * 0.5, h.z * 0.6)
	var body := PackedVector2Array()
	var cy: float = -0.03
	for i: int in 12:
		var t: float = PI * float(i) / 11.0
		body.append(Vector2(cos(t) * h.x, cy - sin(t) * (h.y + cy)))
	body.append(Vector2(-h.x * 0.85, h.y - 0.10))
	body.append(Vector2(h.x * 0.85, h.y - 0.10))
	k.slab(S.GLOVES, body, -h.z, h.z * 0.7)
	k.tint = _DEEP
	var pocket := PackedVector2Array()
	for i: int in 10:
		var t: float = TAU * float(i) / 10.0
		pocket.append(Vector2(cos(t) * h.x * 0.55, cy - 0.04 + sin(t) * h.y * 0.42))
	k.slab(S.GLOVES, pocket, -h.z - 0.004, -h.z + 0.01)
	k.tint = Color.WHITE
	k.box(S.GLOVE_ACCENT, Vector3(0.0, -h.y * 0.80, -h.z * 0.4), Vector3(h.x * 0.55, 0.012, h.z * 0.45))
	k.box(S.GLOVE_ACCENT, Vector3(0.0, -h.y * 0.62, -h.z * 0.4), Vector3(0.012, h.y * 0.18, h.z * 0.45))


# The blocker: the board on the back of the hand, a panel down its face, the
# fist behind it on the stick.
static func _blocker(k: KeeperMeshKit, h: Vector3) -> void:
	var cut: float = 0.03
	var board := PackedVector2Array([
		Vector2(-h.x + cut, -h.y), Vector2(h.x - cut, -h.y), Vector2(h.x, -h.y + cut),
		Vector2(h.x, h.y - cut), Vector2(h.x - cut, h.y), Vector2(-h.x + cut, h.y),
		Vector2(-h.x, h.y - cut), Vector2(-h.x, -h.y + cut),
	])
	k.slab(S.GLOVES, board, -h.z, h.z)
	k.box(S.GLOVE_ACCENT, Vector3(-h.x * 0.35, 0.0, -h.z - 0.003), Vector3(h.x * 0.22, h.y * 0.88, 0.003))
	k.ellipsoid(S.GLOVES, Vector3(0.0, -KeeperAnatomy.BLOCKER_ABOVE_GRIP_M, h.z + KeeperAnatomy.BLOCKER_FACE_OFF_GRIP_M * 0.6),
			Vector3(0.05, 0.065, 0.045), 4, 8)


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
