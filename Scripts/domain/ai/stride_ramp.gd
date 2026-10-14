class_name AIStrideRamp

# The stride's ramp from `v0` toward `vmax`, as the AI's travel models price it
# — mirrors SkaterMovementRules' drive: constant accel up to the power knee,
# then constant power (dv/dt = P/v, so v² grows linearly in time and distance
# goes as v³), then cruise.

# Fraction of the stride's push the movement model nets after glide losses
# over a 0→top ramp, measured against the real movement core
# (tests/unit/ai/test_time_to_arrive_calibration.gd).
const EFFICIENCY: float = 1.0

# head_start's crossing search: the scan only has to bracket where the speeds
# meet (both ramps are monotone, so one crossing per bracket), and the bisection
# pins it to horizon / (SCAN · 2^BISECT) — under a millisecond.
const HEAD_START_SCAN: int = 8
const HEAD_START_BISECT: int = 12


# `accel_m_s2` is the skater's standing-start push; EFFICIENCY nets out
# the glide losses. time_to_cover is distance → time, distance_in its inverse;
# all closed-form, no allocation.
static func time_to_cover(v0: float, dist: float, vmax: float,
		accel_m_s2: float) -> float:
	var a: float = maxf(accel_m_s2 * EFFICIENCY, 0.001)
	var p: float = a * GameRules.DEFAULT_SKATER_POWER_KNEE_M_S
	var knee: float = minf(GameRules.DEFAULT_SKATER_POWER_KNEE_M_S, vmax)
	var v: float = clampf(v0, 0.0, vmax)
	var r: float = maxf(dist, 0.0)
	var t: float = 0.0
	if v < knee:
		var d_a: float = (knee * knee - v * v) / (2.0 * a)
		if r <= d_a:
			return (sqrt(v * v + 2.0 * a * r) - v) / a
		t += (knee - v) / a
		r -= d_a
		v = knee
	if v < vmax:
		var d_b: float = (vmax * vmax * vmax - v * v * v) / (3.0 * p)
		if r <= d_b:
			var v_end: float = pow(v * v * v + 3.0 * p * r, 1.0 / 3.0)
			return t + (v_end * v_end - v * v) / (2.0 * p)
		t += (vmax * vmax - v * v) / (2.0 * p)
		r -= d_b
	return t + r / vmax


# Distance the stride needs to build from rest to `speed` (no cruise).
static func distance_to_speed(speed: float, accel_m_s2: float) -> float:
	var a: float = maxf(accel_m_s2 * EFFICIENCY, 0.001)
	var knee: float = GameRules.DEFAULT_SKATER_POWER_KNEE_M_S
	var v: float = maxf(speed, 0.0)
	if v <= knee:
		return v * v / (2.0 * a)
	return knee * knee / (2.0 * a) + (v * v * v - knee * knee * knee) / (3.0 * a * knee)


# The most ground a skater starting along a line at `lead_v0` gains on one
# starting at `chase_v0`, both driving flat out along it from now, within
# `horizon_s`. A negative start is momentum the wrong way, braked out at
# `brake_m_s2` before the stride begins. The gain peaks where the chaser's speed
# comes up to the lead's, so this finds that crossing (a coarse scan of the speed
# difference, then bisection) and prices the distance there and at the horizon
# — two distance pairs rather than a fine distance sweep, since it runs per
# attacker on every station dispatch.
static func head_start(lead_v0: float, lead_vmax: float, lead_accel: float,
		chase_v0: float, chase_vmax: float, chase_accel: float,
		brake_m_s2: float, horizon_s: float) -> float:
	if horizon_s <= 0.0:
		return 0.0
	var best: float = _gain_at(horizon_s, lead_v0, lead_vmax, lead_accel,
			chase_v0, chase_vmax, chase_accel, brake_m_s2)
	var step: float = horizon_s / float(HEAD_START_SCAN)
	var t0: float = 0.0
	var d0: float = _speed_gap(0.0, lead_v0, lead_vmax, lead_accel,
			chase_v0, chase_vmax, chase_accel, brake_m_s2)
	for i: int in range(1, HEAD_START_SCAN + 1):
		var t1: float = step * float(i)
		var d1: float = _speed_gap(t1, lead_v0, lead_vmax, lead_accel,
				chase_v0, chase_vmax, chase_accel, brake_m_s2)
		if d0 > 0.0 and d1 <= 0.0:
			var lo: float = t0
			var hi: float = t1
			for _j: int in HEAD_START_BISECT:
				var mid: float = 0.5 * (lo + hi)
				if _speed_gap(mid, lead_v0, lead_vmax, lead_accel, chase_v0,
						chase_vmax, chase_accel, brake_m_s2) > 0.0:
					lo = mid
				else:
					hi = mid
			best = maxf(best, _gain_at(lo, lead_v0, lead_vmax, lead_accel,
					chase_v0, chase_vmax, chase_accel, brake_m_s2))
		t0 = t1
		d0 = d1
	return maxf(best, 0.0)


static func _gain_at(t: float, lead_v0: float, lead_vmax: float,
		lead_accel: float, chase_v0: float, chase_vmax: float,
		chase_accel: float, brake_m_s2: float) -> float:
	return signed_distance_in(lead_v0, t, lead_vmax, lead_accel, brake_m_s2) \
			- signed_distance_in(chase_v0, t, chase_vmax, chase_accel, brake_m_s2)


static func _speed_gap(t: float, lead_v0: float, lead_vmax: float,
		lead_accel: float, chase_v0: float, chase_vmax: float,
		chase_accel: float, brake_m_s2: float) -> float:
	return signed_speed_at(lead_v0, t, lead_vmax, lead_accel, brake_m_s2) \
			- signed_speed_at(chase_v0, t, chase_vmax, chase_accel, brake_m_s2)


# The speed signed_distance_in integrates: the stride's speed `time` into the
# ramp, with a wrong-way start braked out first (negative until it is).
static func signed_speed_at(v0: float, time: float, vmax: float,
		accel_m_s2: float, brake_m_s2: float) -> float:
	if v0 < 0.0:
		var t_brake: float = -v0 / maxf(brake_m_s2, 0.001)
		if time <= t_brake:
			return v0 + brake_m_s2 * time
		return speed_at(0.0, time - t_brake, vmax, accel_m_s2)
	return speed_at(v0, time, vmax, accel_m_s2)


static func speed_at(v0: float, time: float, vmax: float,
		accel_m_s2: float) -> float:
	var a: float = maxf(accel_m_s2 * EFFICIENCY, 0.001)
	var p: float = a * GameRules.DEFAULT_SKATER_POWER_KNEE_M_S
	var knee: float = minf(GameRules.DEFAULT_SKATER_POWER_KNEE_M_S, vmax)
	var v: float = clampf(v0, 0.0, vmax)
	var tau: float = maxf(time, 0.0)
	if v < knee:
		var t_a: float = (knee - v) / a
		if tau <= t_a:
			return v + a * tau
		tau -= t_a
		v = knee
	if v < vmax:
		return minf(sqrt(v * v + 2.0 * p * tau), vmax)
	return v


# distance_in that also takes a start against the line (`v0 < 0`): that
# momentum brakes out at `brake_m_s2`, losing ground, then the ramp starts from
# rest. Signed: ground lost is negative.
static func signed_distance_in(v0: float, time: float, vmax: float,
		accel_m_s2: float, brake_m_s2: float) -> float:
	if v0 >= 0.0:
		return distance_in(v0, time, vmax, accel_m_s2)
	var t_brake: float = -v0 / maxf(brake_m_s2, 0.001)
	if time <= t_brake:
		return v0 * time + 0.5 * brake_m_s2 * time * time
	return -v0 * v0 / (2.0 * maxf(brake_m_s2, 0.001)) \
			+ distance_in(0.0, time - t_brake, vmax, accel_m_s2)


static func distance_in(v0: float, time: float, vmax: float,
		accel_m_s2: float) -> float:
	var a: float = maxf(accel_m_s2 * EFFICIENCY, 0.001)
	var p: float = a * GameRules.DEFAULT_SKATER_POWER_KNEE_M_S
	var knee: float = minf(GameRules.DEFAULT_SKATER_POWER_KNEE_M_S, vmax)
	var v: float = clampf(v0, 0.0, vmax)
	var tau: float = maxf(time, 0.0)
	var d: float = 0.0
	if v < knee:
		var t_a: float = (knee - v) / a
		if tau <= t_a:
			return v * tau + 0.5 * a * tau * tau
		d += (knee * knee - v * v) / (2.0 * a)
		tau -= t_a
		v = knee
	if v < vmax:
		var t_b: float = (vmax * vmax - v * v) / (2.0 * p)
		if tau <= t_b:
			var v_end: float = sqrt(v * v + 2.0 * p * tau)
			return d + (v_end * v_end * v_end - v * v * v) / (3.0 * p)
		d += (vmax * vmax * vmax - v * v * v) / (3.0 * p)
		tau -= t_b
	return d + vmax * tau
