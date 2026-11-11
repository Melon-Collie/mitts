extends GutTest

# Which shots he reads as going in (KeeperShotRead.on_net): every line the
# game scores clean between the posts and under the bar, and the ones tight
# enough to the iron to go in off its inner half (a post's or the bar's); none wide of a post or over
# the bar. Flat shots from the blue line out by the boards, where one tight
# inside the far post was let go as wide.

const RELEASE := Vector3(9.5, GameRules.PUCK_COLLISION_HALF_HEIGHT, -18.8)
const SHOT_M_S: float = 40.0


# A flat shot from RELEASE whose line crosses the goal line `x` across at
# `y` up, as he reads it.
func _read(x: float, y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT) -> KeeperShotRead:
	var read := KeeperShotRead.new()
	var flat := Vector2(x - RELEASE.x, -RELEASE.z)
	var t: float = flat.length() / SHOT_M_S
	var along: Vector2 = flat.normalized() * SHOT_M_S
	var vy: float = 0.0
	if y > RELEASE.y:
		vy = (y - RELEASE.y + 0.5 * GameRules.GRAVITY_M_S2 * t * t) / t
	read.start()
	read.step(0.0, RELEASE, Vector3(along.x, vy, along.y))
	return read


func test_every_line_the_game_scores_clean_is_read_on_net() -> void:
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	var limit: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - r
	var x: float = -limit
	while x <= limit + 1e-6:
		assert_true(GoalDetectionRules.point_in_mouth(x, GameRules.PUCK_COLLISION_HALF_HEIGHT,
				GameRules.NET_HALF_WIDTH, GameRules.NET_HEIGHT, GameRules.NET_POST_RADIUS, r,
				GameRules.PUCK_COLLISION_HALF_HEIGHT), "a goal at %.3f" % x)
		assert_true(_read(x).on_net(), "on net at %.3f" % x)
		x += limit / 20.0


func test_a_shot_tight_inside_the_far_post_is_on_net() -> void:
	var limit: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS \
			- GameRules.PUCK_COLLISION_RADIUS
	assert_true(_read(-limit).on_net(), "at the clear mouth's edge")
	assert_true(_read(-(limit + 0.005)).on_net(), "a hair past it, onto the iron")


func test_one_on_the_inner_half_of_the_iron_is_on_net() -> void:
	assert_true(_read(-(GameRules.NET_HALF_WIDTH - 0.005)).on_net(), "far post")
	assert_true(_read(GameRules.NET_HALF_WIDTH - 0.005).on_net(), "near post")
	assert_true(_read(0.0, GameRules.NET_HEIGHT - 0.005).on_net(), "the bar")


func test_one_wide_of_a_post_or_over_the_bar_is_not() -> void:
	assert_false(_read(-(GameRules.NET_HALF_WIDTH + 0.005)).on_net(), "wide of the far post")
	assert_false(_read(GameRules.NET_HALF_WIDTH + 0.005).on_net(), "wide of the near post")
	assert_false(_read(0.0, GameRules.NET_HEIGHT + 0.005).on_net(), "over the bar")
