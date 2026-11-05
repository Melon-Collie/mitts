class_name AIIcingRead
extends RefCounted

# NHL hybrid icing (IcingRace) as a bot reads a release before it makes it: the
# puck leaves our half, crosses their goal line before anybody plays it, and
# their side wins the race to the end-zone dots. Callers walk the puck's path
# and know who touches it when; this reads the rule off those.

# A faceoff is a coin flip for the puck: the share of their possession of the
# dot an icing hands over.
const FACEOFF_LOSS_SHARE: float = 0.5


# When the puck walked on `path` (its position every `step_dt` from the
# release) first crosses the goal line at the end `attack_z` attacks (its sign).
# INF when it does not within the walk.
static func crossing_s(path: Array[Vector3], step_dt: float, attack_z: float) -> float:
	for i: int in path.size():
		if path[i].z * attack_z > GameRules.GOAL_LINE_Z:
			return float(i + 1) * step_dt
	return INF


# Whether a release from `origin_z` toward the end `attack_z` attacks, crossing
# their goal line at `crossed_s` and first played at `touched_s`, is iced: from
# our half, across untouched, and our side (`ours_to_dots`) not at the dots
# ahead of theirs (`theirs_to_dots`) by the clear margin.
static func ices(origin_z: float, attack_z: float, crossed_s: float, touched_s: float,
		ours_to_dots: float, theirs_to_dots: float) -> bool:
	if not InfractionRules.behind_red_line(origin_z, attack_z):
		return false
	if crossed_s >= touched_s:
		return false
	return ours_to_dots + GameRules.ICING_RACE_CLEAR_MARGIN_S > theirs_to_dots


# Soonest of `pos` (velocities and caps index-matched; a null cap is the league
# reference build) to the end-zone dots' line at the end `attack_z` attacks,
# straight down the ice.
static func first_to_dots(attack_z: float, pos: Array[Vector3], vel: Array[Vector3],
		caps: Array[AISkaterCaps]) -> float:
	var line_z: float = attack_z * GameRules.ICING_FACEOFF_DOT_Z
	var best: float = INF
	for i: int in pos.size():
		var c: AISkaterCaps = caps[i] if i < caps.size() else null
		best = minf(best, AIArrival.time_to_arrive(pos[i], Vector3(pos[i].x, 0.0, line_z),
				vel[i] if i < vel.size() else Vector3.ZERO,
				c.max_speed if c != null else AIArrival.SKATER_REF_SPEED_M_S))
	return best


# Where the faceoff for `team_id`'s icing is taken: its own end's dot on the
# release's side.
static func faceoff_spot(team_id: int, release_x: float) -> Vector3:
	var dot: Vector2 = GameRules.icing_faceoff_dot(team_id, release_x)
	return Vector3(dot.x, 0.0, dot.y)
