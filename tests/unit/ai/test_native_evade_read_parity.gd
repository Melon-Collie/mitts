extends GutTest

# Parity fuzz: NativeEvadeRead (C++ GDExtension, native/src/) against the GDScript
# reference AIEvadeRead.evade_safety_reference — carriers anywhere on the ice,
# against the boards and in the corners, moving or still, against defences from
# none to six, closing, retreating and crossing, with caps per man, some null,
# or none. The two agree to the bit. Goes pending when the extension isn't built.

const FUZZ_ITERATIONS: int = 1500
const SEED: int = 0x45564144  # "EVAD"

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_rng.seed = SEED


func _native_missing() -> bool:
	if ClassDB.class_exists(&"NativeEvadeRead"):
		return false
	NativeParityGuard.report_missing(self, "NativeEvadeRead")
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
	return c


func test_every_read_is_the_gdscripts() -> void:
	if _native_missing():
		return
	var native: RefCounted = NativeEvadeReadFactory.make()
	var reads: Array[int] = [0, 0, 0]
	for i: int in FUZZ_ITERATIONS:
		var carrier: Vector3 = _on_ice()
		var vel: Vector3 = _velocity(9.0) if _rng.randf() < 0.7 else Vector3.ZERO
		var opponents: Array[Vector3] = []
		var vels: Array[Vector3] = []
		var caps: Array = []
		var n: int = _rng.randi_range(0, 6)
		for _k: int in n:
			# Most in a carrier's neighbourhood, where the sweep has to work.
			var near: bool = _rng.randf() < 0.8
			opponents.append(carrier + _velocity(6.0) if near else _on_ice())
			vels.append(_velocity(9.0))
			caps.append(null if _rng.randf() < 0.3 else _caps())
		if _rng.randf() < 0.3:
			caps.clear()
		var reach: float = _rng.randf_range(0.6, 1.2)
		var reference: float = AIEvadeRead.evade_safety_reference(carrier, vel, opponents, vels,
				reach, caps)
		var ported: float = native.evade_safety(carrier, vel, opponents, vels, reach,
				AIEvadeRead._pack_caps(caps, n))
		assert_eq(ported, reference, "read %d: %s at %s against %d" % [i, carrier, vel, n])
		reads[0 if reference <= 0.0 else (2 if reference >= 1.0 else 1)] += 1
	gut.p("reads: %d lost, %d between, %d kept" % reads)
	assert_gt(reads[1], FUZZ_ITERATIONS / 10, "a good share of the reads sweep the seam")
