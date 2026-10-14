extends GutTest

func test_role_decision_defaults_are_neutral() -> void:
	var d := RoleDecision.new()
	assert_eq(d.target_position, Vector3.ZERO)
	assert_false(d.has_aim_override)
