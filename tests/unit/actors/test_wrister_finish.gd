extends "res://tests/harness/body_jerk_harness.gd"

# A wrister let go at speed, where the body leans well forward and the chest is
# still folded over the stick it carried: the finish hangs from the shoulder
# the body is drawn with and is posed level, so the lean neither folds the top
# arm shut under the chest nor takes the blade off the height it was given.

const SCENARIO: String = "wrister: carry, charge, release, skating"
const RELEASE_TICK: int = 120
# Past the finish, into the tracked stick taking it back.
const END_TICK: int = 190
const EPS_M: float = 0.01


# The scenario skated with the cursor on `side` (the sign of x), sampled each
# tick of the follow-through: the smallest (hand to its drawn shoulder, blade
# over the ice) and the largest blade lift, as Vector3(reach, low, high).
func _finish(side: float) -> Vector3:
	var steer: Callable
	for s: Dictionary in scenarios():
		if String(s["name"]) == SCENARIO:
			steer = s["steer"]
			_rig(s["start_z"])
	var input := InputState.new()
	var worst := Vector3(INF, INF, -INF)
	for i: int in range(-SETTLE_TICKS, END_TICK):
		input.delta = DT
		input.host_timestamp += DT
		var aim: Vector3 = steer.call(input, i)
		aim.x = absf(aim.x) * side
		input.mouse_world_pos = _skater.global_position + aim
		input.mouse_world_pos.y = 0.0
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)
		if _controller.get_shot_state() != SkaterStateMachine.State.FOLLOW_THROUGH:
			continue
		var shoulder: Vector3 = _skater.visible_shoulder(_skater.shoulder.position)
		var lift: float = _skater.upper_body_to_global(_skater.get_blade_position()).y \
				- _controller.blade_height
		worst.x = minf(worst.x, shoulder.distance_to(_skater.get_top_hand_position()))
		worst.y = minf(worst.y, lift)
		worst.z = maxf(worst.z, lift)
	return worst


func test_the_top_hand_stays_off_its_shoulder() -> void:
	for side: float in [-1.0, 1.0]:
		var worst: Vector3 = _finish(side)
		assert_gt(worst.x, _skater.forearm_length,
				"cursor side %+.0f: a hand inside a forearm of its shoulder is an arm folded shut (%.2f m)"
				% [side, worst.x])


func test_the_blade_stays_over_the_ice() -> void:
	for side: float in [-1.0, 1.0]:
		var worst: Vector3 = _finish(side)
		assert_gt(worst.y, -EPS_M, "cursor side %+.0f: %.3f m under it" % [side, -worst.y])


func test_the_blade_rises_to_its_finish() -> void:
	for side: float in [-1.0, 1.0]:
		var worst: Vector3 = _finish(side)
		var high: float = _controller.wrister_follow_through_blade_lift \
				* _controller._sm.follow_through_power
		assert_almost_eq(worst.z, high, EPS_M,
				"cursor side %+.0f: the blade's high point is the finish's own" % side)
