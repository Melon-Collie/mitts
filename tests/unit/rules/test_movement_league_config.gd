extends GutTest

# A bot plans a league-average body with SkaterMovementRules.league_config and
# AISkaterCaps' defaults until its own build applies; they must be the body the
# controller and skater ship with before any attributes.


func test_league_config_is_the_controllers_authored_config() -> void:
	var ctrl := SkaterController.new()
	var authored: SkaterMovementRules.MovementConfig = ctrl.get_movement_config()
	ctrl.free()
	var league: SkaterMovementRules.MovementConfig = SkaterMovementRules.league_config()
	for prop: Dictionary in league.get_property_list():
		if prop["type"] != TYPE_FLOAT:
			continue
		var field: String = prop["name"]
		assert_almost_eq(league.get(field), authored.get(field), 1e-6, field)


func test_caps_defaults_are_the_authored_body() -> void:
	var ctrl := SkaterController.new()
	var caps := AISkaterCaps.new()
	assert_eq(caps.facing_drag_speed, ctrl.facing_drag_speed)
	assert_eq(caps.facing_drag_speed_braking, ctrl.facing_drag_speed_braking)
	assert_eq(caps.board_shield_probe, ctrl.board_shield_probe)
	assert_almost_eq(caps.board_shield_max_rad, deg_to_rad(ctrl.board_shield_max_deg), 1e-6)
	ctrl.free()
	var skater: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	assert_eq(caps.body_radius, skater.collision_radius())
	skater.free()
