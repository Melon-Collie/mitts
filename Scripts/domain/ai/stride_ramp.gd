class_name AIStrideRamp

# The stride's ramp from `v0` toward `vmax`, as the AI's travel models price it
# — mirrors SkaterMovementRules' drive: constant accel up to the power knee,
# then constant power (dv/dt = P/v, so v² grows linearly in time and distance
# goes as v³), then cruise.

# Fraction of the stride's push the movement model nets after glide losses
# over a 0→top ramp. Measured (tests/unit/ai/test_time_to_arrive_calibration.gd).
const EFFICIENCY: float = 1.0

# Samples over the head-start horizon. The peak is where the two speeds meet, so
# the grid's error there is second order: ~2 cm over a 4 s horizon.
const HEAD_START_SAMPLES: int = 24


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
# `brake_m_s2` before the stride begins. Peaks where the chaser matches the
# lead's speed; the horizon bounds a lead the chaser never matches.
static func head_start(lead_v0: float, lead_vmax: float, lead_accel: float,
		chase_v0: float, chase_vmax: float, chase_accel: float,
		brake_m_s2: float, horizon_s: float) -> float:
	if horizon_s <= 0.0:
		return 0.0
	var best: float = 0.0
	var step: float = horizon_s / float(HEAD_START_SAMPLES)
	for i: int in range(1, HEAD_START_SAMPLES + 1):
		var t: float = step * float(i)
		var gained: float = signed_distance_in(lead_v0, t, lead_vmax,
				lead_accel, brake_m_s2) - signed_distance_in(
				chase_v0, t, chase_vmax, chase_accel, brake_m_s2)
		best = maxf(best, gained)
	return best


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
