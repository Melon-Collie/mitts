extends GutTest

# The Puck's three up-tip launch speeds against the shot ladder's targets at the
# goal line (docs/elevation-rework-plan.md: over the butterfly pad, the armpit,
# upstairs), for the reference tip their comment names: off the ice, 5 m out,
# at the ~23 m/s a typical tip keeps of a point shot. The lift is composed as
# Puck.apply_blade_deflect composes it (ShotMechanics.loft_y, total speed kept).

const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const REF_DIST_M: float = 5.0
const REF_PACE_M_S: float = 23.0
const TARGETS_M: Dictionary = {
	ShotMechanics.ELEVATION_LOW: 0.41,
	ShotMechanics.ELEVATION_MID: 0.70,
	ShotMechanics.ELEVATION_HIGH: 0.99,
}
const TOLERANCE_M: float = 0.05


func _arrival(puck: Puck, level: int) -> float:
	var vy: float = PuckCollisionRules.deflect_loft_speed(level,
			puck.deflect_low_loft_speed, puck.deflect_mid_loft_speed,
			puck.deflect_high_loft_speed, puck.deflect_down_loft_speed, false)
	var r: float = ShotMechanics.loft_y(REF_PACE_M_S, absf(vy)) * signf(vy)
	var horiz: float = REF_PACE_M_S / sqrt(1.0 + r * r)
	var up: float = REF_PACE_M_S * r / sqrt(1.0 + r * r)
	var t: float = REF_DIST_M / horiz
	return puck.ice_height + up * t - 0.5 * GameRules.GRAVITY_M_S2 * t * t


func test_each_level_tips_onto_its_ladder_height() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	for level: int in TARGETS_M:
		assert_almost_eq(_arrival(puck, level), TARGETS_M[level], TOLERANCE_M,
				"level %d at the goal line" % level)


func test_the_levels_rise_in_order_and_high_stays_under_the_bar() -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	var flat: float = _arrival(puck, ShotMechanics.ELEVATION_FLAT)
	var low: float = _arrival(puck, ShotMechanics.ELEVATION_LOW)
	var mid: float = _arrival(puck, ShotMechanics.ELEVATION_MID)
	var high: float = _arrival(puck, ShotMechanics.ELEVATION_HIGH)
	assert_lt(flat, low)
	assert_lt(low, mid)
	assert_lt(mid, high)
	assert_lt(high, GameRules.NET_HEIGHT, "the reference HIGH tip is under the bar")
