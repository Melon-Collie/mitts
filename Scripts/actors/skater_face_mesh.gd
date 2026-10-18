class_name SkaterFaceMesh
extends RefCounted

# The face on the skater's head ball: a brow, two eyes, a nose, a mouth and a
# chin, laid on the ball's own front facets in its frame (head centre at the
# origin, face toward −Z). Everything is skin-painted; the darker features are
# vertex tints the skin material multiplies under the player's skin tone, so the
# face costs no surface of its own.
#
# The face gear rides 0.157 m (cage) to 0.158 m (shields) from the helmet centre,
# which is HEAD_FORWARD_M behind this origin, so nothing here may stand more than
# about a centimetre proud of the facets — test_skater_face_mesh.gd holds it.

const EYE_TINT := Color(0.12, 0.10, 0.10)
const BROW_TINT := Color(0.42, 0.34, 0.30)
const MOUTH_TINT := Color(0.62, 0.45, 0.44)

# (centre x, centre y, half width, half height) on the eye band.
const _EYE := Vector4(0.040, 0.012, 0.013, 0.006)
# Brow ledge: (inner x, outer x, bottom y, top y, standing out).
const _BROW: Array[float] = [0.012, 0.062, 0.026, 0.036, 0.004]
# Nose: bridge top y, tip (y, standing out), base (y, half width).
const _NOSE_TOP_Y: float = 0.016
const _NOSE_TIP := Vector2(-0.026, 0.009)
const _NOSE_BASE := Vector2(-0.034, 0.016)
# Mouth: (y, half width, half height) — drawn as two halves, one per facet,
# because a single patch across the centre column would sink behind its ridge.
const _MOUTH := Vector3(-0.058, 0.020, 0.0035)
# Chin: (top y, point y, bottom y, half width, standing out).
const _CHIN: Array[float] = [-0.080, -0.094, -0.104, 0.024, 0.008]
# Off-facet lift for the painted patches, so they never z-fight the ball.
const _DECAL_LIFT_M: float = 0.0012

var _radius: float
var _lon: int
var _lat: int


static func build(radius: float, lon: int, lat: int) -> ArrayMesh:
	var face := SkaterFaceMesh.new()
	face._radius = radius
	face._lon = lon
	face._lat = lat
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading, like every part
	face._emit(st)
	st.generate_normals()
	return st.commit()


# `src` with every vertex tinted white — pure skin — so it merges with the face
# into one surface that carries a tint throughout.
static func untinted(src: ArrayMesh) -> ArrayMesh:
	var arrays: Array = src.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR] = colors
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _emit(st: SurfaceTool) -> void:
	for side: float in [-1.0, 1.0]:
		_patch(st, Vector2(side * _EYE.x, _EYE.y), Vector2(_EYE.z, _EYE.w), EYE_TINT)
		_brow(st, side)
		_patch(st, Vector2(side * _MOUTH.y * 0.5, _MOUTH.x),
				Vector2(_MOUTH.y * 0.5, _MOUTH.z), MOUTH_TINT)
	_nose(st)
	_chin(st)


# A flat tinted patch lying on the facet under (x, y).
func _patch(st: SurfaceTool, c: Vector2, half: Vector2, tint: Color) -> void:
	var corners: Array[Vector3] = []
	for d: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var p: Vector2 = c + d * half
		corners.append(_proud(p.x, p.y, _DECAL_LIFT_M))
	var out: Vector3 = _out(c.x, c.y)
	_tri(st, corners[0], corners[1], corners[2], out, tint)
	_tri(st, corners[0], corners[2], corners[3], out, tint)


# A ledge over each eye: its face stands proud, its underside reads in shadow.
func _brow(st: SurfaceTool, side: float) -> void:
	var x0: float = side * _BROW[0]
	var x1: float = side * _BROW[1]
	var y0: float = _BROW[2]
	var y1: float = _BROW[3]
	var lift: float = _BROW[4]
	var top_in: Vector3 = _proud(x0, y1, 0.0)
	var top_out: Vector3 = _proud(x1, y1, 0.0)
	var face_in: Vector3 = _proud(x0, y0, lift)
	var face_out: Vector3 = _proud(x1, y0, lift)
	var root_in: Vector3 = _proud(x0, y0 - 0.004, -0.001)
	var root_out: Vector3 = _proud(x1, y0 - 0.004, -0.001)
	var out: Vector3 = _out(side * 0.035, (y0 + y1) * 0.5)
	_tri(st, top_in, top_out, face_out, out, BROW_TINT)
	_tri(st, top_in, face_out, face_in, out, BROW_TINT)
	_tri(st, face_in, face_out, root_out, Vector3.DOWN + out, BROW_TINT)
	_tri(st, face_in, root_out, root_in, Vector3.DOWN + out, BROW_TINT)


# A wedge down the centre column: the bridge rises from flush to the tip, two
# cheek-facing sides, and an underside.
func _nose(st: SurfaceTool) -> void:
	var top: Vector3 = _proud(0.0, _NOSE_TOP_Y, -0.001)
	var tip: Vector3 = _proud(0.0, _NOSE_TIP.x, _NOSE_TIP.y)
	var left: Vector3 = _proud(-_NOSE_BASE.y, _NOSE_BASE.x, -0.001)
	var right: Vector3 = _proud(_NOSE_BASE.y, _NOSE_BASE.x, -0.001)
	var fwd: Vector3 = _out(0.0, _NOSE_TIP.x)
	_tri(st, top, tip, left, fwd + Vector3.LEFT, Color.WHITE)
	_tri(st, top, right, tip, fwd + Vector3.RIGHT, Color.WHITE)
	_tri(st, tip, right, left, Vector3.DOWN, Color.WHITE)


# Three columns (both sides and the centre ridge), so no edge spans the ridge
# and sinks behind it.
func _chin(st: SurfaceTool) -> void:
	var hw: float = _CHIN[3]
	var lift: float = _CHIN[4]
	var top: Array[Vector3] = []
	var point: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for k: float in [-1.0, 0.0, 1.0]:
		top.append(_proud(k * hw, _CHIN[0], -0.001))
		point.append(_proud(k * hw * 0.7, _CHIN[1], lift))
		bottom.append(_proud(k * hw * 0.8, _CHIN[2], -0.001))
	var out: Vector3 = _out(0.0, _CHIN[1])
	for i: int in 2:
		_tri(st, top[i], top[i + 1], point[i + 1], out + Vector3.UP * 0.3, Color.WHITE)
		_tri(st, top[i], point[i + 1], point[i], out + Vector3.UP * 0.3, Color.WHITE)
		_tri(st, point[i], point[i + 1], bottom[i + 1], out + Vector3.DOWN, Color.WHITE)
		_tri(st, point[i], bottom[i + 1], bottom[i], out + Vector3.DOWN, Color.WHITE)
	_tri(st, top[0], point[0], bottom[0], out + Vector3.LEFT, Color.WHITE)
	_tri(st, top[2], bottom[2], point[2], out + Vector3.RIGHT, Color.WHITE)


# One triangle wound so its face points along `out` (Godot's front faces are
# clockwise: the normal is (c − a) × (b − a)).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3,
		tint: Color) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var t: Vector3 = b
		b = c
		c = t
	st.set_color(tint)
	st.set_uv(Vector2.ZERO)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# The point on the ball's front facet under (x, y), moved `lift` along the
# facet's outward normal. The front three columns are the ones a face sits on,
# and each facet is a planar quad between two rings, so the point is found by
# interpolating its corners.
func _proud(x: float, y: float, lift: float) -> Vector3:
	return _on_facet(x, y) + _out(x, y) * lift


func _out(x: float, y: float) -> Vector3:
	var q: Array[Vector3] = _facet(x, y)
	var n: Vector3 = (q[3] - q[0]).cross(q[1] - q[0]).normalized()
	return n if n.dot(_on_facet(x, y)) > 0.0 else -n


func _on_facet(x: float, y: float) -> Vector3:
	var q: Array[Vector3] = _facet(x, y)
	var t: float = (q[0].y - y) / (q[0].y - q[3].y)
	var hi: Vector3 = q[0].lerp(q[3], t)   # centre column at this height
	var lo: Vector3 = q[1].lerp(q[2], t)   # side column at this height
	var s: float = x / lo.x if absf(lo.x) > 1e-6 else 0.0
	return hi.lerp(lo, s)


# Corners of the facet under (x, y): centre column top, side column top, side
# column bottom, centre column bottom.
func _facet(x: float, y: float) -> Array[Vector3]:
	var j: int = 0
	while j < _lat - 1 and _ring_y(j + 1) > y:
		j += 1
	var centre: int = _lon / 2   # dead front (−Z)
	var side: int = centre + (-1 if x > 0.0 else 1)
	return [_vertex(j, centre), _vertex(j, side), _vertex(j + 1, side), _vertex(j + 1, centre)]


func _ring_y(j: int) -> float:
	return _radius * cos(PI * float(j) / float(_lat))


# The ball's ring vertex, with _build_ball's convention (U from +Z toward +X).
func _vertex(j: int, k: int) -> Vector3:
	var v: float = float(j) / float(_lat)
	var r: float = _radius * sin(PI * v)
	var theta: float = TAU * float(k) / float(_lon)
	return Vector3(sin(theta) * r, _ring_y(j), cos(theta) * r)
