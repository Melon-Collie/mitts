extends GutTest

# AIStickLiftRead: an on-puck bot lifts the carrier's stick instead of jabbing
# exactly when the carrier's body blocks the jab and the shaft is in reach.

const HAND := Vector3(0.0, 1.0, -0.3)
const BLADE := Vector3(0.0, 0.03, -1.4)
const BODY_R: float = GameRules.OFFSIDE_LINE_SLACK


func test_the_lift_point_is_where_a_lifted_blade_fits_under_the_shaft() -> void:
	var p: Vector3 = AIStickLiftRead.shaft_lift_point(HAND, BLADE)
	assert_almost_eq(p.y, AIStickLiftRead.LIFT_CONTACT_Y_M + AIStickLiftRead.UNDER_CLEARANCE_M,
			1e-5)
	# The hook the host tests: a blade at lift height there sits under the shaft.
	var blade_at := Vector3(p.x, AIStickLiftRead.LIFT_CONTACT_Y_M, p.z)
	assert_true(PuckInteractionRules.check_blade_under_stick(blade_at, HAND, BLADE,
			GameRules.STICK_LIFT_RADIUS_M), "aiming there lands the hook")


func test_a_shaft_held_too_low_offers_only_its_top() -> void:
	var low_hand := Vector3(0.0, 0.5, -0.3)
	assert_eq(AIStickLiftRead.shaft_lift_point(low_hand, BLADE), low_hand)


func test_the_puck_is_shielded_only_with_the_body_in_between() -> void:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var puck := Vector3(0.0, 0.0, -1.2)
	assert_true(AIStickLiftRead.puck_shielded(Vector3(0.0, 0.0, 1.5), carrier, puck, BODY_R),
			"from behind, the body is on the line to the puck")
	assert_false(AIStickLiftRead.puck_shielded(Vector3(1.5, 0.0, -1.2), carrier, puck, BODY_R),
			"from the puck side the jab is open")
	assert_false(AIStickLiftRead.puck_shielded(Vector3(0.0, 0.0, -3.0), carrier, puck, BODY_R),
			"head on, the puck is in front of the body")


func test_lift_from_behind_jab_from_the_side() -> void:
	var carrier := Vector3(0.0, 0.0, 0.0)
	var puck := Vector3(0.0, 0.0, -1.2)
	var reach: float = GameRules.DEFAULT_STICK_LENGTH_M + GameRules.DEFAULT_BLADE_LENGTH_M \
			+ GameRules.STICK_LIFT_RADIUS_M
	assert_true(AIStickLiftRead.prefers_lift(Vector3(0.0, 0.0, 1.2), carrier, puck,
			HAND, BLADE, reach, BODY_R), "shielded and the shaft in reach")
	assert_false(AIStickLiftRead.prefers_lift(Vector3(1.4, 0.0, -1.2), carrier, puck,
			HAND, BLADE, reach, BODY_R), "the jab is open")
	assert_false(AIStickLiftRead.prefers_lift(Vector3(0.0, 0.0, 6.0), carrier, puck,
			HAND, BLADE, reach, BODY_R), "shielded but the shaft is out of reach")


func test_the_lift_height_mirrors_the_skater() -> void:
	var controller := SkaterController.new()
	assert_almost_eq(AIStickLiftRead.LIFT_CONTACT_Y_M,
			controller.blade_height + controller.blade_lift_height, 1e-5,
			"the read's lifted blade must sit where the real one does")
	controller.free()
