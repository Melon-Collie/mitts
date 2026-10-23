class_name AIScreenRead
extends RefCounted

# Whether a body screens a goalie, read the way the goalie himself reads it: his
# own silhouette and sightline test (GoalieBehaviorRules.ScreenConfig). The
# press prices a screen off it. Pure/static, no allocation.

# Whether `body` stands on the goalie's sightline to the release: between his
# eyes and the puck, clear of both ends (the shooter, and a body on his own
# eyes), and within the body's half-width at the height the line crosses it —
# the test GoalieBehaviorRules.screen_peek_offset makes of each body
# (test_screen_read.gd holds the two together).
static func hides_release(body: Vector3, goalie_pos: Vector3, puck_pos: Vector3,
		cfg: GoalieBehaviorRules.ScreenConfig) -> bool:
	var px: float = puck_pos.x - goalie_pos.x
	var pz: float = puck_pos.z - goalie_pos.z
	var p_len: float = sqrt(px * px + pz * pz)
	if p_len <= cfg.min_along:
		return false
	var vhx: float = px / p_len
	var vhz: float = pz / p_len
	var wx: float = body.x - goalie_pos.x
	var wz: float = body.z - goalie_pos.z
	var along: float = wx * vhx + wz * vhz
	if along <= cfg.min_along or along >= p_len - cfg.min_along:
		return false
	var eye_y: float = goalie_pos.y + cfg.eye_height
	var sight_y: float = eye_y + along / p_len * (puck_pos.y - eye_y)
	return absf(wx * -vhz + wz * vhx) < GoalieBehaviorRules.screener_half_width_at(sight_y, cfg)


# A screen a push clears: he hides the release now, and moved `displacement`
# along `push_dir` he would not.
static func clears_screen(man_pos: Vector3, push_dir: Vector2, displacement: float,
		goalie_pos: Vector3, puck_pos: Vector3, cfg: GoalieBehaviorRules.ScreenConfig) -> bool:
	if not hides_release(man_pos, goalie_pos, puck_pos, cfg):
		return false
	var moved := Vector3(man_pos.x + push_dir.x * displacement, man_pos.y,
			man_pos.z + push_dir.y * displacement)
	return not hides_release(moved, goalie_pos, puck_pos, cfg)
