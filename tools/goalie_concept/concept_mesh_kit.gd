extends RefCounted

# Flat-shaded faceted mesh accumulator with baked vertex colour — the goalie
# concept's whole geometry vocabulary. Every triangle is oriented from an
# outward hint rather than from vertex order, so concave rings (the pad's leg
# channel) and mirrored frames (det −1 transforms) need no winding care.

var _st := SurfaceTool.new()
var _xf := Transform3D.IDENTITY


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


# Applied to every point and hint passed afterwards — lets a part be authored
# along +Y and laid down along any axis.
func set_transform(xf: Transform3D) -> void:
	_xf = xf


func commit() -> ArrayMesh:
	return _st.commit()


# One triangle, wound so its face points along `out_hint` (Godot's front faces
# wind clockwise seen from outside).
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out_hint: Vector3) -> void:
	a = _xf * a
	b = _xf * b
	c = _xf * c
	out_hint = _xf.basis * out_hint
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	if n.dot(out_hint) < 0.0:
		var t: Vector3 = b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for v: Vector3 in [a, c, b]:
		_st.set_color(col)
		_st.set_normal(n)
		_st.add_vertex(v)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out_hint: Vector3) -> void:
	tri(a, b, c, col, out_hint)
	tri(a, c, d, col, out_hint)


# Superellipse ring in XZ: half-width `hw`, front (−Z) reach `f`, back (+Z)
# reach `b`. p = 2 is an ellipse; larger p squares it toward a box. Starts half
# a step off the front axis so a facet, not a vertex, faces the shooter.
static func ring(hw: float, f: float, b: float, sides: int, p: float = 2.0,
		cx: float = 0.0, cz: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var e: float = 2.0 / p
	for k: int in sides:
		var th: float = TAU * (float(k) + 0.5) / float(sides) - PI * 0.5
		var c: float = cos(th)
		var s: float = sin(th)
		var x: float = hw * signf(c) * pow(absf(c), e)
		var z: float = (f if s < 0.0 else b) * signf(s) * pow(absf(s), e)
		out.append(Vector2(x + cx, z + cz))
	return out


# Lofts rings through heights. `stations`: Array of [y: float,
# ring: PackedVector2Array], top first, all rings the same length. `paint`
# (band, side, centroid) -> Color colours each side facet; caps take the
# colour of the band they close. `band_hints` overrides the radial outward hint
# for bands that face inward (a pocket's walls).
func sweep(stations: Array, paint: Callable, cap_top: bool = true, cap_bottom: bool = true,
		band_hints: Dictionary = {}) -> void:
	var n: int = (stations[0][1] as PackedVector2Array).size()
	for i: int in stations.size() - 1:
		var ya: float = stations[i][0]
		var yb: float = stations[i + 1][0]
		var ra: PackedVector2Array = stations[i][1]
		var rb: PackedVector2Array = stations[i + 1][1]
		var area: float = _signed_area(ra)
		for j: int in n:
			var j1: int = (j + 1) % n
			var a := Vector3(ra[j].x, ya, ra[j].y)
			var b := Vector3(ra[j1].x, ya, ra[j1].y)
			var c := Vector3(rb[j1].x, yb, rb[j1].y)
			var d := Vector3(rb[j].x, yb, rb[j].y)
			var edge: Vector2 = (ra[j1] - ra[j]) + (rb[j1] - rb[j])
			var out2 := Vector2(edge.y, -edge.x) if area > 0.0 else Vector2(-edge.y, edge.x)
			var col: Color = paint.call(i, j, (a + b + c + d) * 0.25)
			var hint: Vector3 = band_hints.get(i, Vector3(out2.x, 0.0, out2.y))
			quad(a, b, c, d, col, hint)
	if cap_top:
		_cap(stations[0][1], stations[0][0], 1.0, paint.call(0, -1, Vector3.ZERO))
	if cap_bottom:
		var last: int = stations.size() - 1
		_cap(stations[last][1], stations[last][0], -1.0,
				paint.call(last - 1, -1, Vector3.ZERO))


func _cap(r: PackedVector2Array, y: float, dir: float, col: Color) -> void:
	var ctr := Vector2.ZERO
	for p: Vector2 in r:
		ctr += p
	ctr /= float(r.size())
	var c3 := Vector3(ctr.x, y, ctr.y)
	for j: int in r.size():
		var j1: int = (j + 1) % r.size()
		tri(c3, Vector3(r[j].x, y, r[j].y), Vector3(r[j1].x, y, r[j1].y), col,
				Vector3(0.0, dir, 0.0))


static func _signed_area(r: PackedVector2Array) -> float:
	var a: float = 0.0
	for j: int in r.size():
		var j1: int = (j + 1) % r.size()
		a += r[j].x * r[j1].y - r[j1].x * r[j].y
	return a


# Chamfered box centred at `c`: a sweep with a squared octagon ring.
func box(c: Vector3, size: Vector3, col: Color, chamfer_p: float = 5.0) -> void:
	var h: Vector3 = size * 0.5
	var r := ring(h.x, h.z, h.z, 8, chamfer_p, c.x, c.z)
	var solid := func(_i: int, _j: int, _ctr: Vector3) -> Color: return col
	sweep([[c.y + h.y, r], [c.y - h.y, r]], solid)


# Faceted ellipsoid centred at `c` with semi-axes `s`.
func ellipsoid(c: Vector3, s: Vector3, col: Color, sides: int = 10, bands: int = 6) -> void:
	var stations: Array = []
	for i: int in bands + 1:
		var ph: float = PI * float(i) / float(bands)
		var rr: float = maxf(sin(ph), 0.02)
		stations.append([c.y + s.y * cos(ph), ring(s.x * rr, s.z * rr, s.z * rr, sides, 2.0, c.x, c.z)])
	var solid := func(_i: int, _j: int, _ctr: Vector3) -> Color: return col
	sweep(stations, solid)
