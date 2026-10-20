extends GutTest

# A harder shot finishes longer, and the extra time is all hold and settle: the
# whip still snaps out in whip_attack_time, and the slapper still comes down to
# contact in slapper_downswing_time, however long the finish runs.

class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _controller: SkaterController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 10.0)
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


func _envelope(elapsed_s: float, span_s: float) -> float:
	return SkaterShotPoseCoordinator.finish_envelope(elapsed_s / span_s, span_s,
			_controller.whip_attack_time, _controller.wrister_whip_release_frac)


func test_the_whip_snaps_out_as_fast_in_a_long_finish() -> void:
	var at_attack: float = _controller.whip_attack_time
	assert_almost_eq(_envelope(at_attack, _controller.wrister_follow_through_time_min), 1.0, 0.001,
			"a soft wrister is fully out by the end of the attack")
	assert_almost_eq(_envelope(at_attack, _controller.wrister_follow_through_time_max), 1.0, 0.001,
			"so is a hard one: a longer finish does not snap slower")
	assert_almost_eq(_envelope(at_attack * 0.5, _controller.wrister_follow_through_time_min),
			_envelope(at_attack * 0.5, _controller.wrister_follow_through_time_max), 0.001,
			"the two rise together")


func test_a_longer_finish_holds_longer() -> void:
	var soft: float = _controller.wrister_follow_through_time_min
	var hard: float = _controller.wrister_follow_through_time_max
	# Where the soft finish has fully relaxed, the hard one is still out.
	assert_almost_eq(_envelope(soft, soft), 0.0, 0.001, "the soft finish is back down")
	assert_almost_eq(_envelope(soft, hard), 1.0, 0.001, "the hard finish still holds")
	assert_almost_eq(_envelope(hard, hard), 0.0, 0.001, "and comes back down by its own end")


func test_the_slapper_finish_grows_with_the_wind_up() -> void:
	var aiming: SkaterAimingBehavior = _controller._aiming
	aiming.slapper_charge_timer = 0.0
	var none: float = _controller.slapper_follow_through_time()
	assert_almost_eq(none, _controller.slapper_follow_through_time_min, 0.0001,
			"no wind-up finishes in the minimum")
	var prev: float = none
	var full_s: float = _controller._slapper_config().max_slapper_charge_time
	for i: int in range(1, 5):
		aiming.slapper_charge_timer = full_s * i / 4.0
		var now: float = _controller.slapper_follow_through_time()
		assert_gt(now, prev, "a taller wind-up finishes longer")
		prev = now
	assert_almost_eq(prev, _controller.slapper_follow_through_time_max, 0.0001,
			"a full wind-up finishes in the maximum")


# The one-timer's hold is the blade coming down onto the puck, so the puck leaves
# on the beat the finish animation calls contact.
func test_the_one_timer_hold_is_the_downswing() -> void:
	assert_almost_eq(_controller.one_timer_retention_time, _controller.slapper_downswing_time,
			0.0001, "retention and the finish's downswing are the same beat")
