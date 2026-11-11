class_name AIScreenRead
extends RefCounted

# Whether a body screens a goalie, read off the goalie's own silhouette and
# sightline (GoalieScreenRules). The press prices a screen off it.
# Pure/static, no allocation.

# Whether `body` hides the release from the goalie (GoalieScreenRules.hides):
# the release screen_occlusion_delay finds hidden (test_screen_read.gd holds
# the two together).
static func hides_release(body: Vector3, goalie_pos: Vector3, puck_pos: Vector3,
		cfg: GoalieScreenRules.ScreenConfig) -> bool:
	return GoalieScreenRules.hides(body, goalie_pos, puck_pos, cfg)


# A screen a push clears: he hides the release now, and moved `displacement`
# along `push_dir` he would not.
static func clears_screen(man_pos: Vector3, push_dir: Vector2, displacement: float,
		goalie_pos: Vector3, puck_pos: Vector3, cfg: GoalieScreenRules.ScreenConfig) -> bool:
	if not hides_release(man_pos, goalie_pos, puck_pos, cfg):
		return false
	var moved := Vector3(man_pos.x + push_dir.x * displacement, man_pos.y,
			man_pos.z + push_dir.y * displacement)
	return not hides_release(moved, goalie_pos, puck_pos, cfg)
