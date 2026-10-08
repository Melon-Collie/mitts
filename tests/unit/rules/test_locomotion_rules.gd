extends GutTest

# The state mix is the physics' own decision, so each case below is one the
# movement model resolves a particular way; the mix has to agree with it, and
# its weights have to be a crossfade (sum to 1).

const UP_ICE := Vector2(0.0, -1.0)   # travelling −Z, facing −Z
const RIGHT := Vector2(1.0, 0.0)     # the traveller's right when going −Z
const ALIGN: float = deg_to_rad(30.0)

var _mix := LocomotionRules.Mix.new()


func _classify(vel: Vector2, intent: Vector2, brake: bool = false,
		facing: Vector2 = UP_ICE) -> LocomotionRules.Mix:
	LocomotionRules.classify(vel, intent, brake, facing, ALIGN, _mix)
	assert_almost_eq(_total(_mix), 1.0, 1e-5, "the weights are a crossfade")
	return _mix


func _total(m: LocomotionRules.Mix) -> float:
	return m.glide + m.stride + m.crossover + m.backward + m.shuffle + m.skid + m.tight + m.stop


func test_stick_along_travel_is_a_stride() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, UP_ICE).stride, 1.0, 1e-5)


func test_no_stick_at_speed_is_a_glide() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, Vector2.ZERO).glide, 1.0, 1e-5)


func test_stick_across_travel_is_a_crossover_on_that_side() -> void:
	var m := _classify(UP_ICE * 6.0, RIGHT)
	assert_almost_eq(m.crossover, 1.0, 1e-5)
	assert_eq(m.side, 1.0, "turning toward the traveller's right")
	assert_eq(_classify(UP_ICE * 6.0, -RIGHT).side, -1.0)


# Between the pure cases the split is the physics' own resolution of the stick:
# cos² along, sin² across.
func test_a_diagonal_stick_splits_stride_and_crossover() -> void:
	var m := _classify(UP_ICE * 6.0, (UP_ICE + RIGHT).normalized())
	assert_almost_eq(m.stride, 0.5, 1e-5)
	assert_almost_eq(m.crossover, 0.5, 1e-5)


func test_stick_against_travel_is_a_skid() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, -UP_ICE).skid, 1.0, 1e-5)


func test_brake_in_line_is_a_stop_and_off_line_a_tight_turn() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, Vector2.ZERO, true).stop, 1.0, 1e-5)
	var m := _classify(UP_ICE * 6.0, RIGHT, true)
	assert_almost_eq(m.tight, 1.0, 1e-5)
	assert_eq(m.side, 1.0)
	# The stick behind you while braking is a stop again (the physics' taper).
	assert_almost_eq(_classify(UP_ICE * 6.0, -UP_ICE, true).stop, 1.0, 1e-5)


func test_travel_behind_the_facing_is_backward_skating() -> void:
	var facing_back := -UP_ICE
	assert_almost_eq(_classify(UP_ICE * 6.0, UP_ICE, false, facing_back).backward, 1.0, 1e-5)
	# A backward turn stays in the C-cuts.
	assert_almost_eq(_classify(UP_ICE * 6.0, RIGHT, false, facing_back).backward, 1.0, 1e-5)


func test_from_a_standstill_the_stick_against_the_body_decides() -> void:
	assert_almost_eq(_classify(Vector2.ZERO, UP_ICE).stride, 1.0, 1e-5, "a start")
	var m := _classify(Vector2.ZERO, RIGHT)
	assert_almost_eq(m.shuffle, 1.0, 1e-5, "a side-step")
	assert_eq(m.side, 1.0)
	assert_almost_eq(_classify(Vector2.ZERO, -UP_ICE).backward, 1.0, 1e-5, "a backward push")
	assert_almost_eq(_classify(Vector2.ZERO, Vector2.ZERO).glide, 1.0, 1e-5, "standing")
