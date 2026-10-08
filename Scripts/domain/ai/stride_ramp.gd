class_name AIStrideRamp

# The stride's ramp from `v0` toward `vmax`, as the AI's travel models price it
# — mirrors SkaterMovementRules' drive: constant accel up to the power knee,
# then constant power (dv/dt = P/v, so v² grows linearly in time and distance
# goes as v³), then cruise.

# Fraction of the stride's push the movement model nets after glide losses
# over a 0→top ramp. Measured (tests/unit/ai/test_time_to_arrive_calibration.gd).
const EFFICIENCY: float = 1.0


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
