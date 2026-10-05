extends GutTest

# Down, his pad reaches the post only along the line it points. The arrival test
# measures the post spot against that pad, turned however far his body is from
# the seal's own facing (GoalieBehaviorRules.tuck_point_travel).

const GOAL_Z: float = 0.0
const POST_X: float = -0.915


func _cfg(turn: float) -> GoalieBehaviorRules.BeatenWideConfig:
	var c := GoalieBehaviorRules.BeatenWideConfig.new()
	c.cover_radius = 0.8
	c.pad_turn_rad = Vector2(turn, 0.0)
	return c


func test_facing_the_seal_it_is_the_plain_reach() -> void:
	var g := Vector3(-0.2, 0.0, 0.1)
	var d: float = Vector2(POST_X - g.x, GOAL_Z - g.z).length()
	assert_almost_eq(GoalieBehaviorRules.tuck_point_travel(g, POST_X, GOAL_Z, _cfg(0.0)),
			d - 0.8, 1e-6)


func test_turned_away_the_post_is_open_though_it_is_in_reach() -> void:
	var g := Vector3(-0.2, 0.0, 0.1)
	assert_lte(GoalieBehaviorRules.tuck_point_travel(g, POST_X, GOAL_Z, _cfg(0.0)), 0.0,
			"in reach, and pointing at it: sealed")
	var turned: float = GoalieBehaviorRules.tuck_point_travel(
			g, POST_X, GOAL_Z, _cfg(deg_to_rad(50.0)))
	assert_gt(turned, 0.3, "the same reach swung 50 degrees off the post covers nothing")


func test_only_the_drive_side_turn_counts() -> void:
	var c := _cfg(0.0)
	c.pad_turn_rad = Vector2(0.0, deg_to_rad(50.0))
	var g := Vector3(-0.2, 0.0, 0.1)
	assert_lte(GoalieBehaviorRules.tuck_point_travel(g, POST_X, GOAL_Z, c), 0.0,
			"a turn away from the other post is not this seal's")
