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
	# settled on the carrier faces him. Within a couple of metres of the line he
	# sets on the post rather than square; out from there every SET cell faces
	# the shot.
	AIShotOdds.shot_set(Vector3(0.0, 0.0, GOAL_Z + 6.0), Vector3(0.0, 0.0, GOAL_Z))
	for spot: int in AIShotOdds._set_cell.size():
		if AIShotFieldData.SPOT_FWD[spot / AIShotFieldData.SPOT_X.size()] < 2.5:
			continue
		var c: int = AIShotOdds._set_cell[spot]
		assert_lt(absf(AIShotOdds._square[c]), deg_to_rad(5.0),
				"SET cell %d faces the shot" % c)


# The cells at `c`'s spot, weighed by a query with `c`'s own read; returns the
# weight on `other`.
func _weight_of(other: int, c: int, use_facing: bool) -> float:
	var t: PackedStringArray = AIShotFieldData.ROWS[c].split("\t")
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var release := Vector3(float(t[7]), 0.0, GOAL_Z + float(t[8]))
	var keeper := Vector3(float(t[30]), 0.0, float(t[31]))
	AIShotOdds.shot_now(release, goal, keeper, float(t[35]), AIShotOdds._stance[c],
			float(t[32]) if use_facing else NAN)
	AIShotOdds._sync_cells(AIShotOdds._worker)
	for j: int in AIShotOdds._worker.cells.size():
		if AIShotOdds._worker.cells[j] == other:
			return AIShotOdds._worker.weights[j]
	return 0.0


func _spot_of(c: int) -> int:
	var t: PackedStringArray = AIShotFieldData.ROWS[c].split("\t")
	return AIShotFieldData.SPOT_FWD.find(float(t[2])) * AIShotFieldData.SPOT_X.size() \
			+ AIShotFieldData.SPOT_X.find(float(t[1]))


func test_a_keeper_drawn_off_his_depth_is_told_from_a_set_one() -> void:
	# A decoy that leaves him deep in his net or out challenging, at the offset
	# a set keeper has: his depth alone is what tells the two apart.
	AIShotOdds.shot_set(Vector3(0.0, 0.0, GOAL_Z + 6.0), Vector3(0.0, 0.0, GOAL_Z))
	var checked: int = 0
	for c: int in AIShotFieldData.ROWS.size():
		if AIShotFieldData.ROWS[c].get_slice("\t", 3) != "DECOY":
			continue
		var set_cell: int = AIShotOdds._set_cell[_spot_of(c)]
		if absf(AIShotOdds._depth[c] - AIShotOdds._depth[set_cell]) \
				< 2.0 * AIShotOdds.DEPTH_BANDWIDTH_M \
				or AIShotOdds._stance[c] != AIShotOdds._stance[set_cell]:
			continue
		checked += 1
		assert_gt(_weight_of(c, c, false), _weight_of(set_cell, c, false),
				"decoy cell %d reads as itself, not the SET keeper" % c)
	assert_gt(checked, 0, "the field measures keepers drawn off their depth")


func test_a_keeper_turned_off_the_shot_is_told_from_a_set_one() -> void:
	# A feed can leave him at a set keeper's offset and depth, still, but turned
	# toward where the pass came from: his facing alone tells the two apart.
	AIShotOdds.shot_set(Vector3(0.0, 0.0, GOAL_Z + 6.0), Vector3(0.0, 0.0, GOAL_Z))
	var checked: int = 0
	for c: int in AIShotFieldData.ROWS.size():
		if AIShotOdds._is_shot_sample[c] == 0:
			continue
		var set_cell: int = AIShotOdds._set_cell[_spot_of(c)]
		if c == set_cell or AIShotOdds._stance[c] != AIShotOdds._stance[set_cell] \
				or absf(angle_difference(AIShotOdds._square[c], AIShotOdds._square[set_cell])) \
						< 2.0 * AIShotOdds.SQUARE_BANDWIDTH_RAD:
			continue
		checked += 1
		assert_gt(_weight_of(c, c, true), _weight_of(set_cell, c, true),
				"cell %d, turned off the shot, reads as itself" % c)
	assert_gt(checked, 0, "the field measures keepers turned off the shot")


func test_a_keeper_on_the_post_is_read_by_whether_the_puck_is_in_his_seal_zone() -> void:
	# Sealed with the puck inside his zone he is set on the post; with it outside,
	# it has been pulled off the line and he is leaving. Each query reads only the
	# cells on its own side of that trigger.
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var keeper: Vector3 = _keeper_at(goal, 0.85, 0.1)
	var read: Array[bool] = [false, false]
	for fwd: float in [0.6, 0.65, 0.8, 1.0, 1.5, 2.5]:
		for x: float in [-8.0, -5.0, -4.0, 4.0, 4.5, 6.0, 8.0]:
			var release := Vector3(x, 0.0, GOAL_Z + fwd)
			var k := Vector3(keeper.x * signf(x), 0.0, keeper.z)
			var inside: int = 1 if AIGoalieModel.in_post_seal_zone(release, goal) else 0
			AIShotOdds.shot_now(release, goal, k, 0.0, AIShotOdds.Stance.POST_SEAL)
			AIShotOdds._sync_cells(AIShotOdds._worker)
			for c: int in AIShotOdds._worker.cells:
				assert_eq(int(AIShotOdds._in_seal_zone[c]), inside,
						"a seal read at (%.1f, %.2f) reads cell %d" % [x, fwd, c])
			if not AIShotOdds._worker.cells.is_empty():
				read[inside] = true
	assert_true(read[0] and read[1], "the field measures the seal both held and being left")


# A caller off the AI worker reads through its own Query. It gets the worker's
# answer, and the worker's scratch is left as the worker's last read had it.
func test_a_query_of_its_own_leaves_the_workers_untouched() -> void:
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var keeper: Vector3 = _keeper_at(goal, 0.3, 1.2)
	var mine := AIShotOdds.Query.new()
	for x: float in [-6.0, -2.0, 0.0, 3.0, 7.0]:
		var release := Vector3(x, 0.0, GOAL_Z + 7.0)
		var worker_odds: float = AIShotOdds.shot_now(release, goal, keeper, 0.5,
				AIShotOdds.Stance.UPRIGHT)
		AIShotOdds._sync_cells(AIShotOdds._worker)
		var worker_cells: PackedInt32Array = AIShotOdds._worker.cells.duplicate()
		var other := Vector3(-x, 0.0, GOAL_Z + 3.0)
		AIShotOdds.shot_now_at_spread(other, goal, keeper, 0.0, AIShotOdds.Stance.UPRIGHT, 0.06,
				NAN, mine)
		AIShotOdds._sync_cells(AIShotOdds._worker)
		assert_eq(AIShotOdds._worker.cells, worker_cells, "x %.0f: the worker's cells kept" % x)
		assert_eq(AIShotOdds.shot_now(release, goal, keeper, 0.5, AIShotOdds.Stance.UPRIGHT,
				NAN, mine), worker_odds, "x %.0f: the same answer through either" % x)


# The xG stat reads the field on the main thread at a release while the AI worker
# reads it too: the main-thread game code reaches it only through its own query.
func test_the_main_thread_reads_the_field_through_its_own_query() -> void:
	var allowed: Array[String] = ["AIShotOdds.Query", "AIShotOdds.Stance",
			"AIShotOdds.prepare", "AIShotOdds.native_factory", "AIShotOdds.attach_native"]
	var checked: int = 0
	for f: String in DirAccess.get_files_at("res://Scripts/game"):
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string("res://Scripts/game".path_join(f))
		for token: String in ["AIShotOdds.", "AIShotValue.", "AIPossessionValue."]:
			var at: int = src.find(token)
			while at >= 0:
				var use: String = src.substr(at, 40)
				var ok: bool = false
				for a: String in allowed:
					if use.begins_with(a):
						ok = true
				assert_true(ok, "%s calls %s on the main thread" % [f, use.get_slice("(", 0)])
				at = src.find(token, at + 1)
		var call_at: int = src.find("expected_goals(")
		while call_at >= 0:
			checked += 1
			var args: String = src.substr(call_at, src.find("\n\n", call_at) - call_at)
			assert_true(args.contains("_xg_query"), "%s reads xG through its own query" % f)
			call_at = src.find("expected_goals(", call_at + 1)
	assert_gt(checked, 0, "the xG call was found")
