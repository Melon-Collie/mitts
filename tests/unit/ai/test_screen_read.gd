extends GutTest

# AIScreenRead: the screen a bot reads is the goalie's own
# (GoalieBehaviorRules.screen_peek_offset), and a push clears it only by moving
# the body off the sightline.

var _cfg := GoalieBehaviorRules.ScreenConfig.new()


func test_the_screen_is_the_goalies_own() -> void:
	var goalie := Vector3(0.0, 0.0, 25.0)
	var puck := Vector3(1.5, 0.02, 15.0)
	for x: float in [-1.0, -0.5, -0.2, 0.0, 0.2, 0.4, 0.8, 1.5]:
		for z: float in [24.6, 23.0, 21.0, 18.0, 15.5]:
			var body := Vector3(x, 0.85, z)
			var bodies := PackedVector3Array([body])
			var peeks: bool = GoalieBehaviorRules.screen_peek_offset(goalie, puck, bodies, _cfg,
					100.0) != 0.0
			assert_eq(AIScreenRead.hides_release(body, goalie, puck, _cfg), peeks,
					"body at (%.1f, %.1f)" % [x, z])


func test_a_push_that_moves_him_off_the_sightline_clears_the_screen() -> void:
	var goalie := Vector3(0.0, 0.0, 25.0)
	var puck := Vector3(0.0, 0.02, 15.0)
	var man := Vector3(0.2, 0.85, 22.0)
	assert_true(AIScreenRead.clears_screen(man, Vector2(1.0, 0.0), 0.3, goalie, puck, _cfg),
			"off the line")
	assert_false(AIScreenRead.clears_screen(man, Vector2(1.0, 0.0), 0.05, goalie, puck, _cfg),
			"not far enough")
	assert_false(AIScreenRead.clears_screen(man, Vector2(0.0, -1.0), 1.0, goalie, puck, _cfg),
			"along the line he still screens")
	assert_false(AIScreenRead.clears_screen(Vector3(2.0, 0.85, 22.0), Vector2(1.0, 0.0), 0.3,
			goalie, puck, _cfg), "no screen to clear")
