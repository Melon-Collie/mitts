class_name AIStripOdds

# Whether the defence takes the puck off a path the carrier skates
# (docs/strip-interception-plan.md): the defenders' options from where they are
# and how they are moving, never a guess at what they will do. Over the path's
# first COMMIT_S the carrier sees them coming and dodges, so the odds are whether
# every place he can dodge to is a stick's (escape_margin, measured against an
# interceptor the carrier dodges, tests/instruments/ai/
# test_reacting_interceptor_truth.gd); where the path is going is a race — can a
# stick be set there first (chance_at, measured against a worst-case
# interceptor). Never measured against our defending bots. A leaf — GameRules,
# AIArrival and AISkaterCaps only.

# How long before the puck his stick has to be there to take it (s): a stick
# arriving with less strips next to nothing.
const SET_S: float = 0.25
# The odds a stick set on the path strips a carrier who keeps to it.
const SET_STRIP: float = 0.88
# A carrier dodging them: the odds one poke takes the puck by how deep inside a
# stick's reach his best escape is — DEAD_ON_STRIP deep inside, even odds of
# that ESCAPE_SET_M inside, graded across ESCAPE_BAND_M either side — and a poke
# more for every POKE_CYCLE_S the stick stays on him: the losses inside
# COMMIT_S against an interceptor the carrier dodges, fit by likelihood.
const DEAD_ON_STRIP: float = 0.77
const ESCAPE_SET_M: float = 1.23
const ESCAPE_BAND_M: float = 1.89
const POKE_CYCLE_S: float = 0.31
# A carrier dodges off his line with his whole thrust from this planned pace
# (m/s), ramping in from none on a plan that stands: holding a spot, a dodge
# leaves it, and leaving it is another plan.
const DODGE_FULL_PACE_M_S: float = 1.0
# A straight carry's samples (s).
const DWELL_STEP_S: float = 0.1

# How long the deepest stick at the carrier's best escape stays on him, left by
# the last escape_margin: across his reach at their closing speed, to the end of
# COMMIT_S.
static var last_dwell_s: float = 0.0
# How much of a path a keep read looks at, from where the read starts (s): the
# carrier re-plans many times a second, and inside this he cannot get out of a
# stick's reach however he re-plans (his reaction, then sliding a blade's reach
# aside), so it is what taking the space commits him to. Past it a read looks
# only at where the path is going, when it gets there — whether that place is
# taken first, the race to a crossing of the line that makes speed worth having.
# A man who can only get to the path in between — a chase down from behind — is
# a later decision's.
const COMMIT_S: float = 1.0


# The odds a defender at `pos` moving `vel`, built as `caps` (null: the league
# build), has his stick set on `point` `set_s` before `puck_t` from his read: his
# arrival clock to within `reach` of it (his blade's, when negative), graded
# across the clock's error as the arrival race grades a race.
static func chance_at(pos: Vector3, vel: Vector3, caps: AISkaterCaps, point: Vector3,
		puck_t: float, set_s: float = SET_S, reach: float = -1.0) -> float:
	if reach < 0.0:
		reach = caps.max_blade_reach if caps != null else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var to := Vector3(point.x - pos.x, 0.0, point.z - pos.z)
	var d: float = to.length()
	var arrive: float = 0.0
	if d > reach:
		arrive = AIArrival.time_to_arrive_caps(pos, pos + to * ((d - reach) / d), vel, caps)
	var band: float = maxf(AIArrival.ERROR_FLOOR_S, AIArrival.ERROR_FRAC * arrive)
	return clampf(0.5 + (puck_t - arrive - set_s) / (2.0 * band), 0.0, 1.0)


# How far inside a stick's reach the carrier's best escape from `point` is
# `t` after the defence's read (negative: outside every stick's; -INF with no
# defenders), the plan carrying him through it at `plan_vel` and `on_plan_s`
# after he set off on it (negative: `t`): holding his line, or dodging off it
# either way as far as his thrust and top speed (`carrier_caps`, null: the
# league build) take him in that time, ramped in by DODGE_FULL_PACE_M_S —
# against the deepest of `defenders` (index-matched `vels`, and `caps` or empty
# for the league build) at each. Leaves how long that stick stays on him in
# last_dwell_s.
static func escape_margin(point: Vector3, plan_vel: Vector3, t: float,
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		carrier_caps: AISkaterCaps = null, on_plan_s: float = -1.0) -> float:
	t = maxf(t, 0.0)
	var accel: float = carrier_caps.max_accel if carrier_caps != null \
			else GameRules.DEFAULT_SKATER_THRUST_M_S2
	var top: float = carrier_caps.max_speed if carrier_caps != null \
			else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var pace: float = sqrt(plan_vel.x * plan_vel.x + plan_vel.z * plan_vel.z)
	var dodge: float = _skated(0.0, t if on_plan_s < 0.0 else on_plan_s, top, accel) \
			* minf(1.0, pace / DODGE_FULL_PACE_M_S)
	var side := Vector3(-plan_vel.z / pace, 0.0, plan_vel.x / pace) if pace > 1e-6 \
			else Vector3.ZERO
	var has_caps: bool = caps.size() == defenders.size()
	var plan_t: float = t if on_plan_s < 0.0 else on_plan_s
	# The men who could take it: a stick that cannot get within the odds' floor of
	# any escape changes nothing, whichever is deepest.
	var near: int = 0
	for i: int in defenders.size():
		if _could_reach(defenders[i], vels[i], caps[i] if has_caps else null, point, t,
				dodge + ESCAPE_BAND_M - ESCAPE_SET_M):
			near |= 1 << i
	last_dwell_s = 0.0
	if near == 0:
		return -INF
	# His escapes: either way off his line as far as he gets, or holding it.
	var best: float = INF
	var at := Vector3.ZERO
	var by: int = -1
	var by_reach: float = 0.0
	for j: int in (3 if dodge > 0.0 else 1):
		var escape: Vector3 = point + side * (dodge * (j - 1)) if dodge > 0.0 else point
		var worst: float = -INF
		var worst_i: int = -1
		var worst_reach: float = 0.0
		for i: int in defenders.size():
			if near & (1 << i) == 0:
				continue
			var rd: Vector2 = _reach(defenders[i], vels[i], caps[i] if has_caps else null,
					escape, t)
			if rd.x - rd.y > worst:
				worst = rd.x - rd.y
				worst_i = i
				worst_reach = rd.x
		if worst < best:
			best = worst
			at = escape
			by = worst_i
			by_reach = worst_reach
	if by >= 0:
		var rel := Vector3(plan_vel.x - vels[by].x, 0.0, plan_vel.z - vels[by].z)
		var rel_speed: float = rel.length()
		var miss: float = 0.0
		if rel_speed > 1e-3:
			var off: Vector3 = at - defenders[by] - vels[by] * t
			miss = absf(off.x * rel.z - off.z * rel.x) / rel_speed
		var chord: float = 2.0 * sqrt(maxf(by_reach * by_reach - miss * miss, 0.0))
		last_dwell_s = minf(chord / maxf(rel_speed, 1e-3), COMMIT_S - plan_t + DWELL_STEP_S)
	return best


# The odds the defence takes the puck from an escape margin, its stick on him for
# `dwell_s` (escape_margin, last_dwell_s): a poke at those odds, and another
# every POKE_CYCLE_S.
static func strip_odds(margin: float, dwell_s: float = 0.0) -> float:
	var poke: float = DEAD_ON_STRIP * clampf(0.5 + (margin - ESCAPE_SET_M) / (2.0 * ESCAPE_BAND_M),
			0.0, 1.0)
	if poke <= 0.0:
		return 0.0
	return 1.0 - pow(1.0 - poke, 1.0 + maxf(dwell_s, 0.0) / POKE_CYCLE_S)


# A defender at `pos` moving `vel`, built as `caps`, `t` after his read: how far
# from where his drift has him by then his stick gets toward `point` — his
# blade's reach and his own thrust to his top speed that way (x) — and how far
# the point is from there (y).
static func _reach(pos: Vector3, vel: Vector3, caps: AISkaterCaps, point: Vector3,
		t: float) -> Vector2:
	var reach: float = caps.max_blade_reach if caps != null else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var top: float = caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var accel: float = caps.max_accel if caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2
	var wx: float = point.x - pos.x - vel.x * t
	var wz: float = point.z - pos.z - vel.z * t
	var d: float = sqrt(wx * wx + wz * wz)
	var toward: float = minf((vel.x * wx + vel.z * wz) / d, top) if d > 1e-6 else 0.0
	return Vector2(reach + _skated(toward, t, top, accel), d)


# Whether a defender at `pos` moving `vel`, built as `caps`, could have his
# stick within `slack` of `point` `t` after his read: his reach at its longest,
# whichever way it points.
static func _could_reach(pos: Vector3, vel: Vector3, caps: AISkaterCaps, point: Vector3,
		t: float, slack: float) -> bool:
	var reach: float = caps.max_blade_reach if caps != null else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var top: float = caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var accel: float = caps.max_accel if caps != null else GameRules.DEFAULT_SKATER_THRUST_M_S2
	var wx: float = point.x - pos.x - vel.x * t
	var wz: float = point.z - pos.z - vel.z * t
	var longest: float = reach + _skated(-top, t, top, accel) + slack
	return wx * wx + wz * wz < longest * longest


# How much further than his drift a skater moving `speed` along a line gets
# along it in `t`, driving at `accel` to `top`.
static func _skated(speed: float, t: float, top: float, accel: float) -> float:
	var t_top: float = maxf(top - speed, 0.0) / accel
	if t <= t_top:
		return 0.5 * accel * t * t
	return 0.5 * accel * t_top * t_top + (top - speed) * (t - t_top)


# The odds the puck is kept along a path: through `points`, reached at `times`
# from now, against `defenders` (index-matched `vels`, and `caps` or empty for
# the league build) read `elapsed_s` after now, carried by a man built as
# `carrier_caps` — his best escape over its first `window_s` (escape_margin, the
# plan's pace at each point from its neighbours), and each defender's race to
# its last point past that, a separate chance.
static func path_keep(points: Array[Vector3], times: Array[float],
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		elapsed_s: float = 0.0, window_s: float = COMMIT_S,
		carrier_caps: AISkaterCaps = null) -> float:
	var n: int = points.size()
	if n == 0 or defenders.is_empty():
		return 1.0
	var margin: float = -INF
	var dwell: float = 0.0
	for k: int in n:
		if times[k] > window_s + 1e-6:
			continue
		var a: int = maxi(k - 1, 0)
		var b: int = mini(k + 1, n - 1)
		var plan_vel: Vector3 = (points[b] - points[a]) / (times[b] - times[a]) if b > a \
				else Vector3.ZERO
		var m: float = escape_margin(points[k], plan_vel, times[k] - elapsed_s, defenders, vels,
				caps, carrier_caps, times[k])
		if m > margin:
			margin = m
			dwell = last_dwell_s
	var keep: float = 1.0 - strip_odds(margin, dwell)
	if times[n - 1] > window_s + 1e-6:
		keep *= _race_keep(points[n - 1], times[n - 1] - elapsed_s, defenders, vels, caps)
	return keep


# The odds the puck is kept on a straight carry from `from` to `to` in
# `arrival_time` (held, when they meet), sampled every DWELL_STEP_S, setting off
# `start_s` from now, carried by a man built as `carrier_caps`: his best escape
# over the carry's first COMMIT_S, and the race to where it ends.
static func carry_keep(from: Vector3, to: Vector3, arrival_time: float,
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		elapsed_s: float = 0.0, start_s: float = 0.0,
		carrier_caps: AISkaterCaps = null) -> float:
	if arrival_time <= 0.0 or defenders.is_empty():
		return 1.0
	var steps: int = maxi(1, ceili(arrival_time / DWELL_STEP_S - 1e-6))
	var read: int = committed_steps(arrival_time, steps)
	var plan_vel: Vector3 = (to - from) / arrival_time
	var margin: float = -INF
	var dwell: float = 0.0
	for k: int in read:
		var f: float = float(k + 1) / steps
		var m: float = escape_margin(from.lerp(to, f), plan_vel,
				start_s + arrival_time * f - elapsed_s, defenders, vels, caps, carrier_caps,
				arrival_time * f)
		if m > margin:
			margin = m
			dwell = last_dwell_s
	var keep: float = 1.0 - strip_odds(margin, dwell)
	if read < steps:
		keep *= _race_keep(to, start_s + arrival_time - elapsed_s, defenders, vels, caps)
	return keep


# The odds no defender's stick is set on `point` before the puck gets there
# `puck_t` after his read, each a separate chance.
static func _race_keep(point: Vector3, puck_t: float, defenders: Array[Vector3],
		vels: Array[Vector3], caps: Array) -> float:
	var has_caps: bool = caps.size() == defenders.size()
	var keep: float = 1.0
	for i: int in defenders.size():
		keep *= 1.0 - SET_STRIP * chance_at(defenders[i], vels[i],
				caps[i] if has_caps else null, point, puck_t)
	return keep


# How many of a carry's `steps` samples, over `arrival_time`, fall in its first
# COMMIT_S (its end is read beside them).
static func committed_steps(arrival_time: float, steps: int) -> int:
	return mini(steps, maxi(1, floori(steps * COMMIT_S / arrival_time + 1e-6)))
