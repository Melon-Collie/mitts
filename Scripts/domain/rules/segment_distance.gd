class_name SegmentDistance

# Minimum squared distance between segments p0→p1 and q0→q1.
static func dist_sq(
		p0: Vector3, p1: Vector3,
		q0: Vector3, q1: Vector3) -> float:
	var st: Vector2 = params(p0, p1, q0, q1)
	return p0.lerp(p1, st.x).distance_squared_to(q0.lerp(q1, st.y))


# Parameters (s on p0→p1, t on q0→q1) of the closest approach between two line
# segments (Eberly analytical solution). Degenerates correctly when either or
# both segments have zero length.
static func params(
		p0: Vector3, p1: Vector3,
		q0: Vector3, q1: Vector3) -> Vector2:
	var d1: Vector3 = p1 - p0
	var d2: Vector3 = q1 - q0
	var r: Vector3 = p0 - q0
	var a: float = d1.dot(d1)
	var e: float = d2.dot(d2)
	var f: float = d2.dot(r)
	var s: float
	var t: float
	if a <= 1e-10 and e <= 1e-10:
		return Vector2.ZERO
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
	return Vector2(s, t)
