extends GutTest

# The poke check's plan (KeeperPoke): a carrier driving at him with the puck
# out in front, in his reach and in front of his goal line, he pokes, the blade
# sent to lie on the puck where it will be when the blade gets there; one out
# of reach, beside or behind him, behind the carrier's body or behind his line
# he leaves, and so a carrier skating across, stopped, gliding in or driving
# wide of him. Under way the blade is sent on after the puck from where it is,
# until the puck is pulled where it no longer lands. REACH_M culls nothing he
# could reach.

const SPEED_M_S: float = 5.0
# A skater's body, the default build's.
const BODY_R: float = 0.35
const DRIVING := 3.0
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


func _rest() -> Vector3:
	var p := KeeperPose.new()
	_motor.pose(p)
	return Vector3(p.blade_center.x, 0.0, p.blade_center.z)


# The carrier skating straight at him at DRIVING.
func _at_him(carrier: Vector2) -> Vector2:
	return (Vector2(_motor.x, _motor.z) - carrier).normalized() * DRIVING


func _lands(puck: Vector2, carrier: Vector2, mirrored: bool = false) -> bool:
	return _poke.plan(puck, _at_him(carrier), carrier, BODY_R, _motor, mirrored, SPEED_M_S)


func test_a_puck_driven_at_him_he_pokes_the_blade_onto_where_it_will_be() -> void:
	for rest: int in [R.FEET, R.DOWN]:
		_motor.rest = rest
		var puck := Vector2(-0.3, -2.6)
		var carrier := Vector2(-0.3, -3.2)
		assert_true(_lands(puck, carrier), "rest %d: in reach" % rest)
		var reach: float = _poke.reach_s
		var will_be: Vector2 = puck + _at_him(carrier) * reach
		var blade: Vector3 = _blade()
		assert_lte(Vector2(blade.x - will_be.x, blade.z - (will_be.y - _motor.z)).length(), 2.0 * KeeperPoke.ON_PUCK_M,
				"rest %d: on it where it will be" % rest)
		assert_almost_eq(reach, _rest().distance_to(_poke.target) / SPEED_M_S, 1e-5, "rest %d: at his blocker speed" % rest)


func test_one_he_cannot_get_the_blade_to_he_leaves() -> void:
	assert_false(_lands(Vector2(0.0, -3.8), Vector2(0.0, -4.4)), "out of his reach")
	assert_false(_lands(Vector2(-1.0, -0.9), Vector2(-1.6, -0.9)), "beside him")
	assert_false(_lands(Vector2(0.0, -1.15), Vector2(0.0, -1.8)), "at his feet")


func test_one_held_behind_the_carriers_body_he_leaves() -> void:
	assert_false(_lands(Vector2(0.0, -2.6), Vector2(0.0, -2.2)), "the body between")
	assert_false(_lands(Vector2(0.0, -2.6), Vector2(0.0, -2.6 - 0.5 * BODY_R)), "inside the body, among the skates")


func test_one_behind_his_goal_line_he_leaves() -> void:
	_motor.z = -0.3
	_motor.yaw = PI * 0.5
	assert_false(_lands(Vector2(-1.4, 0.1), Vector2(-2.0, 0.2)), "behind the line")
	assert_true(_lands(Vector2(-1.4, -0.3), Vector2(-2.0, -0.3)), "the same in front of it")


# Only a carrier driving at him: not one skating across, stopped, gliding in
# slower than DRIVING_M_S, or driving on a line wide of his reach.
func test_only_a_carrier_driving_at_him() -> void:
	var puck := Vector2(-0.3, -2.6)
	var carrier := Vector2(-0.3, -3.2)
	assert_false(_poke.plan(puck, Vector2(DRIVING, 0.0), carrier, BODY_R, _motor, false, SPEED_M_S), "skating across")
	assert_false(_poke.plan(puck, Vector2.ZERO, carrier, BODY_R, _motor, false, SPEED_M_S), "stopped")
	assert_false(_poke.plan(puck, _at_him(carrier).normalized() * (KeeperPoke.DRIVING_M_S - 0.5), carrier, BODY_R, _motor,
			false, SPEED_M_S), "gliding in")
	assert_false(_poke.plan(Vector2(-2.6, -2.6), Vector2(0.0, DRIVING), Vector2(-2.6, -3.2), BODY_R, _motor, false, SPEED_M_S),
			"driving down the wing, wide of him")


func test_a_right_catcher_pokes_the_mirror() -> void:
	assert_true(_lands(Vector2(-0.4, -2.6), Vector2(-0.4, -3.2)), "left-catching")
	var left: Vector3 = _poke.target
	assert_true(_lands(Vector2(0.4, -2.6), Vector2(0.4, -3.2), true), "right-catching, mirrored")
	assert_almost_eq(_poke.target, left, Vector3.ONE * 1e-5, "the same poke in his space")


# Under way, the blade is sent from where it is onto the puck as now read; a
# puck pulled back behind the carrier's body no longer lands.
func test_under_way_the_blade_follows_the_puck_until_it_is_pulled() -> void:
	var carrier := Vector2(-0.5, -3.2)
	var motion: Vector2 = _at_him(carrier)
	var blade := Vector3(0.1, 0.0, -1.2)
	assert_true(_poke.track(Vector2(-0.6, -2.6), motion, carrier, BODY_R, _motor, false, SPEED_M_S, blade), "followed")
	assert_almost_eq(_poke.reach_s, blade.distance_to(_poke.target) / SPEED_M_S, 1e-5, "from where the blade is")
	assert_lt(_blade().x, -0.3, "across to it")
	assert_false(_poke.track(Vector2(-0.5, -3.7), motion, carrier, BODY_R, _motor, false, SPEED_M_S, blade),
			"pulled behind the body")


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
