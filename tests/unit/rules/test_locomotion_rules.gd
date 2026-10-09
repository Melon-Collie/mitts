extends GutTest

# The state mix is what the physics is doing: whether it is driving (the stick's
# component along travel, as SkaterMovementRules thrusts by) and the share of
# the edge's grip the travel's curve is using. Each case is one the movement
# model resolves a particular way; the mix has to agree with it, and its weights
# have to be a crossfade (sum to 1).

const UP_ICE := Vector2(0.0, -1.0)   # travelling −Z, facing −Z
const RIGHT := Vector2(1.0, 0.0)     # the traveller's right when going −Z
const DIAGONAL := Vector2(0.70710678, -0.70710678)  # 45° right of up-ice

var _mix := LocomotionRules.Mix.new()


func _classify(vel: Vector2, intent: Vector2, turning: float = 0.0, brake: bool = false,
		facing: Vector2 = UP_ICE, stance: bool = false) -> LocomotionRules.Mix:
	LocomotionRules.classify(vel, intent, brake, stance, facing, turning, _mix)
	assert_almost_eq(_total(_mix), 1.0, 1e-5, "the weights are a crossfade")
	return _mix


func _total(m: LocomotionRules.Mix) -> float:
	return m.glide + m.stride + m.crossover + m.carve + m.backward + m.shuffle + m.skid \
			+ m.tight + m.stop


func test_driving_straight_is_a_stride() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, UP_ICE).stride, 1.0, 1e-5)


func test_no_stick_at_speed_is_a_glide() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, Vector2.ZERO).glide, 1.0, 1e-5)


# The weights say whether the skater pushes, not how hard: from half the thrust
# up he is striding, and only a light touch eases toward the glide.
func test_a_light_stick_eases_toward_the_glide() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, UP_ICE * LocomotionRules.DRIVE_FULL).stride,
			1.0, 1e-5, "half the thrust is a push")
	var m := _classify(UP_ICE * 6.0, UP_ICE * LocomotionRules.DRIVE_FULL * 0.5)
	assert_almost_eq(m.stride, 0.5, 1e-5)
	assert_almost_eq(m.glide, 0.5, 1e-5)


# A diagonal stick turns at the full edge rate AND thrusts by its cosine (71%):
# a driven arc, skated with crossovers.
func test_driving_through_a_turn_is_a_crossover() -> void:
	var m := _classify(UP_ICE * 6.0, DIAGONAL, 1.0)
	assert_almost_eq(m.crossover, 1.0, 1e-5)
	assert_almost_eq(m.carve, 0.0, 1e-5)
	assert_eq(m.side, 1.0, "turning toward the traveller's right")
	assert_eq(_classify(UP_ICE * 6.0, Vector2(-DIAGONAL.x, DIAGONAL.y), 1.0).side, -1.0)


# A stick across travel turns the skater with no thrust at all: he coasts round
# on his edges, which is a carve, never a crossover (power strokes while not
# pushing).
func test_turning_without_driving_is_a_carve() -> void:
	var m := _classify(UP_ICE * 6.0, RIGHT, 1.0)
	assert_almost_eq(m.carve, 1.0, 1e-5)
	assert_almost_eq(m.crossover, 0.0, 1e-5)


# What decides "turning" is the curve the travel is actually on, not the stick:
# the instant a stick goes across travel, nothing has curved yet.
func test_a_stick_off_travel_is_not_a_turn_until_the_travel_curves() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, RIGHT, 0.0).glide, 1.0, 1e-5)
	assert_almost_eq(_classify(UP_ICE * 6.0, DIAGONAL, 0.0).stride, 1.0, 1e-5)


# Between straight and full lock the turning share splits the push into stride
# and crossover, and the coast into glide and carve.
func test_the_turning_share_splits_push_and_coast() -> void:
	var stick: Vector2 = UP_ICE * LocomotionRules.DRIVE_FULL * 0.5
	var m := _classify(UP_ICE * 6.0, stick, 0.25)
	assert_almost_eq(m.stride, 0.5 * 0.75, 1e-5)
	assert_almost_eq(m.crossover, 0.5 * 0.25, 1e-5)
	assert_almost_eq(m.glide, 0.5 * 0.75, 1e-5)
	assert_almost_eq(m.carve, 0.5 * 0.25, 1e-5)


func test_stick_against_travel_is_a_skid() -> void:
	assert_almost_eq(_classify(UP_ICE * 6.0, -UP_ICE).skid, 1.0, 1e-5)


func test_the_brake_is_a_stop_whatever_the_stick_says() -> void:
	for stick: Vector2 in [Vector2.ZERO, UP_ICE, RIGHT, DIAGONAL, -UP_ICE]:
		assert_almost_eq(_classify(UP_ICE * 6.0, stick, 1.0, true).stop, 1.0, 1e-5,
				"stick %s" % stick)
	assert_eq(_classify(UP_ICE * 6.0, RIGHT, 0.0, true).side, 1.0,
			"the stick still picks the stop's side")


# The loaded stance skates the whole turning part with both blades dug in, where
# the upright skater crosses over or carves.
func test_the_stance_turns_on_dug_edges() -> void:
	var m := _classify(UP_ICE * 6.0, DIAGONAL, 1.0, false, UP_ICE, true)
	assert_almost_eq(m.tight, 1.0, 1e-5)
	assert_almost_eq(m.crossover, 0.0, 1e-5)
	assert_almost_eq(m.carve, 0.0, 1e-5)
	assert_eq(m.side, 1.0)
	assert_almost_eq(_classify(UP_ICE * 6.0, UP_ICE, 0.0, false, UP_ICE, true).stride, 1.0, 1e-5,
			"straight in the stance is still a stride")


func test_travel_behind_the_facing_is_backward_skating() -> void:
	var facing_back := -UP_ICE
	assert_almost_eq(_classify(UP_ICE * 6.0, UP_ICE, 0.0, false, facing_back).backward,
			1.0, 1e-5)
	# A backward turn stays in the C-cuts.
	assert_almost_eq(_classify(UP_ICE * 6.0, RIGHT, 1.0, false, facing_back).backward,
			1.0, 1e-5)


func test_from_a_standstill_the_stick_against_the_body_decides() -> void:
	assert_almost_eq(_classify(Vector2.ZERO, UP_ICE).stride, 1.0, 1e-5, "a start")
	var m := _classify(Vector2.ZERO, RIGHT)
	assert_almost_eq(m.shuffle, 1.0, 1e-5, "a side-step")
	assert_eq(m.side, 1.0)
	assert_almost_eq(_classify(Vector2.ZERO, -UP_ICE).backward, 1.0, 1e-5, "a backward push")
	assert_almost_eq(_classify(Vector2.ZERO, Vector2.ZERO).glide, 1.0, 1e-5, "standing")
