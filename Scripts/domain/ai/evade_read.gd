class_name AIEvadeRead

# The carrier's evadability as a number, read at spots nobody is carrying yet:
# what possession of a spot keeps (AIPossessionValue.base_at). Reads AICarrySpace
# from above; AICarrySpace never reads it.
#
# Where the application layer installs AICarrySpace.native (NativeCarrySpaceFactory,
# the extension built), evade_safety runs in NativeCarrySpace, held to this file by
# test_native_carry_space_parity.gd; the GDScript below is the reference.

const _HORIZON_S: float = AICarrySpace.EVADE_HORIZON_S
const _ANGLES: int = AICarrySpace.EVADE_SAMPLE_ANGLES
# The dwell map reads this much clearance or more as fully safe.
const _SATURATED_M: float = AICarrySpace.POKE_CONTACT_RADIUS_M + AICarrySpace.DWELL_HALF_BAND_M

# Scratch (AI worker only, as the callers are): each sample's bound on the ring
# being swept, and each defender's coast point and slack (_fill_clearance_bounds).
static var _evade_bound: PackedFloat64Array = PackedFloat64Array()
static var _bound_x: PackedFloat64Array = PackedFloat64Array()
static var _bound_z: PackedFloat64Array = PackedFloat64Array()
static var _bound_slack: PackedFloat64Array = PackedFloat64Array()


# clearance_to_safety at the max-clearance seam (AICarrySpace.best_evade_point):
# "can he keep the puck at all", in whatever direction. The same number as
# reading reach_clearance at best_evade_point's answer (test_evade_safety.gd),
# for a fraction of the sweep: it stops at the first sample the dwell map reads
# as fully safe, sweeps the outer ring first, and reads a sample, best-bounded
# first, only when its bound (_clearance_bound) can beat the best read so far —
# a ring whose every sample cannot is skipped.
static func evade_safety(
		carrier_pos: Vector3, carrier_vel: Vector3,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		handle_reach: float, opponent_caps: Array = []) -> float:
	if AICarrySpace.native != null:
		return AICarrySpace.native.evade_safety(carrier_pos, carrier_vel, opponents,
				opponent_vels, handle_reach, AICarrySpace.pack_caps(opponent_caps, opponents.size()))
	return evade_safety_reference(carrier_pos, carrier_vel, opponents, opponent_vels,
			handle_reach, opponent_caps)


# evade_safety in GDScript: the reference the kernel is held to.
static func evade_safety_reference(
		carrier_pos: Vector3, carrier_vel: Vector3,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		handle_reach: float, opponent_caps: Array = []) -> float:
	var proj_x: float = carrier_pos.x + carrier_vel.x * _HORIZON_S
	var proj_z: float = carrier_pos.z + carrier_vel.z * _HORIZON_S
	var best_clear: float = AICarrySpace.reach_clearance(Vector3(proj_x, 0.0, proj_z),
			_HORIZON_S, opponents, opponent_vels, opponent_caps)
	if best_clear >= _SATURATED_M:
		return 1.0
	var env: float = 0.5 * AICarrySpace.MANEUVER_ACCEL_M_S2 * _HORIZON_S * _HORIZON_S \
			+ handle_reach
	if _evade_bound.size() != _ANGLES:
		_evade_bound.resize(_ANGLES)
	_fill_clearance_bounds(opponents, opponent_vels, opponent_caps)
	var rings: Array[float] = AICarrySpace.EVADE_SAMPLE_RINGS
	for ring: int in range(rings.size() - 1, -1, -1):
		var radius: float = env * rings[ring]
		if _clearance_bound(Vector3(proj_x, 0.0, proj_z)) + radius <= best_clear:
			continue
		var top: int = -1
		for k: int in _ANGLES:
			var p: Vector3 = _sample(proj_x, proj_z, radius, k)
			var ub: float = -INF if AICarrySpace.board_gap_m(p) < 0.0 else _clearance_bound(p)
			_evade_bound[k] = ub
			if ub > best_clear and (top < 0 or ub > _evade_bound[top]):
				top = k
		if top < 0:
			continue
		for read_top: int in 2:
			for k: int in _ANGLES:
				if (read_top == 0) != (k == top) or _evade_bound[k] <= best_clear:
					continue
				var c: float = AICarrySpace.reach_clearance(_sample(proj_x, proj_z, radius, k),
						_HORIZON_S, opponents, opponent_vels, opponent_caps, -1.0,
						Vector2.ZERO, 0.0, best_clear)
				if c > best_clear:
					best_clear = c
					if best_clear >= _SATURATED_M:
						return 1.0
	return AICarrySpace.clearance_to_safety(best_clear)


# Envelope sample `k` of the ring at `radius` round the projected centre, at
# best_evade_point's angles.
static func _sample(proj_x: float, proj_z: float, radius: float, k: int) -> Vector3:
	var ang: float = TAU * float(k) / float(_ANGLES)
	return Vector3(proj_x + cos(ang) * radius, 0.0, proj_z + sin(ang) * radius)


# Per defender, for an upper bound on reach_clearance over the horizon with the
# whole window committed (AICarrySpace._committed_clearance): where he coasts to
# by his read, and the most his clearance can exceed his distance from there —
# his stick off, and the least ground his pursuit makes in any direction added
# back. One too slow to have cross-speed to shed makes least ground straight
# away from his motion (brake out, then ramp); a faster one may spend the window
# shedding, so only braking out a retreat bounds him.
static func _fill_clearance_bounds(opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array) -> void:
	var n: int = opponents.size()
	_bound_x.resize(n)
	_bound_z.resize(n)
	_bound_slack.resize(n)
	var tau: float = maxf(0.0, _HORIZON_S - AICarrySpace.EVADE_REACTION_S)
	var coast: float = _HORIZON_S - tau
	var has_caps: bool = opponent_caps.size() == n
	var brake: float = AIArrival.REVERSAL_BRAKE_DECEL_M_S2
	for i: int in n:
		var v: Vector3 = opponent_vels[i] if i < opponent_vels.size() else Vector3.ZERO
		var accel: float = AICarrySpace.MANEUVER_ACCEL_M_S2
		var stick: float = AICarrySpace.EVADE_STICK_REACH_M
		var vmax: float = AIArrival.SKATER_REF_SPEED_M_S
		var grip: float = 1.0
		if has_caps and opponent_caps[i] != null:
			var caps: AISkaterCaps = opponent_caps[i]
			accel = caps.max_accel
			stick = caps.blade_span
			vmax = caps.max_speed
			grip = caps.lateral_grip
		var speed: float = sqrt(v.x * v.x + v.z * v.z)
		var least: float = -speed * speed / (2.0 * brake)
		if speed <= AIArrival.VM_FREE_SHED_M_S * maxf(grip, 0.001):
			var t_b: float = minf(speed / brake, tau)
			least = -speed * t_b + 0.5 * brake * t_b * t_b \
					+ AIStrideRamp.distance_in(0.0, tau - t_b, vmax, accel)
		_bound_x[i] = opponents[i].x + v.x * coast
		_bound_z[i] = opponents[i].z + v.z * coast
		_bound_slack[i] = -least - stick


# The bound _fill_clearance_bounds prepared, at `p`.
static func _clearance_bound(p: Vector3) -> float:
	var bound: float = INF
	for i: int in _bound_x.size():
		var dx: float = p.x - _bound_x[i]
		var dz: float = p.z - _bound_z[i]
		bound = minf(bound, sqrt(dx * dx + dz * dz) + _bound_slack[i])
	return bound
