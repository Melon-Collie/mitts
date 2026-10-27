class_name AIDefenderRace

# Whether a defender gets his stick to the puck first, as a race on the shared
# arrival clock (docs/defender-race-plan.md). No defender intent: his time to
# the point against the puck's, graded by an uncertainty that grows with how far
# ahead the point is. A leaf — AIArrival, AILaneReach and AISkaterCaps only.

# How long he carries on as he is before he skates to the point (s).
const REACT_S: float = 0.15
# The grade's half-width at T = 0 (s), and its growth per second of T: the
# further out the collision, the more he can choose to do something else.
const SIGMA_S: float = AIArrival.ERROR_FLOOR_S
const SIGMA_PER_S: float = AIArrival.ERROR_FRAC


# When the stick of a defender at `pos` moving at `vel`, built as `caps` (null:
# the league build), is within his reach of `point` (or within `reach_m` of it):
# now if it already is; else he carries on for `react_s`, then skates to it on
# the arrival clock.
static func stick_time(pos: Vector3, vel: Vector3, caps: AISkaterCaps, point: Vector3,
		react_s: float = REACT_S, reach_m: float = -1.0) -> float:
	var reach: float = reach_m if reach_m >= 0.0 else AILaneReach.defender_reach(caps)
	var nx: float = point.x - pos.x
	var nz: float = point.z - pos.z
	if nx * nx + nz * nz <= reach * reach:
		return 0.0
	var from := Vector3(pos.x + vel.x * react_s, 0.0, pos.z + vel.z * react_s)
	var ox: float = from.x - point.x
	var oz: float = from.z - point.z
	var off: float = sqrt(ox * ox + oz * oz)
	if off <= reach:
		return react_s
	return react_s + AIArrival.time_to_arrive_caps(from,
			Vector3(point.x + ox / off * reach, 0.0, point.z + oz / off * reach), vel, caps)


# The odds the puck at a point `t_puck` from now is not his, whose stick gets
# there at `t_stick`: even when they tie, sure a half-width either side.
static func keep(t_stick: float, t_puck: float, sigma_s: float = SIGMA_S,
		sigma_per_s: float = SIGMA_PER_S) -> float:
	var half: float = maxf(sigma_s + sigma_per_s * t_puck, 0.001)
	return clampf(0.5 + (t_stick - t_puck) / (2.0 * half), 0.0, 1.0)


# The odds the puck keeps to the path `points` (reached at `times` from now)
# against every defender (index-matched `vels`, `caps` or empty for the league
# build): each defender at his best point on it, the defenders multiplied.
static func path_keep(points: Array[Vector3], times: Array[float],
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array,
		react_s: float = REACT_S, sigma_s: float = SIGMA_S,
		sigma_per_s: float = SIGMA_PER_S) -> float:
	var has_caps: bool = caps.size() == defenders.size()
	var total: float = 1.0
	for i: int in defenders.size():
		var c: AISkaterCaps = caps[i] if has_caps else null
		var worst: float = 1.0
		for k: int in points.size():
			worst = minf(worst, keep(stick_time(defenders[i], vels[i], c, points[k], react_s),
					times[k], sigma_s, sigma_per_s))
			if worst <= 0.0:
				return 0.0
		total *= worst
	return total
