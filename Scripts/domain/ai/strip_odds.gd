class_name AIStripOdds

# Whether a defender takes the puck off a path the carrier skates
# (docs/strip-interception-plan.md): one chance per defender — can his stick get
# to some point of the path, set, before the puck is there — graded by the
# arrival clock's own error, and taken with the odds a set stick strips. His
# options from where he is and how he is moving, never a guess at what he will
# do. Measured against a worst-case interceptor
# (tests/instruments/ai/test_interceptor_truth.gd), never against our defending
# bots. A leaf — GameRules, AIArrival and AISkaterCaps only.

# How long before the puck his stick has to be there to take it (s): a stick
# arriving with less strips next to nothing.
const SET_S: float = 0.25
# The odds a stick set on the path strips a carrier who keeps to it.
const SET_STRIP: float = 0.88
# A straight carry's samples (s).
const DWELL_STEP_S: float = 0.1
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
# build), has his stick set on `point` by `puck_t` from his read: his arrival
# clock to within his blade's reach of it, graded across the clock's error as
# the arrival race grades a race.
static func chance_at(pos: Vector3, vel: Vector3, caps: AISkaterCaps, point: Vector3,
		puck_t: float) -> float:
	var reach: float = caps.max_blade_reach if caps != null \
			else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M
	var to := Vector3(point.x - pos.x, 0.0, point.z - pos.z)
	var d: float = to.length()
	var arrive: float = 0.0
	if d > reach:
		arrive = AIArrival.time_to_arrive_caps(pos, pos + to * ((d - reach) / d), vel, caps)
	var band: float = maxf(AIArrival.ERROR_FLOOR_S, AIArrival.ERROR_FRAC * arrive)
	return clampf(0.5 + (puck_t - arrive - SET_S) / (2.0 * band), 0.0, 1.0)


# The odds the puck is kept along a path: through `points`, reached at `times`
# from now, against `defenders` (index-matched `vels`, and `caps` or empty for
# the league build) read `elapsed_s` after now, over its first `window_s` and its
# last point. Each defender's one chance is his best on it; the chances are
# separate.
static func path_keep(points: Array[Vector3], times: Array[float],
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		elapsed_s: float = 0.0, window_s: float = COMMIT_S) -> float:
	var has_caps: bool = caps.size() == defenders.size()
	var keep: float = 1.0
	for i: int in defenders.size():
		var best: float = 0.0
		for k: int in points.size():
			if times[k] > window_s + 1e-6 and k < points.size() - 1:
				continue
			best = maxf(best, chance_at(defenders[i], vels[i], caps[i] if has_caps else null,
					points[k], times[k] - elapsed_s))
			if best >= 1.0:
				break
		keep *= 1.0 - SET_STRIP * best
	return keep


# The odds the puck is kept on a straight carry from `from` to `to` in
# `arrival_time` (held, when they meet), sampled every DWELL_STEP_S, setting off
# `start_s` from now: over the carry's first COMMIT_S and where it ends.
static func carry_keep(from: Vector3, to: Vector3, arrival_time: float,
		defenders: Array[Vector3], vels: Array[Vector3], caps: Array = [],
		elapsed_s: float = 0.0, start_s: float = 0.0) -> float:
	if arrival_time <= 0.0 or defenders.is_empty():
		return 1.0
	var has_caps: bool = caps.size() == defenders.size()
	var steps: int = maxi(1, ceili(arrival_time / DWELL_STEP_S - 1e-6))
	var read: int = committed_steps(arrival_time, steps)
	var keep: float = 1.0
	for i: int in defenders.size():
		var best: float = 0.0
		for k: int in read:
			var f: float = float(k + 1) / steps
			best = maxf(best, chance_at(defenders[i], vels[i], caps[i] if has_caps else null,
					from.lerp(to, f), start_s + arrival_time * f - elapsed_s))
			if best >= 1.0:
				break
		if read < steps and best < 1.0:
			best = maxf(best, chance_at(defenders[i], vels[i], caps[i] if has_caps else null,
					to, start_s + arrival_time - elapsed_s))
		keep *= 1.0 - SET_STRIP * best
	return keep


# How many of a carry's `steps` samples, over `arrival_time`, fall in its first
# COMMIT_S (its end is read beside them).
static func committed_steps(arrival_time: float, steps: int) -> int:
	return mini(steps, maxi(1, floori(steps * COMMIT_S / arrival_time + 1e-6)))
