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
		KeeperMeshKit.octagon(h.y, h.x * 0.86, h.z * 0.85, h.x * 0.3),
	]
	k.sweep(S.PANTS, rings, Vector3.ZERO)
	k.tint = _DEEP
	k.box(S.PANTS, Vector3(0.0, h.y - 0.02, 0.0), Vector3(h.x * 0.87, 0.02, h.z * 0.86))
	k.tint = Color.WHITE


# The chest protector under the jersey: wide at the floaters, pinched at the
# waist, the hem striped.
static func _chest(k: KeeperMeshKit, h: Vector3) -> void:
	var stations: Array[Vector3] = [
		Vector3(-h.y, 0.80, 0.90),
		Vector3(-h.y + 0.06, 0.84, 0.92),
		Vector3(-h.y + 0.20, 0.82, 0.95),
		Vector3(h.y - 0.14, 0.95, 1.0),
		Vector3(h.y - 0.04, 1.0, 0.95),
		Vector3(h.y, 0.70, 0.70),
	]
	var rings: Array[PackedVector3Array] = []
	for s: Vector3 in stations:
		rings.append(KeeperMeshKit.octagon(s.x, h.x * s.y, h.z * s.z, h.x * 0.2 * s.y))
	k.sweep(S.JERSEY, rings, Vector3.ZERO)
	k.tube(S.JERSEY_STRIPE, -h.y + 0.03, -h.y + 0.08, h.x * 0.81, h.x * 0.83, 8, h.z / h.x * 1.1, false)
	k.ellipsoid(S.JERSEY_STRIPE, Vector3(0.0, h.y - 0.01, 0.0), Vector3(0.07, 0.02, 0.07), 3, 8)


static func _sleeve(k: KeeperMeshKit, h: Vector3, fore: bool) -> void:
	k.tube(S.JERSEY, -h.y, h.y, h.x * (0.85 if fore else 0.95), h.x, 8, h.z / h.x)
	if fore:
		k.tube(S.JERSEY_STRIPE, -h.y * 0.2, h.y * 0.15, h.x * 0.92, h.x * 0.96, 8, h.z / h.x, false)
		k.ellipsoid(S.JERSEY, Vector3(0.0, h.y, 0.0), Vector3(h.x, h.x, h.z), 4, 8)


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


# The mask: the shell over the skull, the cage across the face, the dangler
# hanging under the chin.
static func _mask(k: KeeperMeshKit, h: Vector3) -> void:
	k.ellipsoid(S.HELMET, Vector3(0.0, 0.01, 0.005), Vector3(h.x * 0.95, h.y * 0.93, h.z * 0.95), 7, 12)
	var face_z: float = -h.z * 0.97
	for x: float in [-0.055, -0.02, 0.02, 0.055]:
		k.box(S.CAGE, Vector3(x, -0.035, face_z), Vector3(0.0035, 0.055, 0.004))
	for y: float in [-0.005, -0.045, -0.08]:
		k.box(S.CAGE, Vector3(0.0, y, face_z), Vector3(0.075, 0.0035, 0.004))
	k.box(S.STRAP, Vector3(0.0, -h.y + 0.02, -h.z * 0.7), Vector3(0.045, 0.03, 0.006))


static func _blade(k: KeeperMeshKit, h: Vector3) -> void:
	k.box(S.STICK, Vector3.ZERO, h)
	k.box(S.STICK_TAPE, Vector3(-h.x * 0.15, 0.0, 0.0), Vector3(h.x * 0.45, h.y + 0.002, h.z + 0.002))
