class_name StripeOutline

# A kit stripe round a tube's side as polygons in (U, V): U round the tube 0..1,
# V down it as the stripe's `pos` and `width` are; filled in one color they are
# the stripe. A stripe with a `peak` {depth, count, u} has its centre line
# zigzag `depth` down the tube (up it when negative) at each of `count` peaks
# spaced evenly round it, the first at `u`, and back to `pos` midway between
# them. The stripe's `width` is held square to that line in metres, its bends
# mitred, so stripes stacked on one pos at shrinking widths outline each other
# evenly round every bend. A stripe's optional `fill_below` color fills the tube
# from it to the end (below).
#
# A peaked stripe is a strip per straight run of its line and a wedge on the
# outside of each bend. Their overlaps on a bend's inside are what keep a bend
# sharper than the stripe is wide from folding over itself, as one offset
# outline would. They reach a little past U 0 and 1, and are given a turn either
# way too, so the seam closes.

# A bend under this (its sine, ~0.6°) gets no wedge: the gap it leaves is under
# a texel, and a sliver that thin does not triangulate.
const _MIN_BEND_SIN: float = 0.01


# `length_m` is the tube's length V spans, `girth_m` its girth U spans. `u_shift`
# turns the peak's `u` into the texture's U, for a tube whose kit measures U from
# elsewhere than the texture does.
static func of(stripe: Dictionary, length_m: float, girth_m: float,
		u_shift: float = 0.0) -> Array[PackedVector2Array]:
	var pos: float = float(stripe.pos)
	var half: float = float(stripe.width) * 0.5
	var peak: Dictionary = stripe.get("peak", {})
	if peak.is_empty() or is_zero_approx(float(peak.depth)):
		return [PackedVector2Array([Vector2(0.0, pos - half), Vector2(1.0, pos - half),
				Vector2(1.0, pos + half), Vector2(0.0, pos + half)])]
	var depth: float = float(peak.depth)
	var count: int = int(peak.count)
	var first_u: float = fposmod(float(peak.u) + u_shift, 1.0)
	var to_uv := Vector2(1.0 / girth_m, 1.0 / length_m)
	var h: float = half * length_m
	# The line in metres, a turn's worth from the seam back round to it.
	var line := PackedVector2Array()
	for u: float in _kinks(count, first_u):
		line.append(Vector2(u * girth_m, (pos + _offset(u, depth, count, first_u)) * length_m))
	var n: int = line.size()
	var turn := Vector2(girth_m, 0.0)
	var pieces: Array[PackedVector2Array] = []
	for i: int in n - 1:
		var off: Vector2 = _down_normal(line[i + 1] - line[i]) * h
		pieces.append(PackedVector2Array([line[i] - off, line[i + 1] - off,
				line[i + 1] + off, line[i] + off]))
	for i: int in n - 1:
		# The bend at the seam joins the last run to the first, a turn back.
		var prev: Vector2 = line[i - 1] if i > 0 else line[n - 2] - turn
		var wedge: PackedVector2Array = _wedge(prev, line[i], line[i + 1], h)
		if not wedge.is_empty():
			pieces.append(wedge)
	var out: Array[PackedVector2Array] = []
	for piece: PackedVector2Array in pieces:
		for shift: float in [-1.0, 0.0, 1.0]:
			var moved := PackedVector2Array()
			for p: Vector2 in piece:
				moved.append((p + turn * shift) * to_uv)
			out.append(moved)
	return out


# The tube below a stripe's centre line, to `bottom` in V, as one polygon: what
# its `fill_below` paints, just before the stripe covers its own half of it.
static func below(stripe: Dictionary, u_shift: float = 0.0,
		bottom: float = 2.0) -> PackedVector2Array:
	var pos: float = float(stripe.pos)
	var peak: Dictionary = stripe.get("peak", {})
	var area := PackedVector2Array()
	if peak.is_empty() or is_zero_approx(float(peak.depth)):
		area.append_array(PackedVector2Array([Vector2(0.0, pos), Vector2(1.0, pos)]))
	else:
		var count: int = int(peak.count)
		var first_u: float = fposmod(float(peak.u) + u_shift, 1.0)
		for u: float in _kinks(count, first_u):
			area.append(Vector2(u, pos + _offset(u, float(peak.depth), count, first_u)))
	area.append_array(PackedVector2Array([Vector2(1.0, bottom), Vector2(0.0, bottom)]))
	return area


# How far down the tube the centre line sits at `u`: `depth` on a peak,
# nothing midway between two.
static func _offset(u: float, depth: float, count: int, first_u: float) -> float:
	var phase: float = fposmod((u - first_u) * float(count), 1.0)
	return depth * (1.0 - 2.0 * minf(phase, 1.0 - phase))


# Every U in 0..1 the line bends at, in order: the ends, and each peak and
# valley between them.
static func _kinks(count: int, first_u: float) -> PackedFloat64Array:
	var step: float = 0.5 / float(count)
	var out := PackedFloat64Array([0.0])
	var u: float = first_u - floorf(first_u / step) * step
	if u < 1e-4:
		u += step
	while u < 1.0 - 1e-4:
		out.append(u)
		u += step
	out.append(1.0)
	return out


# The mitre on the outside of the bend at `at`, from the end of one run's strip
# to the start of the next's; empty where the line runs (all but) straight on.
static func _wedge(prev: Vector2, at: Vector2, next: Vector2, h: float) -> PackedVector2Array:
	var d1: Vector2 = at - prev
	var d2: Vector2 = next - at
	var turn: float = d1.cross(d2)
	if absf(turn) < _MIN_BEND_SIN * d1.length() * d2.length():
		return PackedVector2Array()
	# The line turns toward its down normal when the cross is positive; the
	# outside of the bend is the other way.
	var side: float = -signf(turn)
	var n1: Vector2 = _down_normal(d1)
	var n2: Vector2 = _down_normal(d2)
	var bisector: Vector2 = (n1 + n2).normalized()
	var mitre: Vector2 = bisector / bisector.dot(n1) * h
	return PackedVector2Array([at, at + n1 * h * side, at + mitre * side, at + n2 * h * side])


static func _down_normal(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x).normalized()
