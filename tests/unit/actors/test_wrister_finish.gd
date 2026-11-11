extends "res://tests/harness/body_jerk_harness.gd"

# A wrister on the live rig, wound up and let go: the blade holds still while
# it is wound up, both hands stay on the stick from the press to the end of
# the finish, and the finish hangs from the shoulder the body is drawn with,
# posed level, so a body leaning at speed neither folds the top arm shut under
# the chest nor takes the blade off the height it was given.

const SKATING: String = "wrister: carry, charge, release, skating"
const STANDING: String = "wrister standing, cursor to the backhand"
const PRESS_TICK: int = 60
# Well past any finish, the tracked stick settled again.
const END_TICK: int = 260
const EPS_M: float = 0.01


# What one shot measured, over the ticks it was wound up and the ticks of its
# finish.
class Shot:
	# The furthest the wound-up blade strayed from where the press found it,
	# in the skater's travelling frame (m).
	var blade_strayed: float = 0.0
	# The most the bottom hand let go, 0..1.
	var let_go: float = 0.0
	# The top hand off its drawn shoulder (m): as the wind-up last held it, and
	# the nearest the finish brought it.
	var hand_held_off: float = 0.0
	var hand_off_shoulder: float = INF
	# The finish: the blade's lowest and highest over the ice (m), and the
	# least the body sat under its frame, against what it sat once the stick
	# had settled.
	var blade_low: float = INF
	var blade_high: float = -INF
	var sat_least: float = INF
	var sat_after: float = 0.0
	var power: float = 0.0


# `scenario` skated with the cursor on `side` (the sign of x).
func _shoot(scenario: String, side: float) -> Shot:
	var steer: Callable
	for s: Dictionary in scenarios():
		if String(s["name"]) == scenario:
			steer = s["steer"]
			_rig(s["start_z"])
	var input := InputState.new()
	var shot := Shot.new()
	var pressed_at := Vector3.INF
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
		var state: int = _controller.get_shot_state()
		var blade: Vector3 = _skater.upper_body_to_global(_skater.get_blade_position())
		var hand_off: float = _skater.visible_shoulder(_skater.shoulder.position) \
				.distance_to(_skater.get_top_hand_position())
		if state == SkaterStateMachine.State.WRISTER_AIM:
			shot.hand_held_off = hand_off
			var off_body: Vector3 = blade - _skater.global_position
			if pressed_at == Vector3.INF:
				pressed_at = off_body
			shot.blade_strayed = maxf(shot.blade_strayed, off_body.distance_to(pressed_at))
			shot.let_go = maxf(shot.let_go, _controller._ik._bh_release)
		elif state == SkaterStateMachine.State.FOLLOW_THROUGH:
			var lift: float = blade.y - _controller.blade_height
			shot.let_go = maxf(shot.let_go, _controller._ik._bh_release)
			shot.hand_off_shoulder = minf(shot.hand_off_shoulder, hand_off)
			shot.blade_low = minf(shot.blade_low, lift)
			shot.blade_high = maxf(shot.blade_high, lift)
			shot.sat_least = minf(shot.sat_least, _skater.body_drop_below_frame())
			shot.power = _controller._sm.follow_through_power
	shot.sat_after = _skater.body_drop_below_frame()
	return shot


func test_the_wound_up_blade_holds_still() -> void:
	for side: float in [-1.0, 1.0]:
		var shot: Shot = _shoot(SKATING, side)
		assert_lt(shot.blade_strayed, EPS_M,
				"cursor side %+.0f: the frozen blade moved %.3f m off where the press found it"
				% [side, shot.blade_strayed])


func test_both_hands_stay_on_the_stick() -> void:
	for scenario: String in [SKATING, STANDING]:
		for side: float in [-1.0, 1.0]:
			var shot: Shot = _shoot(scenario, side)
			assert_lt(shot.let_go, 0.05, "%s, cursor side %+.0f: the bottom hand let go by %.2f"
					% [scenario, side, shot.let_go])


# The finish carries the stick out from where the wind-up held it: a hand
# drawn back under its shoulder instead is an arm folded shut.
func test_the_finish_never_draws_the_top_hand_back() -> void:
	for side: float in [-1.0, 1.0]:
		var shot: Shot = _shoot(SKATING, side)
		assert_gt(shot.hand_off_shoulder, shot.hand_held_off - EPS_M,
				"cursor side %+.0f: %.2f m off its shoulder wound up, %.2f m in the finish"
				% [side, shot.hand_held_off, shot.hand_off_shoulder])


func test_the_blade_stays_over_the_ice() -> void:
	for side: float in [-1.0, 1.0]:
		var shot: Shot = _shoot(SKATING, side)
		assert_gt(shot.blade_low, -EPS_M, "cursor side %+.0f: %.3f m under it"
				% [side, -shot.blade_low])


func test_the_blade_rises_to_its_finish() -> void:
	for side: float in [-1.0, 1.0]:
		var shot: Shot = _shoot(SKATING, side)
		assert_almost_eq(shot.blade_high,
				_controller.wrister_follow_through_blade_lift * shot.power, EPS_M,
				"cursor side %+.0f: the blade's high point is the finish's own" % side)


# Standing, where the crouch is the ready stance's own: the finish does not
# stand him up and sit him down again.
func test_he_stays_down_through_the_finish() -> void:
	var shot: Shot = _shoot(STANDING, -1.0)
	assert_gt(shot.sat_after, EPS_M, "he sits to an empty stick once it has settled")
	assert_gt(shot.sat_least, shot.sat_after - EPS_M,
			"through the finish he sat %.3f m at least, against %.3f m after it"
			% [shot.sat_least, shot.sat_after])
