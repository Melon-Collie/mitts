extends GutTest

# A client's predicted goalie used to be drawn in the corrected place the frame
# a snapshot re-stepped his predictor: a pop of up to ~45 cm (#913).
# KeeperRestepEase draws him moving from what was on screen onto the corrected
# prediction instead, and snaps only a teleport or a frame drawn by something
# else.

const DT: float = 1.0 / 90.0


func _state(x: float, z: float, yaw: float = 0.0) -> GoalieNetworkState:
	var s := GoalieNetworkState.new()
	s.position_x = x
	s.position_z = z
	s.rotation_y = yaw
	return s


# The prediction walks +x at `speed`; on frame 10 it re-steps `jump` metres on.
# Returns the drawn x per frame.
func _drawn_xs(smoother: KeeperRestepEase, jump: float, speed: float, frames: int) -> Array[float]:
	var xs: Array[float] = []
	for f in range(frames):
		var x: float = speed * DT * float(f) + (jump if f >= 10 else 0.0)
		var target := _state(x, -25.0)
		var drawn: GoalieNetworkState = smoother.apply(target, f == 10, DT, f)
		smoother.note_drawn(drawn, f)
		xs.append(drawn.position_x)
	return xs


func test_a_restep_is_eased_not_popped() -> void:
	var smoother := KeeperRestepEase.new()
	var jump: float = 0.45
	var speed: float = 3.0
	var xs: Array[float] = _drawn_xs(smoother, jump, speed, 40)
	var steady: float = speed * DT
	var worst_step: float = 0.0
	for f in range(10, 40):
		worst_step = maxf(worst_step, xs[f] - xs[f - 1])
	# Smoothstep is steepest at its middle, 1.5 times its mean slope: no frame
	# carries more than that share of the jump, where the pop carried all of it.
	var peak_share: float = 1.5 * DT / KeeperRestepEase.EASE_S
	assert_lt(worst_step - steady, (jump + steady) * peak_share + 1e-4,
			"no frame carries much of the jump (worst %.3f m over the steady %.3f)" % [worst_step, steady])
	assert_lt(peak_share, 0.25, "the ease spans enough frames to matter")
	var settle: int = ceili(KeeperRestepEase.EASE_S / DT) + 1
	for f in range(10 + settle, 40):
		assert_almost_eq(xs[f], speed * DT * float(f) + jump, 1e-6, "frame %d: on the prediction" % f)


func test_he_keeps_moving_with_the_prediction_through_the_ease() -> void:
	var xs: Array[float] = _drawn_xs(KeeperRestepEase.new(), -0.3, 3.0, 20)
	for f in range(11, 20):
		var step: float = xs[f] - xs[f - 1]
		assert_gt(step, -0.3 * 0.25, "frame %d: never thrown back with the correction" % f)


func test_a_teleport_snaps() -> void:
	var xs: Array[float] = _drawn_xs(KeeperRestepEase.new(), KeeperRestepEase.SNAP_M * 2.0, 0.0, 12)
	assert_almost_eq(xs[10], KeeperRestepEase.SNAP_M * 2.0, 1e-6)


func test_nothing_on_screen_last_frame_snaps() -> void:
	var smoother := KeeperRestepEase.new()
	smoother.note_drawn(_state(0.0, -25.0), 5)
	var drawn: GoalieNetworkState = smoother.apply(_state(0.4, -25.0), true, DT, 9)
	assert_almost_eq(drawn.position_x, 0.4, 1e-6, "a replay drew him in between")


func test_his_turn_eases_the_short_way_round() -> void:
	var smoother := KeeperRestepEase.new()
	smoother.note_drawn(_state(0.0, -25.0, PI - 0.1), 0)
	var drawn: GoalieNetworkState = smoother.apply(_state(0.0, -25.0, -PI + 0.1), true, DT, 1)
	assert_lt(absf(angle_difference(drawn.rotation_y, PI)), 0.2,
			"between the two across ±π, not swung through zero")


func test_without_a_jump_he_is_the_prediction() -> void:
	var smoother := KeeperRestepEase.new()
	var target := _state(1.0, -25.0)
	assert_same(smoother.apply(target, false, DT, 0), target)
