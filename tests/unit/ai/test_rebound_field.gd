extends GutTest

# AIReboundField reads the generated rebound field (properties of the reader,
# not calibration: the numbers are the goalie's, test_rebound_field_is_current.gd
# holds them to him).

const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const OTHER_NET := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)


func test_every_spot_holds_its_shots() -> void:
	var total: int = 0
	for fi: int in AIReboundFieldData.SPOT_FWD.size():
		for xi: int in AIReboundFieldData.SPOT_X.size():
			var spot: int = fi * AIReboundFieldData.SPOT_X.size() + xi
			assert_gt(AIReboundField.shot_count(spot), 0, "spot %d has shots" % spot)
			total += AIReboundField.shot_count(spot)
	assert_eq(total, AIReboundFieldData.ROWS.size(), "every row belongs to one spot")


func test_a_release_reads_its_nearest_spot_from_either_end() -> void:
	var here: int = AIReboundField.spot_of(Vector3(-3.6, 0.0, NET.z + 6.4), NET)
	var there: int = AIReboundField.spot_of(Vector3(-3.6, 0.0, OTHER_NET.z - 6.4), OTHER_NET)
	assert_eq(here, there, "metres out read from the net attacked")
	var s: int = AIReboundField.shot(here, 0)
	var f: PackedStringArray = AIReboundFieldData.ROWS[s].split("\t")
	assert_almost_eq(float(f[1]), -4.0, 0.01)
	assert_almost_eq(float(f[2]), 6.0, 0.01)


func test_only_a_live_rebound_has_a_path_and_it_starts_at_the_keeper() -> void:
	var live: int = 0
	for r: int in AIReboundFieldData.ROWS.size():
		var o: int = AIReboundField.outcome(r)
		if o == AIReboundField.Outcome.LIVE:
			live += 1
			assert_gt(AIReboundField.sample_count(r), 0, "row %d has a path" % r)
			var first: Vector3 = AIReboundField.sample_pos(r, 0, NET)
			assert_lt(first.distance_to(NET), 3.0, "row %d's first sample is at the save" % r)
		elif o == AIReboundField.Outcome.COVERED or o == AIReboundField.Outcome.GOAL \
				or o == AIReboundField.Outcome.MISSED:
			assert_eq(AIReboundField.sample_count(r), 0, "row %d ends at the save" % r)
	assert_gt(live, 0, "the field holds live rebounds")


func test_the_other_end_mirrors_the_path() -> void:
	for r: int in AIReboundFieldData.ROWS.size():
		if AIReboundField.sample_count(r) == 0:
			continue
		var a: Vector3 = AIReboundField.sample_pos(r, 1, NET)
		var b: Vector3 = AIReboundField.sample_pos(r, 1, OTHER_NET)
		assert_almost_eq(a.x, b.x, 1e-4)
		assert_almost_eq(a.z, -b.z, 1e-4)
		var va: Vector3 = AIReboundField.sample_vel(r, 1, NET)
		var vb: Vector3 = AIReboundField.sample_vel(r, 1, OTHER_NET)
		assert_almost_eq(va.z, -vb.z, 1e-4)
		return
