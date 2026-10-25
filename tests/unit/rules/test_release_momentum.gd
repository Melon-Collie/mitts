extends GutTest

# ReleaseMomentum — the puck leaves with the skater's motion, corrected by the
# hands onto the aim. The aim is −Z throughout.

const AIM := Vector3(0.0, 0.0, -1.0)
const AT_IT := Vector3(0.0, 0.0, -8.0)
const ACROSS := Vector3(8.0, 0.0, 0.0)
const AWAY := Vector3(0.0, 0.0, 8.0)


func _r(power: float, skater: Vector3, direction: Vector3 = AIM) -> Vector3:
	return ReleaseMomentum.release_velocity(direction, power, skater)


func test_standing_still_is_the_push_alone() -> void:
	var lofted := Vector3(0.0, 0.3, -1.0).normalized()
	assert_almost_eq(_r(33.0, Vector3.ZERO, lofted).distance_to(lofted * 33.0), 0.0, 0.0001)


func test_skating_into_the_shot_adds_the_pace() -> void:
	var r := _r(33.0, AT_IT)
	assert_almost_eq(r.length(), 41.0, 0.001)
	assert_almost_eq(r.normalized().dot(AIM), 1.0, 0.0001)


func test_skating_away_from_the_shot_takes_it() -> void:
	assert_almost_eq(_r(33.0, AWAY).length(), 25.0, 0.001)


func test_the_hands_cancel_the_motion_across_the_aim() -> void:
	var r := _r(33.0, ACROSS)
	assert_almost_eq(r.normalized().dot(AIM), 1.0, 0.0001, "still exactly on the cursor")
	assert_almost_eq(r.length(), sqrt(33.0 * 33.0 - 64.0), 0.001, "at the push's cost")
	assert_almost_eq(_r(14.0, ACROSS).length(), sqrt(14.0 * 14.0 - 64.0), 0.001,
			"a soft feed pays far more of itself")


func test_a_push_too_weak_to_cancel_the_motion_drifts() -> void:
	var r := _r(5.0, ACROSS)
	assert_almost_eq(r.z, 0.0, 0.0001, "nothing left to drive along the aim")
	assert_almost_eq(r.x, 3.0, 0.0001, "the motion the push could not cancel")


func test_a_blade_can_always_leave_the_puck_behind() -> void:
	assert_almost_eq(_r(5.0, AWAY).length(), 0.0, 0.0001, "a drop pass: left at rest")
	assert_almost_eq(_r(0.0, AWAY).length(), 0.0, 0.0001)


func test_the_launch_angle_is_kept() -> void:
	var lofted := Vector3(0.0, 0.25, -1.0).normalized()
	for skater: Vector3 in [AT_IT, ACROSS, AWAY, Vector3(-5.0, 0.0, -3.0)]:
		var r := _r(30.0, skater, lofted)
		assert_almost_eq(r.y / Vector2(r.x, r.z).length(), 0.25, 0.0001, str(skater))


func test_a_pass_keeps_its_vertical_launch_speed() -> void:
	var saucer := Vector3(0.0, 0.2, -1.0).normalized()
	var vy: float = 14.0 * saucer.y
	for skater: Vector3 in [AT_IT, ACROSS, Vector3(-5.0, 0.0, -3.0)]:
		var r: Vector3 = ReleaseMomentum.release_velocity(saucer, 14.0, skater, true)
		assert_almost_eq(r.y, vy, 0.0001, str(skater))


func test_a_pass_left_behind_never_rises_past_the_host_check() -> void:
	var flip := Vector3(0.0, 0.5, -1.0).normalized()
	for push: float in [0.0, 3.0, 8.5, 9.0]:
		var r: Vector3 = ReleaseMomentum.release_velocity(flip, push, AWAY, true)
		if r.length() > 0.0001:
			assert_almost_eq(ShotReleaseRules.sanitize_direction(r).distance_to(r.normalized()),
					0.0, 0.0001, "push %.1f" % push)
		else:
			assert_almost_eq(r.length(), 0.0, 0.0001, "push %.1f: left at rest" % push)


func test_push_for_pace_inverts_the_release() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	for i: int in 200:
		var aim := Vector2.from_angle(rng.randf() * TAU)
		var skater := Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-10.0, 10.0))
		var pace: float = rng.randf_range(5.0, 35.0)
		var push: float = ReleaseMomentum.push_for_pace(pace, aim, skater)
		var r := _r(push, skater, Vector3(aim.x, 0.0, aim.y))
		var v_par: float = Vector2(skater.x, skater.z).dot(aim)
		if pace <= v_par:
			assert_eq(push, 0.0, "case %d: the body already carries it" % i)
		else:
			assert_almost_eq(Vector2(r.x, r.z).dot(aim), pace, 0.001, "case %d" % i)
			assert_almost_eq(r.length(), pace, 0.001, "case %d: no drift" % i)


func test_the_floor_is_a_pace_on_the_ice() -> void:
	var lofted := Vector3(0.0, 0.3, -1.0).normalized()
	for direction: Vector3 in [AIM, lofted]:
		assert_almost_eq(ReleaseMomentum.floor_push(10.0, direction, Vector3.ZERO), 10.0, 0.0001,
				"standing, the floor is the push")
		var push: float = ReleaseMomentum.floor_push(10.0, direction, AT_IT)
		assert_lt(push, 10.0, "skating at the target, the hands cushion it")
		assert_almost_eq(_r(push, AT_IT, direction).length(), 10.0, 0.001,
				"and the softest touch still lands at the standing floor")
	assert_almost_eq(ReleaseMomentum.floor_push(10.0, AIM, AWAY), 10.0, 0.0001,
			"skating away, no harder push comes free")
	assert_almost_eq(ReleaseMomentum.floor_push(10.0, AIM, Vector3(0.0, 0.0, -12.0)), 0.0, 0.0001,
			"outskating the floor, the softest release is the puck left with the body's pace")

