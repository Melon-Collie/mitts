class_name KeeperKneeBreak
extends MeshInstance3D

# The break above a leg pad's knee: the soft panel that joins the knee stack on
# the shin to the thigh rise on the thigh, so the pad reads as one piece. It is
# lofted between the knee stack's top section and the rise's bottom section
# wherever the pose put them, so it stretches as the knee bends and twists as
# the butterfly turns the shin under the thigh. Drawn only: the stack and the
# rise are the saves.

var _pad_part: int
var _rise_part: int
var _pad_ring: PackedVector3Array
var _rise_ring: PackedVector3Array
var _mesh := ImmediateMesh.new()
var _material: Material = null
# The stack and the rise as last lofted between.
var _pad_xf: Transform3D
var _rise_xf: Transform3D


func _init(pad_part: int, rise_part: int, material: Material) -> void:
	_pad_part = pad_part
	_rise_part = rise_part
	_material = material
	_pad_ring = KeeperGearMeshes.pad_top_ring(KeeperGear.half_extents(pad_part))
	_rise_ring = KeeperGearMeshes.rise_bottom_ring(KeeperGear.half_extents(rise_part))
	mesh = _mesh
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func update(skel: KeeperSkeleton) -> void:
	var pad_xf: Transform3D = KeeperGear.box(skel, _pad_part)
	var rise_xf: Transform3D = KeeperGear.box(skel, _rise_part)
	if pad_xf == _pad_xf and rise_xf == _rise_xf and _mesh.get_surface_count() > 0:
		return
	_pad_xf = pad_xf
	_rise_xf = rise_xf
	var n: int = _pad_ring.size()
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	a.resize(n)
	b.resize(n)
	for i: int in n:
		a[i] = pad_xf * _pad_ring[i]
		b[i] = rise_xf * _rise_ring[i]
	var shift: int = matching_shift(a, b)
	var inside := Vector3.ZERO
	for i: int in n:
		inside += a[i] + b[i]
	inside /= float(2 * n)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for i: int in n:
		var j: int = (i + 1) % n
		var bi: Vector3 = b[(i + shift) % n]
		var bj: Vector3 = b[(j + shift) % n]
		_tri(a[i], a[j], bj, inside)
		_tri(a[i], bj, bi, inside)
	_mesh.surface_end()


# Which rotation of `b` pairs its points with `a`'s most closely, so the loft
# turns the shortest way between two sections that face different ways.
static func matching_shift(a: PackedVector3Array, b: PackedVector3Array) -> int:
	var best: int = 0
	var best_d: float = INF
	for k: int in b.size():
		var d: float = 0.0
		for i: int in a.size():
			d += a[i].distance_squared_to(b[(i + k) % b.size()])
		if d < best_d:
			best_d = d
			best = k
	return best


# One triangle wound to face away from `inside`, flat-shaded.
func _tri(p: Vector3, q: Vector3, r: Vector3, inside: Vector3) -> void:
	var n: Vector3 = (q - p).cross(r - p)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot((p + q + r) / 3.0 - inside) < 0.0:
		n = -n
		var t: Vector3 = q
		q = r
		r = t
	_mesh.surface_set_color(Color.WHITE)
	for v: Vector3 in [p, r, q]:
		_mesh.surface_set_normal(n)
		_mesh.surface_add_vertex(v)
