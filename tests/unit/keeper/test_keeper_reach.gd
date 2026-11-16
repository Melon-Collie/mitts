extends GutTest

# Whether he reaches a pad out for a puck wide of him before it is shot
# (KeeperReach): not for one in front of him, which the butterfly shuts; for
# one carried well wide, toward its side, where the extension shows it less of
# the low net; held where it began; the same whichever way he is turned and
# wherever he is; and a right-catcher the left-catcher reflected.

var _reach: KeeperReach = null
var _motor: KeeperMotor = null


func before_each() -> void:
	_reach = KeeperReach.new()
	_motor = KeeperMotor.new()
	_motor.z = -1.1
	_motor.rest = KeeperRoute.Rest.DOWN


func test_a_puck_in_front_of_him_he_does_not_reach_for() -> void:
	for x: float in [0.0, 0.3, -0.3, 0.5]:
		assert_eq(_reach.plan(Vector2(x, -2.4), _motor, false, 0.0), 0.0, "puck %+.1f across" % x)


func test_a_puck_carried_wide_he_reaches_toward() -> void:
	for side: float in [1.0, -1.0]:
		var reached: bool = false
		for wide: float in [1.2, 1.4, 1.6, 1.8]:
			var to: float = _reach.plan(Vector2(side * wide, -2.2), _motor, false, 0.0)
			assert_true(to == 0.0 or to == side, "%+.0f, %.1f m wide: toward the puck or not at all" % [side, wide])
			reached = reached or to == side
		assert_true(reached, "%+.0f: somewhere out wide the pad goes out" % side)


func test_out_he_holds_it_where_it_began() -> void:
	for wide: float in [0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0]:
		var puck := Vector2(wide, -2.2)
		if _reach.plan(puck, _motor, false, 0.0) == 1.0:
			assert_eq(_reach.plan(puck, _motor, false, 1.0), 1.0, "%.1f m wide: held" % wide)
		assert_ne(_reach.plan(puck, _motor, false, -1.0), -1.0, "%.1f m wide: never held away from the puck" % wide)


func test_it_is_his_own_frame_that_counts() -> void:
	var puck := Vector2(1.5, -2.2)
	var square: float = _reach.plan(puck, _motor, false, 0.0)
	# The same picture moved across and back: the puck, him and the net together.
	_motor.x = 0.0
	for yaw: float in [0.3, -0.4]:
		_motor.yaw = yaw
		var from_side: float = _reach.plan(puck, _motor, false, 0.0)
		assert_true(from_side == 0.0 or from_side == signf((Basis(Vector3.UP, yaw).inverse()
				* Vector3(puck.x - _motor.x, 0.0, puck.y - _motor.z)).x), "turned %.1f: toward the puck as he is turned" % yaw)
	_motor.yaw = 0.0
	assert_eq(_reach.plan(puck, _motor, false, 0.0), square, "the same asked twice")


func test_a_right_catcher_is_the_left_catcher_reflected() -> void:
	for wide: float in [0.4, 1.0, 1.4, 1.8]:
		for side: float in [1.0, -1.0]:
			var left: float = _reach.plan(Vector2(side * wide, -2.2), _motor, false, 0.0)
			var right: float = KeeperReach.new().plan(Vector2(-side * wide, -2.2), _motor, true, 0.0)
			assert_eq(right, -left, "puck %+.1f across" % (side * wide))
	assert_eq(KeeperReach.own_side(1.0, false), 1.0)
	assert_eq(KeeperReach.own_side(1.0, true), -1.0, "keeper space's +x is a right-catcher's glove side")
