class_name GoalieScreenDepth

# Room to see around a screen.
#
# A goalie finds a screened puck by getting his eyes around the body
# (GoalieBehaviorRules.screen_peek_offset), and how well that works depends on
# his distance from the screener in both directions:
#
#   * TIGHT is good — the sightline pivots about the release point, so a head
#     move close to the body swings the line past it almost one for one. At his
#     challenge depth he is already tight to a slot or top-of-the-crease screen,
#     which is why the ceiling needs no screen term to push him out.
#   * ON him is blind — a body inside the peek's reach of his own eyes fills the
#     view and no lateral step turns the line around it. That is chest-to-chest
#     with the screener, which is exactly what goalies are taught to avoid: give
#     yourself a stick of room and look around him.
#
# So the constraint is a MAXIMUM radius: the furthest out, along his challenge
# ray, from which the peek still clears every body hiding the release. INF when
# he can already see from `r_hi`, and INF when backing off would not let him see
# either — then a release he never saw is the blocking drop's to answer.
#
# Only one radius per hiding body is worth asking about: the one that puts it
# just outside the peek's reach of his eyes (`min_along`). Short of that it
# fills the view; past it, every further step back only lengthens the lever the
# peek has to turn, so a body he cannot see around from there he cannot see
# around from deeper either.
#
# Pure/static, no allocation.

static func sight_cap(goal_center: Vector3, threat: Vector3, puck: Vector3,
		screeners: PackedVector3Array, cfg: GoalieBehaviorRules.ScreenConfig,
		max_peek: float, r_hi: float, r_lo: float) -> float:
	if screeners.is_empty():
		return INF
	var ux: float = threat.x - goal_center.x
	var uz: float = threat.z - goal_center.z
	var u_len: float = sqrt(ux * ux + uz * uz)
	if u_len < 0.001:
		return INF
	ux /= u_len
	uz /= u_len
	if _sees_from(goal_center, ux, uz, r_hi, puck, screeners, cfg, max_peek):
		return INF
	var best: float = INF
	for body in screeners:
		var along: float = (body.x - goal_center.x) * ux + (body.z - goal_center.z) * uz
		var r: float = along - cfg.min_along - cfg.peek_clearance
		if r >= r_hi or r < r_lo or (not is_inf(best) and r <= best):
			continue
		if _sees_from(goal_center, ux, uz, r, puck, screeners, cfg, max_peek):
			best = r
	return best


# Can he see the release from radius `r` on the ray, peeking as far as he may?
static func _sees_from(goal_center: Vector3, ux: float, uz: float, r: float,
		puck: Vector3, screeners: PackedVector3Array,
		cfg: GoalieBehaviorRules.ScreenConfig, max_peek: float) -> bool:
	var g := Vector3(goal_center.x + ux * r, goal_center.y, goal_center.z + uz * r)
	var eye: Vector3 = g
	eye.x += GoalieBehaviorRules.screen_peek_offset(g, puck, screeners, cfg, max_peek)
	var line: Vector3 = eye - puck
	line.y = 0.0
	return GoalieBehaviorRules.screen_occlusion_delay(
			puck, line, eye, screeners, cfg) <= 0.0
