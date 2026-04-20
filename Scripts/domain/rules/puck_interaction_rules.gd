class_name PuckInteractionRules

# Segment-segment swept detection — tests whether the closest approach between
# the puck's path (puck_prev→puck_curr) and the blade's path (blade_prev→blade_curr)
# falls within `radius`. Handles stationary puck + fast blade swing, which the
# old puck-segment-vs-blade-point test missed when the blade passed through the
# zone entirely within a single tick.

static func check_pickup(
		puck_prev: Vector3, puck_curr: Vector3,
		blade_prev: Vector3, blade_curr: Vector3,
		radius: float) -> bool:
	return _segment_segment_dist_sq(puck_prev, puck_curr, blade_prev, blade_curr) <= radius * radius


static func check_poke(
		puck_prev: Vector3, puck_curr: Vector3,
		blade_prev: Vector3, blade_curr: Vector3,
		radius: float) -> bool:
	return _segment_segment_dist_sq(puck_prev, puck_curr, blade_prev, blade_curr) <= radius * radius


# Minimum squared distance between two line segments (Eberly analytical solution).
# Degenerates correctly when either or both segments have zero length.
static func _segment_segment_dist_sq(
		p0: Vector3, p1: Vector3,
		q0: Vector3, q1: Vector3) -> float:
	var d1: Vector3 = p1 - p0
	var d2: Vector3 = q1 - q0
	var r: Vector3 = p0 - q0
	var a: float = d1.dot(d1)
	var e: float = d2.dot(d2)
	var f: float = d2.dot(r)
	var s: float
	var t: float
	if a <= 1e-10 and e <= 1e-10:
		return r.length_squared()
	if a <= 1e-10:
		s = 0.0
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1.dot(r)
		if e <= 1e-10:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2)
			var denom: float = a * e - b * b
			if abs(denom) > 1e-10:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			else:
				s = 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var closest_p: Vector3 = p0 + d1 * s
	var closest_q: Vector3 = q0 + d2 * t
	return (closest_p - closest_q).length_squared()
