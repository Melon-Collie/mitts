class_name AIEvadeRead

# The carrier's evadability: the best odds he keeps the puck over the evasion
# horizon (AICarrySpace.EVADE_HORIZON_S) by any cut his skating and hands can
# make, each priced along its ROUTE. Read for the carrier's current safety
# (AIRoleCarrier) and at spots nobody is carrying yet, for what possession of a
# spot keeps (AIPossessionValue.base_at). Reads AICarrySpace from above;
# AICarrySpace never reads it.
#
# A cut is a point of his handling envelope: his body accelerates up to
# MANEUVER_ACCEL_M_S2 off where his momentum takes him (short of the first body
# he skates into, AIArrival.body_contact_time), and his hands carry the puck the
# rest of the way out, up to his handle reach. The puck is read a quarter and half
# way through the horizon, moving (the transit map), and at the end, dwelling (the
# dwell map), each against the defence at that moment; the cut keeps it at the
# least of the three. Read at its end alone, a cut past a man the carrier skates
# by inside his stick, or through him, read as the open ice beyond him. The stop
# is one of the cuts: the hockey stop (AIArrival.REVERSAL_BRAKE_DECEL_M_S2) is
# gentler than the thrust the envelope spends, so the braked route is inside it.
#
# Where the application layer installs AICarrySpace.native (NativeCarrySpaceFactory,
# the extension built), evade_safety runs in NativeCarrySpace, held to this file by
# test_native_carry_space_parity.gd; the GDScript below is the reference.

const _HORIZON_S: float = AICarrySpace.EVADE_HORIZON_S
const _ANGLES: int = AICarrySpace.EVADE_SAMPLE_ANGLES
# Where through the horizon the moving puck is read (its end is the dwell read).
const _MOVING_FRACS: Array[float] = [0.5, 0.25]

# Scratch (AI worker only, as the callers are): each sample's bound on the ring
# being swept, and each defender's coast point and slack (_fill_clearance_bounds).
static var _evade_bound: PackedFloat64Array = PackedFloat64Array()
static var _bound_x: PackedFloat64Array = PackedFloat64Array()
static var _bound_z: PackedFloat64Array = PackedFloat64Array()
static var _bound_slack: PackedFloat64Array = PackedFloat64Array()

# The safety best_evade_point's seam is kept at, by its last call.
static var seam_safety: float = 0.0


# The evadability [0, 1]. The same number as best_evade_point's seam_safety
# (test_evade_safety.gd), for a fraction of the sweep: it stops at the first cut
# kept for certain, sweeps the outer ring first, and prices a cut, best-bounded
# first, only when the bound on its end (_clearance_bound) can beat the best so
# far — a ring whose every cut cannot is skipped — and stops pricing it once one
# of its reads falls to the best.
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
	var t_c: float = AIArrival.body_contact_time(carrier_pos, carrier_vel, opponents,
			opponent_vels, AICarrySpace.EVADE_BODY_CONTACT_M, _HORIZON_S)
	var best: float = _cut_safety(carrier_pos, carrier_vel, t_c, 0.0, 0.0, 0.0, 0.0,
			opponents, opponent_vels, opponent_caps, -INF)
	if best >= 1.0:
		return 1.0
	var body_m: float = 0.5 * AICarrySpace.MANEUVER_ACCEL_M_S2 * _HORIZON_S * _HORIZON_S
	var env: float = body_m + handle_reach
	var proj := Vector3(carrier_pos.x + carrier_vel.x * t_c, 0.0,
			carrier_pos.z + carrier_vel.z * t_c)
	if _evade_bound.size() != _ANGLES:
		_evade_bound.resize(_ANGLES)
	_fill_clearance_bounds(opponents, opponent_vels, opponent_caps)
	var rings: Array[float] = AICarrySpace.EVADE_SAMPLE_RINGS
	for ring: int in range(rings.size() - 1, -1, -1):
		var radius: float = env * rings[ring]
		if AICarrySpace.clearance_to_safety(_clearance_bound(proj) + radius) <= best:
			continue
		var body: float = minf(radius, body_m)
		var hands: float = radius - body
		var top: int = -1
		for k: int in _ANGLES:
			var p: Vector3 = _cut_end(carrier_pos, carrier_vel, t_c, k, body, hands)
			var ub: float = -INF if AICarrySpace.board_gap_m(p) < 0.0 \
					else AICarrySpace.clearance_to_safety(_clearance_bound(p))
			_evade_bound[k] = ub
			if ub > best and (top < 0 or ub > _evade_bound[top]):
				top = k
		if top < 0:
			continue
		for read_top: int in 2:
			for k: int in _ANGLES:
				if (read_top == 0) != (k == top) or _evade_bound[k] <= best:
					continue
				var ang: float = TAU * float(k) / float(_ANGLES)
				var s: float = _cut_safety(carrier_pos, carrier_vel, t_c, cos(ang), sin(ang),
						body, hands, opponents, opponent_vels, opponent_caps, best)
				if s > best:
					best = s
					if best >= 1.0:
						return 1.0
	return best


# The seam: the end of the cut evade_safety keeps the puck best by, swept whole
# (the centre on a tie, then the first cut found), its safety left in
# seam_safety. Returned as a world point (y = 0).
static func best_evade_point(
		carrier_pos: Vector3, carrier_vel: Vector3,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		handle_reach: float, opponent_caps: Array = []) -> Vector3:
	var t_c: float = AIArrival.body_contact_time(carrier_pos, carrier_vel, opponents,
			opponent_vels, AICarrySpace.EVADE_BODY_CONTACT_M, _HORIZON_S)
	var body_m: float = 0.5 * AICarrySpace.MANEUVER_ACCEL_M_S2 * _HORIZON_S * _HORIZON_S
	var env: float = body_m + handle_reach
	var seam := Vector3(carrier_pos.x + carrier_vel.x * t_c, 0.0,
			carrier_pos.z + carrier_vel.z * t_c)
	seam_safety = _cut_safety(carrier_pos, carrier_vel, t_c, 0.0, 0.0, 0.0, 0.0,
			opponents, opponent_vels, opponent_caps, -INF)
	for ring: float in AICarrySpace.EVADE_SAMPLE_RINGS:
		var radius: float = env * ring
		var body: float = minf(radius, body_m)
		var hands: float = radius - body
		for k: int in _ANGLES:
			var p: Vector3 = _cut_end(carrier_pos, carrier_vel, t_c, k, body, hands)
			if AICarrySpace.board_gap_m(p) < 0.0:
				continue
			var ang: float = TAU * float(k) / float(_ANGLES)
			var s: float = _cut_safety(carrier_pos, carrier_vel, t_c, cos(ang), sin(ang),
					body, hands, opponents, opponent_vels, opponent_caps, -INF)
			if s > seam_safety:
				seam_safety = s
				seam = p
	return seam


# Where cut `k` of the ring `body` + `hands` out puts the puck at the horizon.
static func _cut_end(carrier_pos: Vector3, carrier_vel: Vector3, t_c: float, k: int,
		body: float, hands: float) -> Vector3:
	var ang: float = TAU * float(k) / float(_ANGLES)
	return _cut_at(carrier_pos, carrier_vel, t_c, cos(ang), sin(ang), body, hands, 1.0)


# The puck `frac` of the way through a cut along (dir_x, dir_z): his momentum's
# ground to then, short of contact at `t_c`, the body's push off it (from rest in
# that direction, so the square of the time) and the hands' even reach out.
static func _cut_at(carrier_pos: Vector3, carrier_vel: Vector3, t_c: float,
		dir_x: float, dir_z: float, body: float, hands: float, frac: float) -> Vector3:
	var coast: float = minf(_HORIZON_S * frac, t_c)
	var off: float = body * frac * frac + hands * frac
	return Vector3(carrier_pos.x + carrier_vel.x * coast + dir_x * off, 0.0,
			carrier_pos.z + carrier_vel.z * coast + dir_z * off)


# The odds a cut keeps the puck: the least of its two moving reads and its end.
# `beat`: a cut that cannot beat it is not priced exactly (a value at or under it
# comes back), so a defender scan stops once its read falls to it.
static func _cut_safety(carrier_pos: Vector3, carrier_vel: Vector3, t_c: float,
		dir_x: float, dir_z: float, body: float, hands: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3], opponent_caps: Array,
		beat: float) -> float:
	var s: float = AICarrySpace.clearance_to_safety(AICarrySpace.reach_clearance(
			_cut_at(carrier_pos, carrier_vel, t_c, dir_x, dir_z, body, hands, 1.0),
			_HORIZON_S, opponents, opponent_vels, opponent_caps, -1.0, Vector2.ZERO, 0.0,
			_dwell_clearance(beat)))
	if s <= beat:
		return s
	for frac: float in _MOVING_FRACS:
		s = minf(s, AICarrySpace.transit_clearance_to_safety(AICarrySpace.reach_clearance(
				_cut_at(carrier_pos, carrier_vel, t_c, dir_x, dir_z, body, hands, frac),
				_HORIZON_S * frac, opponents, opponent_vels, opponent_caps, -1.0,
				Vector2.ZERO, 0.0, _transit_clearance(beat))))
		if s <= beat:
			return s
	return s


# The clearance each map reads as `safety` (−INF for none to beat).
static func _dwell_clearance(safety: float) -> float:
	if safety == -INF:
		return -INF
	return safety * 2.0 * AICarrySpace.DWELL_HALF_BAND_M \
			+ AICarrySpace.POKE_CONTACT_RADIUS_M - AICarrySpace.DWELL_HALF_BAND_M


static func _transit_clearance(safety: float) -> float:
	if safety == -INF:
		return -INF
	return AICarrySpace.TRANSIT_STRIP_CLEAR_M \
			+ safety * (AICarrySpace.TRANSIT_SAFE_CLEAR_M - AICarrySpace.TRANSIT_STRIP_CLEAR_M)


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
