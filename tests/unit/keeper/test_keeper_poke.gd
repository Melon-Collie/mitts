extends GutTest

# The poke check's plan (KeeperPoke): a puck out in front of its carrier, in
# his reach and in front of his goal line, he pokes, the blade sent to lie on
# it where it will be when the blade gets there; one out of reach, beside or
# behind him, behind the carrier's body or behind his line he leaves. REACH_M
# culls nothing he could reach.

const SPEED_M_S: float = 5.0
const BEARINGS_DEG: Array[float] = [-90.0, -80.0, -70.0, -60.0, -50.0, -40.0, -30.0, -20.0, -10.0, 0.0, 10.0,
		20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0]
const R := KeeperRoute.Rest

var _motor: KeeperMotor = null
var _poke: KeeperPoke = null
var _skel := KeeperSkeleton.new()
var _pose := KeeperPose.new()


func before_each() -> void:
	_motor = KeeperMotor.new()
	_motor.z = -1.0
	_poke = KeeperPoke.new()


# Where the blade lies with its centre sent to the plan's target, his space.
func _blade() -> Vector3:
	_motor.pose(_pose)
	_pose.blade_center = _poke.target
	_skel.pose(_pose)
	return KeeperGear.box(_skel, KeeperGear.Part.BLADE).origin


func _lands(puck: Vector2, carrier: Vector2, motion: Vector2 = Vector2.ZERO, mirrored: bool = false) -> bool:
	return _poke.plan(puck, motion, carrier, _motor, mirrored, SPEED_M_S)


func test_a_puck_out_in_front_of_its_carrier_he_pokes_the_blade_onto() -> void:
	for rest: int in [R.FEET, R.DOWN]:
		_motor.rest = rest
		assert_true(_lands(Vector2(-0.3, -2.3), Vector2(-0.3, -2.9)), "rest %d: in reach" % rest)
		var blade: Vector3 = _blade()
		assert_lte(Vector2(blade.x + 0.3, blade.z + 1.3).length(), KeeperPoke.ON_PUCK_M, "rest %d: on it" % rest)
		assert_almost_eq(_poke.reach_s, Vector3(_pose_rest().x, 0.0, _pose_rest().z).distance_to(_poke.target)
				/ SPEED_M_S, 1e-5, "rest %d: at his blocker speed" % rest)


func _pose_rest() -> Vector3:
	var p := KeeperPose.new()
	_motor.pose(p)
	return p.blade_center


func test_one_he_cannot_get_the_blade_to_he_leaves() -> void:
	assert_false(_lands(Vector2(0.0, -3.4), Vector2(0.0, -4.0)), "out of his reach")
	assert_false(_lands(Vector2(-1.0, -0.9), Vector2(-1.6, -0.9)), "beside him")
	assert_false(_lands(Vector2(0.0, -1.15), Vector2(0.0, -1.8)), "at his feet")


func test_one_held_behind_the_carriers_body_he_leaves() -> void:
	assert_false(_lands(Vector2(0.0, -2.3), Vector2(0.0, -1.9)), "the body between")


func test_one_behind_his_goal_line_he_leaves() -> void:
	_motor.z = -0.3
	_motor.yaw = PI * 0.5
	assert_false(_lands(Vector2(-1.2, 0.1), Vector2(-1.8, 0.2)), "behind the line")
	assert_true(_lands(Vector2(-1.2, -0.3), Vector2(-1.8, -0.3)), "the same in front of it")


# A carrier skating across: the blade is sent where the puck will be when it
# gets there.
func test_a_moving_puck_is_poked_where_it_will_be() -> void:
	var motion := Vector2(2.0, 0.0)
	assert_true(_lands(Vector2(-0.6, -2.3), Vector2(-0.6, -2.9), motion), "skating across")
	var blade: Vector3 = _blade()
	assert_almost_eq(blade.x, -0.6 + motion.x * _poke.reach_s, 2.0 * KeeperPoke.ON_PUCK_M, "led by its skating")


func test_a_right_catcher_pokes_the_mirror() -> void:
	assert_true(_lands(Vector2(-0.4, -2.3), Vector2(-0.4, -2.9)), "left-catching")
	var left: Vector3 = _poke.target
	assert_true(_lands(Vector2(0.4, -2.3), Vector2(0.4, -2.9), Vector2.ZERO, true), "right-catching, mirrored")
	assert_almost_eq(_poke.target, left, Vector3.ONE * 1e-5, "the same poke in his space")


# Standing or down, no aim of his stick at REACH_M or further lies on the puck
# on the ice, whichever way ahead of him; straight ahead short of it, one does.
func test_reach_culls_nothing_he_could_reach() -> void:
	for rest: int in [R.FEET, R.DOWN]:
		_motor.rest = rest
		_poke.pose_from(_motor)
		for deg: float in BEARINGS_DEG:
			var b: float = deg_to_rad(deg)
			for d: float in [KeeperPoke.REACH_M, KeeperPoke.REACH_M + 0.2, KeeperPoke.REACH_M + 0.5]:
				assert_false(_poke.aim(Vector3(sin(b) * d, 0.0, -cos(b) * d)), "rest %d, %.0f°, %.1f m" % [rest, deg, d])
		assert_true(_poke.aim(Vector3(0.0, 0.0, -1.5)), "rest %d: straight ahead, 1.5 m" % rest)
