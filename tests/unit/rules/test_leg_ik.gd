extends GutTest

# The leg solve and its inverse agree everywhere the gait poses a leg, and out of
# reach it points the leg at the target rather than failing.

const THIGH: float = 0.31
const SHIN: float = 0.45

var _leg := LegIK.Leg.new()


func _place(pitch: float, yaw: float, roll: float, knee: float) -> void:
	_leg.pitch = pitch
	_leg.yaw = yaw
	_leg.roll = roll
	_leg.knee = knee
	LegIK.place(_leg, THIGH, SHIN)


func _solve(x: float, y: float, z: float, yaw: float) -> void:
	_leg.x = x
	_leg.y = y
	_leg.z = z
	_leg.yaw = yaw
	_leg.pitch = 0.0
	_leg.roll = 0.0
	_leg.knee = 0.0
	LegIK.solve(_leg, THIGH, SHIN)


func test_the_solve_returns_the_joints_that_placed_the_ankle() -> void:
	var worst: float = 0.0
	for pitch: float in [-1.2, -0.6, -0.1, 0.0, 0.3, 0.9, 1.3]:
		for yaw: float in [-0.8, 0.0, 0.35]:
			for roll: float in [-0.7, -0.2, 0.0, 0.15, 0.6]:
				for knee: float in [-2.0, -1.4, -0.7, -0.25, -0.05, 0.0]:
					_place(pitch, yaw, roll, knee)
					_solve(_leg.x, _leg.y, _leg.z, yaw)
					worst = maxf(worst, maxf(absf(_leg.pitch - pitch),
							maxf(absf(_leg.roll - roll), absf(_leg.knee - knee))))
	assert_lt(worst, 1e-6, "worst joint error %.9f rad" % worst)


func test_a_solved_leg_reaches_its_target() -> void:
	for target: Vector3 in [Vector3(0.0, -0.6, 0.0), Vector3(0.2, -0.5, -0.25),
			Vector3(-0.3, -0.45, 0.2), Vector3(0.05, -0.3, -0.4)]:
		_solve(target.x, target.y, target.z, 0.4)
		LegIK.place(_leg, THIGH, SHIN)
		assert_almost_eq(Vector3(_leg.x, _leg.y, _leg.z), target, Vector3.ONE * 1e-6,
				"target %s" % target)
		assert_lte(_leg.knee, 0.0, "the knee folds back")


func test_out_of_reach_the_leg_points_straight_at_the_target() -> void:
	var target := Vector3(0.3, -1.5, -0.4)
	_solve(target.x, target.y, target.z, 0.0)
	assert_almost_eq(_leg.knee, 0.0, 1e-9, "straight")
	LegIK.place(_leg, THIGH, SHIN)
	var ankle := Vector3(_leg.x, _leg.y, _leg.z)
	assert_almost_eq(ankle.length(), THIGH + SHIN, 1e-6)
	assert_almost_eq(ankle.normalized().dot(target.normalized()), 1.0, 1e-6)


func test_too_near_the_leg_folds_shut_toward_the_target() -> void:
	_solve(0.0, -0.05, 0.1, 0.0)
	assert_almost_eq(_leg.knee, -PI, 1e-9)
	LegIK.place(_leg, THIGH, SHIN)
	assert_almost_eq(Vector3(_leg.x, _leg.y, _leg.z).normalized(),
			Vector3(0.0, -0.05, 0.1).normalized(), Vector3.ONE * 1e-6)
