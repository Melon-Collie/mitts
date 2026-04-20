class_name PuckInteractionRules

# Swept sphere interaction detection — tests whether the puck's path from
# puck_prev to puck_curr passes within `radius` of the given contact point.
# Equivalent to a capsule (swept sphere) vs point test. Provides tunneling
# protection at any speed; at 240 Hz the puck travels at most ~0.125 m/tick
# at max speed, so instantaneous tests would rarely miss, but swept is correct.

static func check_pickup(
		puck_prev: Vector3, puck_curr: Vector3,
		blade_pos: Vector3, radius: float) -> bool:
	return _point_segment_dist_sq(puck_prev, puck_curr, blade_pos) <= radius * radius


static func check_poke(
		puck_prev: Vector3, puck_curr: Vector3,
		blade_pos: Vector3, radius: float) -> bool:
	return _point_segment_dist_sq(puck_prev, puck_curr, blade_pos) <= radius * radius


static func _point_segment_dist_sq(
		seg_start: Vector3, seg_end: Vector3, point: Vector3) -> float:
	var d: Vector3 = seg_end - seg_start
	var len_sq: float = d.length_squared()
	if len_sq < 1e-10:
		return (point - seg_start).length_squared()
	var t: float = clampf(d.dot(point - seg_start) / len_sq, 0.0, 1.0)
	var closest: Vector3 = seg_start + d * t
	return (closest - point).length_squared()
