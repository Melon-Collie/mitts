extends GutTest

# AICrossCheckRead: the bots' prediction of a cross-check is the host's own (a
# live SkaterController.take_cross_check), the screen it reads is a body on the
# goalie's sightline (GoalieScreenRules' silhouette), and the two reasons to
# throw one — a screen it clears, a race it turns.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")


class HostStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _cfg := GoalieScreenRules.ScreenConfig.new()


func _controller() -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var host := HostStub.new()
	add_child_autofree(host)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, host)
	skater.is_host_machine = true
	return c


func test_the_prediction_is_what_the_host_lands() -> void:
	var push := Vector2(1.0, 0.0)
	for case: Array in [
			[Vector2(1.0, 0.0), false, Vector2.ZERO],      # along his blades
			[Vector2(0.0, 1.0), false, Vector2.ZERO],      # across them
			[Vector2(0.0, 1.0), true, Vector2.ZERO],       # across, loaded low
			[Vector2(1.0, 0.0), false, Vector2(-1.0, 0.0)]]:  # pushing back into it
		var c: SkaterController = _controller()
		c.skater.set_facing(case[0])
		c.stance_active = case[1]
		c.skater.move_intent = case[2]
		var man := SkaterNetworkState.new()
		man.facing = case[0]
		man.stance_active = case[1]
		man.move_intent = case[2]
		var caps := AISkaterCaps.new()
		caps.weight = c.skater.weight
		caps.max_accel = c.thrust
		caps.lateral_grip = 1.0
		var predicted: float = AICrossCheckRead.predicted_dv(1.0,
				GameRules.DEFAULT_SKATER_THRUST_M_S2, man, caps, push)
		var landed: float = c.take_cross_check(1.0, GameRules.DEFAULT_SKATER_THRUST_M_S2, push)
		assert_almost_eq(predicted, landed, 1e-5, "facing %s stance %s intent %s" % case)


func test_a_harder_push_moves_him_further_and_a_stronger_man_stops_it_sooner() -> void:
	var thrust: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
	assert_eq(AICrossCheckRead.displacement_m(0.0, thrust), 0.0)
	assert_gt(AICrossCheckRead.displacement_m(1.2, thrust), AICrossCheckRead.displacement_m(0.8, thrust))
	assert_lt(AICrossCheckRead.displacement_m(1.0, thrust * 1.2),
			AICrossCheckRead.displacement_m(1.0, thrust))


func test_the_shove_leaves_him_a_staggered_stride() -> void:
	var thrust: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
	assert_lt(AICrossCheckRead.staggered_thrust(1.0, thrust), thrust)
	assert_eq(AICrossCheckRead.staggered_thrust(0.1, thrust), thrust, "under the stagger floor")


func test_a_push_that_moves_him_off_the_sightline_clears_the_screen() -> void:
	var goalie := Vector3(0.0, 0.0, 25.0)
	var puck := Vector3(0.0, 0.02, 15.0)
	var man := Vector3(0.2, 0.85, 22.0)
	assert_true(AICrossCheckRead.clears_screen(man, Vector2(1.0, 0.0), 0.3, goalie, puck, _cfg),
			"off the line")
	assert_false(AICrossCheckRead.clears_screen(man, Vector2(1.0, 0.0), 0.05, goalie, puck, _cfg),
			"not far enough")
	assert_false(AICrossCheckRead.clears_screen(man, Vector2(0.0, -1.0), 1.0, goalie, puck, _cfg),
			"along the line he still screens")
	assert_false(AICrossCheckRead.clears_screen(Vector3(2.0, 0.85, 22.0), Vector2(1.0, 0.0), 0.3,
			goalie, puck, _cfg), "no screen to clear")


func test_a_race_is_turned_only_if_he_wins_it_now_and_not_after() -> void:
	assert_true(AICrossCheckRead.takes_the_race(1.0, 0.8, 1.2))
	assert_false(AICrossCheckRead.takes_the_race(1.0, 1.1, 1.5), "we win it anyway")
	assert_false(AICrossCheckRead.takes_the_race(1.0, 0.8, 0.9), "he still wins it")
	assert_false(AICrossCheckRead.takes_the_race(0.1, 0.05, 0.25),
			"our stick is still out when he gets there")
