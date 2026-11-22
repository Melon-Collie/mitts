extends GutTest

# The duel harness's deliberate tip (duel_harness.gd:tip_velocity) against the
# real one (Puck.apply_blade_deflect on a Skater holding the deflect): the same
# puck off the same blade leaves at the same velocity, at every tip height.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const LEVELS: Array[int] = [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
		ShotMechanics.ELEVATION_MID, ShotMechanics.ELEVATION_HIGH]
# Shots across the blade from either side, and one along it.
const INCOMING: Array[Vector3] = [Vector3(4.0, 0.0, -30.0), Vector3(-9.0, 0.0, -24.0),
		Vector3(28.0, 0.0, 3.0), Vector3(0.0, 0.0, 18.0)]


func test_the_duel_tips_a_shot_as_the_puck_does() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.deflect_intent = true
	var blade_rel: Vector3 = skater.get_blade_contact_global() - skater.global_position
	assert_gt(Vector2(blade_rel.x, blade_rel.z).length(), 0.1, "the blade is off the body")
	for v: Vector3 in INCOMING:
		for level: int in LEVELS:
			puck.position = Vector3(0.0, puck.ice_height, 0.0)
			puck.linear_velocity = v
			skater.elevation_level = level
			puck.apply_blade_deflect(skater)
			var duel: Vector3 = Duel.tip_velocity(v, blade_rel, level)
			assert_almost_eq(duel.distance_to(puck.linear_velocity), 0.0, 1e-4,
					"%s tipped at %d: puck %s, duel %s" % [v, level, puck.linear_velocity, duel])


func test_the_duel_holds_the_pucks_tip_tunables() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	assert_eq(Duel.TIP_MAX_TURN_DEG, puck.deflect_max_turn_deg)
	assert_eq(Duel.TIP_LOW_LOFT_M_S, puck.deflect_low_loft_speed)
	assert_eq(Duel.TIP_MID_LOFT_M_S, puck.deflect_mid_loft_speed)
	assert_eq(Duel.TIP_HIGH_LOFT_M_S, puck.deflect_high_loft_speed)
	assert_eq(Duel.TIP_DOWN_LOFT_M_S, puck.deflect_down_loft_speed)
