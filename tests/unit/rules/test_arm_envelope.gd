extends GutTest

# ArmEnvelope's reads of its table: the band a bearing holds, a radius held
# into it, a bearing nothing holds at turned toward straight ahead to one that
# does, and the hands interpolated between the cells round a blade. On a table
# where every build and trunk holds the blade 0.8–1.3 m out within 90° of the
# facing and nowhere else, its top hand 0.2 m ahead and its grip spacing the
# blade's radius over four.

const DEG: float = PI / 180.0


func _table(version: int = ArmEnvelope.VERSION) -> Dictionary:
	var builds: Array = []
	for height: int in ArmEnvelope.HEIGHTS:
		var states := {}
		for state: String in ArmEnvelope.STATES:
			var rows: Array = []
			for angle: float in ArmEnvelope.ANGLES_DEG:
				for radius: float in ArmEnvelope.RADII_M:
					var held: bool = absf(angle) <= 90.0 and radius >= 0.8 - 0.001 \
							and radius <= 1.3 + 0.001
					rows.append([1, 0.1, -0.05, -0.2, radius * 0.25, 0.2, 0.0, 0.05] if held
							else [0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
			states[state] = rows
		builds.append({"height": height, "states": states,
				"crouch_curve": [[0.0, 0.0], [1.0, 0.02], [2.0, 0.08]]})
	return {"version": version, "builds": builds}


func test_a_bearing_holds_its_band_and_a_radius_is_held_into_it() -> void:
	var env: ArmEnvelope = ArmEnvelope.from_dict(_table())
	assert_almost_eq(env.band_at(73.0, 0.5, 30.0), Vector2(0.8, 1.3), Vector2.ONE * 0.0001, "the band")
	assert_almost_eq(env.held_blade(73.0, 0.5, 30.0 * DEG, 0.5), Vector2(30.0 * DEG, 0.8),
			Vector2.ONE * 0.0001, "in close: out to the floor")
	assert_almost_eq(env.held_blade(70.0, 0.2, -45.0 * DEG, 2.0), Vector2(-45.0 * DEG, 1.3),
			Vector2.ONE * 0.0001, "far out: in to the rim")
	assert_almost_eq(env.held_blade(77.0, 1.0, 0.0, 1.0), Vector2(0.0, 1.0),
			Vector2.ONE * 0.0001, "inside it: where it is")


func test_a_bearing_nothing_holds_at_turns_toward_straight_ahead() -> void:
	var env: ArmEnvelope = ArmEnvelope.from_dict(_table())
	assert_gt(env.band_at(73.0, 0.0, 135.0).x, env.band_at(73.0, 0.0, 135.0).y, "nothing at 135°")
	for deg: float in [135.0, -150.0]:
		var held: Vector2 = env.held_blade(73.0, 0.0, deg * DEG, 1.0)
		assert_lt(absf(held.x), absf(deg) * DEG, "turned toward ahead")
		assert_almost_eq(absf(held.x), 95.0 * DEG, 5.5 * DEG, "to the first bearing that holds")
		assert_eq(signf(held.x), signf(deg), "on its own side")


func test_the_hands_are_the_cells_round_the_blade_between_them() -> void:
	var env: ArmEnvelope = ArmEnvelope.from_dict(_table())
	var hold := ArmEnvelope.Hold.new()
	assert_true(env.hold_at(73.0, 0.5, 20.0, 1.05, hold), "held")
	assert_almost_eq(hold.hand, Vector3(0.1, -0.05, -0.2), Vector3.ONE * 0.0001, "its hand")
	assert_almost_eq(hold.spacing, 1.05 * 0.25, 0.0001, "the grip between its radii's")
	assert_true(env.hold_at(73.0, 0.5, 20.0, 0.75, hold), "half a cell in")
	assert_almost_eq(hold.spacing, 0.8 * 0.25, 0.0001, "only the cell that holds counts")
	assert_almost_eq(hold.lean, Vector2(0.2, 0.0), Vector2.ONE * 0.0001, "its lean")
	assert_almost_eq(hold.crouch, 0.05, 0.0001, "its crouch")
	assert_false(env.hold_at(73.0, 0.5, 140.0, 1.0, hold), "nothing round 140°")


func test_a_crouch_is_read_off_the_stances_curve_either_way() -> void:
	var env: ArmEnvelope = ArmEnvelope.from_dict(_table())
	assert_almost_eq(env.drop_for_floor(73.0, 1.5), 0.05, 0.0001, "between its points")
	assert_almost_eq(env.floor_for_drop(73.0, 0.05), 1.5, 0.0001, "and back")
	assert_almost_eq(env.floor_for_drop(73.0, 0.14), 3.0, 0.0001, "past its end, along its last stretch")


func test_a_table_of_another_version_is_refused() -> void:
	assert_null(ArmEnvelope.from_dict(_table(ArmEnvelope.VERSION + 1)), "refused")
