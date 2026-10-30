extends GutTest

# The stick against the goalie's gear (GoalieBladeCollision): a wall. A blade
# swept into a pad stops on its face and slides along it; one swept clean
# through a thin piece of gear comes back out the side it went in; gear moved
# onto a still blade puts it out the nearest side, across the ice; a blade over
# a pad lying on the ice, or clear of him, is left alone.

const HALF_THICKNESS: float = 0.01
# A standing pad, 0.28 wide, 0.2 deep, 0.8 tall, its face toward −z.
const PAD_AT := Vector3(0.0, 0.4, 0.0)
const PAD_HALF := Vector3(0.14, 0.4, 0.1)


func _box(basis: Basis, origin: Vector3, half: Vector3) -> PackedFloat32Array:
	return PackedFloat32Array([basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z,
			basis.z.x, basis.z.y, basis.z.z, origin.x, origin.y, origin.z, half.x, half.y, half.z])


func _pad() -> PackedFloat32Array:
	return _box(Basis.IDENTITY, PAD_AT, PAD_HALF)


# A blade lying across −z at `z`, its middle at `x`, on the ice.
func _blade_at(x: float, z: float) -> Array[Vector3]:
	return [Vector3(x - 0.15, 0.04, z), Vector3(x + 0.15, 0.04, z)]


func test_a_blade_swept_into_a_pad_stops_on_its_face_and_slides_along_it() -> void:
	var was: Array[Vector3] = _blade_at(0.0, -0.3)
	var now: Array[Vector3] = _blade_at(0.1, -0.05)
	var push: Vector3 = GoalieBladeCollision.resolve((was[0] + was[1]) * 0.5, now[0], now[1], HALF_THICKNESS, _pad())
	var face: float = -(PAD_HALF.z + HALF_THICKNESS)
	assert_almost_eq(now[0].z + push.z, face, 1e-4, "held on the pad's face")
	assert_almost_eq(push.x, 0.0, 1e-5, "sliding along it as it came")
	assert_eq(push.y, 0.0, "across the ice")


func test_a_blade_swept_through_thin_gear_comes_back_out_the_side_it_went_in() -> void:
	var thin: PackedFloat32Array = _box(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0), Vector3(0.3, 0.2, 0.02))
	var was: Array[Vector3] = _blade_at(0.0, -0.1)
	var now: Array[Vector3] = _blade_at(0.0, 0.015)
	var push: Vector3 = GoalieBladeCollision.resolve((was[0] + was[1]) * 0.5, now[0], now[1], HALF_THICKNESS, thin)
	assert_almost_eq(now[0].z + push.z, -(0.02 + HALF_THICKNESS), 1e-4, "back on the near side")


func test_gear_moved_onto_a_still_blade_puts_it_out_the_nearest_side() -> void:
	var now: Array[Vector3] = _blade_at(0.0, -0.08)
	var push: Vector3 = GoalieBladeCollision.resolve((now[0] + now[1]) * 0.5, now[0], now[1], HALF_THICKNESS, _pad())
	assert_almost_eq(now[0].z + push.z, -(PAD_HALF.z + HALF_THICKNESS), 1e-4, "out the front, the nearer side")
	assert_eq(push.y, 0.0, "across the ice")


func test_a_pad_turned_on_the_ice_pushes_the_blade_off_its_side() -> void:
	# A pad lying flat along the ice in the butterfly, turned 30° about the
	# vertical: its long axis across the ice, its face up.
	var lying := Basis(Vector3.UP, deg_to_rad(30.0)) * Basis(Vector3.RIGHT, -PI * 0.5)
	var pad: PackedFloat32Array = _box(lying, Vector3(0.0, 0.1, 0.0), PAD_HALF)
	var now: Array[Vector3] = _blade_at(0.0, 0.0)
	var push: Vector3 = GoalieBladeCollision.resolve((now[0] + now[1]) * 0.5 + Vector3(0.0, 0.0, -0.5), now[0], now[1],
			HALF_THICKNESS, pad)
	assert_ne(push, Vector3.ZERO, "pushed")
	assert_eq(push.y, 0.0, "across the ice, never up off it")
	for end: Vector3 in now:
		var at: Vector3 = end + push
		var local: Vector3 = lying.inverse() * (at - Vector3(0.0, 0.1, 0.0))
		var clear: bool = absf(local.x) >= PAD_HALF.x + HALF_THICKNESS - 1e-4 \
				or absf(local.y) >= PAD_HALF.y + HALF_THICKNESS - 1e-4 \
				or absf(local.z) >= PAD_HALF.z + HALF_THICKNESS - 1e-4
		assert_true(clear, "the blade's end %s out of the pad" % end)


func test_a_blade_clear_of_him_or_over_his_gear_is_left_alone() -> void:
	var now: Array[Vector3] = _blade_at(0.0, -0.5)
	assert_eq(GoalieBladeCollision.resolve((now[0] + now[1]) * 0.5, now[0], now[1], HALF_THICKNESS, _pad()),
			Vector3.ZERO, "in front of the pad")
	var low: PackedFloat32Array = _box(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0), Vector3(0.3, 0.05, 0.3))
	var over: Array[Vector3] = [Vector3(-0.15, 0.3, 0.0), Vector3(0.15, 0.3, 0.0)]
	assert_eq(GoalieBladeCollision.resolve((over[0] + over[1]) * 0.5, over[0], over[1], HALF_THICKNESS, low),
			Vector3.ZERO, "lifted over a pad on the ice")
	assert_eq(GoalieBladeCollision.resolve(Vector3.ZERO, now[0], now[1], HALF_THICKNESS, PackedFloat32Array()),
			Vector3.ZERO, "no goalie")
