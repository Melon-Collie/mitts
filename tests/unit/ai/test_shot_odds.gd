extends GutTest

# Properties of AIShotOdds that hold whatever the measured field says.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z


func _keeper_at(goal: Vector3, x: float, depth: float) -> Vector3:
	return Vector3(x, 0.0, goal.z - signf(goal.z) * depth)


func test_odds_are_probabilities_across_the_zone() -> void:
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	for fwd: float in [0.5, 2.0, 5.0, 9.0, 14.0, 20.0]:
		for x: float in [-9.0, -4.0, 0.0, 4.0, 9.0]:
			var release := Vector3(x, 0.0, GOAL_Z + fwd)
			for kx: float in [-0.8, 0.0, 0.8]:
				var k: Vector3 = _keeper_at(goal, kx, 1.5)
				var now: float = AIShotOdds.shot_now(release, goal, k, kx * 2.0, AIShotOdds.Stance.UPRIGHT)
				assert_between(now, 0.0, 1.0, "shot_now at (%.1f, %.1f)" % [x, fwd])
				var fed: float = AIShotOdds.feed(release + Vector3(4.0, 0.0, 0.0), release,
						15.0, goal, k, true)
				assert_between(fed, 0.0, 1.0, "feed at (%.1f, %.1f)" % [x, fwd])


func test_no_shot_from_on_or_behind_the_goal_line() -> void:
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var k: Vector3 = _keeper_at(goal, 0.0, 1.0)
	for x: float in [-2.0, 0.0, 2.0]:
		for behind: float in [0.0, 1.0, 3.0]:
			var release := Vector3(x, 0.0, GOAL_Z - behind)
			assert_eq(AIShotOdds.shot_now(release, goal, k, 0.0, AIShotOdds.Stance.UPRIGHT), 0.0)
			assert_eq(AIShotOdds.feed(Vector3(0.0, 0.0, GOAL_Z + 6.0), release, 15.0, goal, k,
					false), 0.0)


func test_the_far_net_reads_as_the_measured_net_seen_from_the_other_end() -> void:
	# The field was measured at the -Z net. A query at the +Z net is the same
	# situation turned through 180°: x and z both flip, and the keeper's motion
	# with them.
	var near := Vector3(0.0, 0.0, GOAL_Z)
	var far := Vector3(0.0, 0.0, -GOAL_Z)
	for release_x: float in [-5.0, -1.5, 2.0, 6.0]:
		for fwd: float in [3.0, 6.5, 10.0]:
			var r_near := Vector3(release_x, 0.0, GOAL_Z + fwd)
			var r_far := Vector3(-release_x, 0.0, -GOAL_Z - fwd)
			var k_near: Vector3 = _keeper_at(near, 0.4, 1.4)
			var k_far: Vector3 = _keeper_at(far, -0.4, 1.4)
			assert_almost_eq(AIShotOdds.shot_now(r_far, far, k_far, -1.5, AIShotOdds.Stance.UPRIGHT),
					AIShotOdds.shot_now(r_near, near, k_near, 1.5, AIShotOdds.Stance.UPRIGHT), 1e-5,
					"shot_now mirrors at (%.1f, %.1f)" % [release_x, fwd])
			var yaw: float = PI - 0.5
			assert_almost_eq(
					AIShotOdds.shot_now(r_far, far, k_far, -1.5, AIShotOdds.Stance.UPRIGHT,
							yaw + PI),
					AIShotOdds.shot_now(r_near, near, k_near, 1.5, AIShotOdds.Stance.UPRIGHT,
							yaw), 1e-5,
					"shot_now with a facing mirrors at (%.1f, %.1f)" % [release_x, fwd])
			var p_near := Vector3(release_x + 3.0, 0.0, GOAL_Z + fwd + 2.0)
			var p_far := Vector3(-release_x - 3.0, 0.0, -GOAL_Z - fwd - 2.0)
			assert_almost_eq(AIShotOdds.feed(p_far, r_far, 16.0, far, k_far, true),
					AIShotOdds.feed(p_near, r_near, 16.0, near, k_near, true), 1e-5,
					"feed mirrors at (%.1f, %.1f)" % [release_x, fwd])


func test_a_set_keeper_reads_the_measured_set_cell() -> void:
	# "Square and set on it" is a measured situation, so at every measured spot
	# the set read IS that spot's SET cell.
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	AIShotOdds.shot_set(Vector3(0.0, 0.0, GOAL_Z + 6.0), goal)
	for fwd: float in AIShotFieldData.SPOT_FWD:
		for x: float in AIShotFieldData.SPOT_X:
			var spot: int = AIShotFieldData.SPOT_FWD.find(fwd) * AIShotFieldData.SPOT_X.size() \
					+ AIShotFieldData.SPOT_X.find(x)
			assert_almost_eq(AIShotOdds.shot_set(Vector3(x, 0.0, GOAL_Z + fwd), goal),
					AIShotOdds._odds[AIShotOdds._set_cell[spot]], 1e-6,
					"the set read at (%.1f, %.1f) is the SET cell" % [x, fwd])


func test_the_set_cells_read_square_on_the_shot() -> void:
	# squareness() and the generator's reads share a facing convention: a keeper
	# settled on the carrier faces him. Off the goal-line row, where he sets on
	# the post rather than square, every SET cell reads within a few degrees.
	AIShotOdds.shot_set(Vector3(0.0, 0.0, GOAL_Z + 6.0), Vector3(0.0, 0.0, GOAL_Z))
	for spot: int in AIShotOdds._set_cell.size():
		if AIShotFieldData.SPOT_FWD[spot / AIShotFieldData.SPOT_X.size()] \
				< AIShotFieldData.SPOT_FWD[1]:
			continue
		var c: int = AIShotOdds._set_cell[spot]
		assert_lt(absf(AIShotOdds._square[c]), deg_to_rad(3.0),
				"SET cell %d faces the shot" % c)
