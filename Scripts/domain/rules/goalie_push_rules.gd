class_name GoaliePushRules

# The upright goalie's lateral push, as kinematics: accelerate at `accel` from
# rest up to `max_speed`, and — for a push that has to END somewhere — brake on
# the lead edge at `accel` × GameRules.GOALIE_EDGE_STOP_DECEL_RATIO to a stop on
# the spot. The keeper's footwork is the second kind (KeeperFootwork's edge
# stop).
#
# Which one a caller wants is the question it is asking:
# - SET (set_reach, time_to_set, push_progress): is he square and stopped on a
#   spot in time? Every re-square race, and every planner read of where he will
#   be standing at a release — a goalie is not covering a one-timer until he is
#   set on it.
# - CRUISE (cruise_reach): how far can a pad get across a shot already in
#   flight? A pad moving through the puck's line stops it; he need not stop.


# Distance covered in `t` from rest, accelerating and then holding top speed.
static func cruise_reach(max_speed: float, accel: float, t: float) -> float:
	if t <= 0.0 or max_speed <= 0.0:
		return 0.0
	if accel <= 0.0:
		return max_speed * t
	var t_ramp: float = max_speed / accel
	if t <= t_ramp:
		return 0.5 * accel * t * t
	return max_speed * t - 0.5 * max_speed * t_ramp


# The farthest spot he can push to and be stopped on within `t`, from rest.
static func set_reach(max_speed: float, accel: float, t: float) -> float:
	if t <= 0.0 or max_speed <= 0.0:
		return 0.0
	if accel <= 0.0:
		return max_speed * t
	var k: float = _push_and_stop_k(accel)
	var peak: float = t / k
	if peak <= max_speed:
		return 0.5 * peak * t
	return 0.5 * max_speed * max_speed * k + max_speed * (t - max_speed * k)


# The inverse of set_reach: how long a push to a spot `dist` away takes, stop
# included.
static func time_to_set(dist: float, max_speed: float, accel: float) -> float:
	if dist <= 0.0:
		return 0.0
	if accel <= 0.0:
		return dist / maxf(max_speed, 0.001)
	var k: float = _push_and_stop_k(accel)
	var full: float = 0.5 * max_speed * max_speed * k
	if dist <= full:
		return sqrt(2.0 * k * dist)
	return max_speed * k + (dist - full) / max_speed


# How far along a push to a spot `dist` away he is `t` into it, from rest —
# accelerating, cruising or braking — clamped at the spot once he is set on it.
static func push_progress(dist: float, max_speed: float, accel: float, t: float) -> float:
	if dist <= 0.0 or t <= 0.0:
		return 0.0
	if accel <= 0.0:
		return minf(dist, max_speed * t)
	var brake: float = accel * GameRules.GOALIE_EDGE_STOP_DECEL_RATIO
	var peak: float = minf(max_speed, sqrt(2.0 * dist / _push_and_stop_k(accel)))
	var t_up: float = peak / accel
	if t <= t_up:
		return 0.5 * accel * t * t
	var d_up: float = 0.5 * peak * t_up
	var d_down: float = peak * peak / (2.0 * brake)
	var t_cruise: float = (dist - d_up - d_down) / peak
	if t <= t_up + t_cruise:
		return d_up + peak * (t - t_up)
	var tau: float = minf(t - t_up - t_cruise, peak / brake)
	return minf(dist, d_up + peak * t_cruise + peak * tau - 0.5 * brake * tau * tau)


# The fastest he can still be travelling `dist` short of his spot and stop on
# it.
static func braking_speed_cap(dist: float, accel: float) -> float:
	return sqrt(2.0 * maxf(accel, 0.0) * GameRules.GOALIE_EDGE_STOP_DECEL_RATIO * maxf(dist, 0.0))


# Seconds per (m/s) of a push's peak that the push-then-stop spends: one over
# the push, one over the stop.
static func _push_and_stop_k(accel: float) -> float:
	return 1.0 / accel + 1.0 / (accel * GameRules.GOALIE_EDGE_STOP_DECEL_RATIO)
