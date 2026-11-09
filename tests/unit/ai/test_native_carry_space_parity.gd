extends GutTest

# Parity fuzz: NativeCarrySpace (C++ GDExtension, native/src/) against the
# GDScript references — AIEvadeRead.evade_safety_reference,
# AICarrySpace.carry_safety_reference and carry_strip_point_reference — for
# carriers anywhere on the ice, against the boards and in the corners, moving or
# still, against defences from none to six, closing, retreating, crossing and
# skating with the carry, with caps per man, some null, or none; carries short
# and long, stands, with and without the escape gate. The two agree to the bit.
# Goes pending when the extension isn't built.

const FUZZ_ITERATIONS: int = 1500
const SEED: int = 0x43415259  # "CARY"

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_rng.seed = SEED


func _native_missing() -> bool:
	if ClassDB.class_exists(&"NativeCarrySpace"):
		return false
	NativeParityGuard.report_missing(self, "NativeCarrySpace")
	return true


func _on_ice() -> Vector3:
	return Vector3(_rng.randf_range(-GameRules.INNER_HALF_WIDTH, GameRules.INNER_HALF_WIDTH),
			0.0, _rng.randf_range(-GameRules.INNER_HALF_LENGTH, GameRules.INNER_HALF_LENGTH))


func _velocity(top: float) -> Vector3:
	var a: float = _rng.randf_range(-PI, PI)
	return Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.0, top)


func _caps() -> AISkaterCaps:
	var c := AISkaterCaps.new()
	c.max_accel = _rng.randf_range(3.0, 9.0)
	c.blade_span = _rng.randf_range(1.4, 2.2)
	c.max_speed = _rng.randf_range(6.0, 10.0)
	c.lateral_grip = _rng.randf_range(0.6, 1.4)
	c.max_blade_reach = _rng.randf_range(2.0, 2.8)
	return c


# A defence round `around`: most within `spread` of it, where the reads work.
func _defence(around: Vector3, opponents: Array[Vector3], vels: Array[Vector3],
		caps: Array, spread: float = 6.0) -> void:
	for _k: int in _rng.randi_range(0, 6):
		opponents.append(around + _velocity(spread) if _rng.randf() < 0.8 else _on_ice())
		vels.append(_velocity(9.0))
		caps.append(null if _rng.randf() < 0.3 else _caps())
	if _rng.randf() < 0.3:
		caps.clear()


func test_every_keep_read_is_the_gdscripts() -> void:
	if _native_missing():
		return
	var native: RefCounted = NativeCarrySpaceFactory.make()
	var reads: Array[int] = [0, 0, 0]
	for i: int in FUZZ_ITERATIONS:
		var carrier: Vector3 = _on_ice()
		var vel: Vector3 = _velocity(9.0) if _rng.randf() < 0.7 else Vector3.ZERO
		var opponents: Array[Vector3] = []
		var vels: Array[Vector3] = []
		var caps: Array = []
		_defence(carrier, opponents, vels, caps)
		var reach: float = _rng.randf_range(0.6, 1.2)
		var reference: float = AIEvadeRead.evade_safety_reference(carrier, vel, opponents, vels,
				reach, caps)
		var ported: float = native.evade_safety(carrier, vel, opponents, vels, reach,
				AICarrySpace.pack_caps(caps, opponents.size()))
		assert_eq(ported, reference, "read %d: %s at %s against %d" % [i, carrier, vel,
				opponents.size()])
		reads[0 if reference <= 0.0 else (2 if reference >= 1.0 else 1)] += 1
	gut.p("keep reads: %d lost, %d between, %d kept" % reads)
	assert_gt(reads[1], FUZZ_ITERATIONS / 10, "a good share of the reads sweep the seam")


func test_every_carry_read_is_the_gdscripts() -> void:
	if _native_missing():
		return
	var native: RefCounted = NativeCarrySpaceFactory.make()
	var reads: Array[int] = [0, 0, 0]
	var strips: int = 0
	for i: int in FUZZ_ITERATIONS:
		var from: Vector3 = _on_ice()
		var to: Vector3 = from if _rng.randf() < 0.15 \
				else from + _velocity(12.0) + Vector3(0.0, 0.0, 0.001)
		var t: float = _rng.randf_range(0.05, 2.5)
		var opponents: Array[Vector3] = []
		var vels: Array[Vector3] = []
		var caps: Array = []
		_defence(from.lerp(to, _rng.randf()), opponents, vels, caps, 12.0)
		var escape: bool = _rng.randf() < 0.5
		var covered_only: bool = _rng.randf() < 0.3
		var safety: float = AICarrySpace.carry_safety_reference(from, to, t, opponents, vels,
				caps, escape)
		assert_eq(native.carry_safety(from, to, t, opponents, vels,
				AICarrySpace.pack_caps(caps, opponents.size()), escape), safety,
				"carry %d: %s to %s in %.2f s against %d" % [i, from, to, t, opponents.size()])
		var strip: Vector3 = AICarrySpace.carry_strip_point_reference(from, to, t, opponents,
				vels, caps, escape, covered_only)
		assert_eq(native.carry_strip_point(from, to, t, opponents, vels,
				AICarrySpace.pack_caps(caps, opponents.size()), escape, covered_only), strip,
				"strip %d: %s to %s in %.2f s against %d" % [i, from, to, t, opponents.size()])
		reads[0 if safety <= 0.0 else (2 if safety >= 1.0 else 1)] += 1
		if strip != to:
			strips += 1
	gut.p("carry reads: %d lost, %d between, %d kept; %d stripped short" % [reads[0], reads[1],
			reads[2], strips])
	# The carry maps' bands are narrow: most carries read 0 or 1 outright.
	assert_gt(reads[1], FUZZ_ITERATIONS / 20, "a share of the carries read in between")
	assert_gt(strips, FUZZ_ITERATIONS / 10, "a good share of the carries strip short")
