class_name BoardArc
extends RefCounted

# Distance along the dasher boards' centerline, as a rounded rectangle of half
# extents `half_w` (x) × `half_l` (z) and corner radius `r`. Arc 0 is the south
# end of the east straight and arc runs counter-clockwise seen from above — the
# walk HockeyRink lays its perimeter stations on, so an arc here lands at the
# same place on the wall as BoardAdBandBuilder's cumulative arc over them
# (test_board_arc.gd holds the two together).


static func perimeter(half_w: float, half_l: float, r: float) -> float:
	return 4.0 * (half_l - r) + 4.0 * (half_w - r) + TAU * r


# Arc of the centerline point nearest `xz`, in [0, perimeter). A point inside
# the rink projects straight out onto the wall it faces, or radially onto a
# corner's arc.
static func arc_at(xz: Vector2, half_w: float, half_l: float, r: float) -> float:
	var cx: float = half_w - r
	var cz: float = half_l - r
	var side: float = 2.0 * cz
	var end: float = 2.0 * cx
	var quarter: float = r * PI / 2.0
	var s: float
	if absf(xz.x) > cx and absf(xz.y) > cz:
		# A corner: the angle from its centre, swept counter-clockwise from the
		# east (+x) direction, as the stations sweep it.
		var centre := Vector2(signf(xz.x) * cx, signf(xz.y) * cz)
		var start: float
		var base: float
		if xz.x > 0.0 and xz.y > 0.0:
			start = 0.0
			base = side
		elif xz.x < 0.0 and xz.y > 0.0:
			start = PI / 2.0
			base = side + quarter + end
		elif xz.x < 0.0:
			start = PI
			base = 2.0 * side + 2.0 * quarter + end
		else:
			start = 1.5 * PI
			base = 2.0 * side + 3.0 * quarter + 2.0 * end
		# Measured from the corner's own start and held to its quarter: a point on
		# a junction can round into the corner at an angle of +0 rather than 2π.
		var swept: float = wrapf((xz - centre).angle() - start, -PI, PI)
		s = base + r * clampf(swept, 0.0, PI / 2.0)
	elif absf(xz.y) <= cz and (absf(xz.x) > cx or half_w - absf(xz.x) <= half_l - absf(xz.y)):
		# A side wall (east or west).
		var z: float = clampf(xz.y, -cz, cz)
		if xz.x >= 0.0:
			s = z + cz
		else:
			s = side + 2.0 * quarter + end + (cz - z)
	else:
		# An end wall (north or south).
		var x: float = clampf(xz.x, -cx, cx)
		if xz.y >= 0.0:
			s = side + quarter + (cx - x)
		else:
			s = 2.0 * side + 3.0 * quarter + end + (x + cx)
	return fposmod(s, perimeter(half_w, half_l, r))


# The centerline point at arc `s` (wrapped onto the loop).
static func point_at(s: float, half_w: float, half_l: float, r: float) -> Vector2:
	var cx: float = half_w - r
	var cz: float = half_l - r
	var side: float = 2.0 * cz
	var end: float = 2.0 * cx
	var quarter: float = r * PI / 2.0
	var t: float = fposmod(s, perimeter(half_w, half_l, r))
	if t < side:
		return Vector2(half_w, t - cz)
	t -= side
	if t < quarter:
		return Vector2(cx, cz) + r * Vector2.from_angle(t / r)
	t -= quarter
	if t < end:
		return Vector2(cx - t, half_l)
	t -= end
	if t < quarter:
		return Vector2(-cx, cz) + r * Vector2.from_angle(PI / 2.0 + t / r)
	t -= quarter
	if t < side:
		return Vector2(-half_w, cz - t)
	t -= side
	if t < quarter:
		return Vector2(-cx, -cz) + r * Vector2.from_angle(PI + t / r)
	t -= quarter
	if t < end:
		return Vector2(-cx + t, -half_l)
	t -= end
	return Vector2(cx, -cz) + r * Vector2.from_angle(1.5 * PI + t / r)
