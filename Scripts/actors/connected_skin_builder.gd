class_name ConnectedSkinBuilder
extends RefCounted

# Builds one flat-shaded skinned surface out of shared vertices: a vertex is a
# position with its binds and weights, and every face that uses it copies those,
# so two faces that share a vertex can never come apart under any pose — which
# is the point of a connected skin. Each face carries its own normal, UVs and
# BodyZonePaint zone (UV2.x), the way the rig's other bodies are drawn.
#
# Faces are wound outward from the `inside` point each is given, so a builder
# laying rings need not track which way round each one runs.

const MAX_INFLUENCES: int = 4

var _pos := PackedVector3Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()

# Faces as laid, emitted at commit so a vertex's weights can still be changed
# after the faces round it are laid (reweight).
var _face_ids := PackedInt32Array()
var _face_normals := PackedVector3Array()
var _face_uvs := PackedVector2Array()
var _face_zones := PackedInt32Array()


# A shared vertex at `p` (bind space), riding `binds` by `weights`.
func vertex(p: Vector3, binds: Array, weights: Array) -> int:
	assert(binds.size() == weights.size() and binds.size() <= MAX_INFLUENCES)
	var total: float = 0.0
	for w: float in weights:
		total += w
	_pos.append(p)
	for i: int in MAX_INFLUENCES:
		_bones.append(int(binds[i]) if i < binds.size() else 0)
		_weights.append(float(weights[i]) / total if i < weights.size() else 0.0)
	return _pos.size() - 1


func reweight(id: int, binds: Array, weights: Array) -> void:
	assert(binds.size() == weights.size() and binds.size() <= MAX_INFLUENCES)
	var total: float = 0.0
	for w: float in weights:
		total += w
	for i: int in MAX_INFLUENCES:
		_bones[id * MAX_INFLUENCES + i] = int(binds[i]) if i < binds.size() else 0
		_weights[id * MAX_INFLUENCES + i] = float(weights[i]) / total if i < weights.size() else 0.0


# Moves a vertex before any face round it is laid (a face takes its winding and
# normal from where its corners are when it is laid).
func move(id: int, p: Vector3) -> void:
	_pos[id] = p


func position(id: int) -> Vector3:
	return _pos[id]


func centroid(ids: PackedInt32Array) -> Vector3:
	var sum := Vector3.ZERO
	for id: int in ids:
		sum += _pos[id]
	return sum / float(maxi(ids.size(), 1))


# `unwrap` takes each U to within half a turn of the first corner's, for UVs that
# wrap round an axis (the texture repeats).
func tri(a: int, b: int, c: int, uva: Vector2, uvb: Vector2, uvc: Vector2, zone: int,
		inside: Vector3, unwrap: bool = false) -> void:
	var pa: Vector3 = _pos[a]
	var pb: Vector3 = _pos[b]
	var pc: Vector3 = _pos[c]
	# Godot's front face winds clockwise: its outward normal is (c − a) × (b − a).
	var n: Vector3 = (pc - pa).cross(pb - pa)
	if n.length_squared() < 1e-14:
		return
	if n.dot((pa + pb + pc) / 3.0 - inside) < 0.0:
		var t: int = b
		b = c
		c = t
		var tuv: Vector2 = uvb
		uvb = uvc
		uvc = tuv
		n = -n
	if unwrap:
		uvb.x = uva.x + wrapf(uvb.x - uva.x, -0.5, 0.5)
		uvc.x = uva.x + wrapf(uvc.x - uva.x, -0.5, 0.5)
	_face_ids.append_array([a, b, c])
	_face_normals.append(n.normalized())
	_face_uvs.append_array([uva, uvb, uvc])
	_face_zones.append(zone)


# Corners in order round the quad; split along a–c.
func quad(a: int, b: int, c: int, d: int, uva: Vector2, uvb: Vector2, uvc: Vector2,
		uvd: Vector2, zone: int, inside: Vector3, unwrap: bool = false) -> void:
	if unwrap:
		uvb.x = uva.x + wrapf(uvb.x - uva.x, -0.5, 0.5)
		uvc.x = uva.x + wrapf(uvc.x - uva.x, -0.5, 0.5)
		uvd.x = uva.x + wrapf(uvd.x - uva.x, -0.5, 0.5)
	tri(a, b, c, uva, uvb, uvc, zone, inside)
	tri(a, c, d, uva, uvc, uvd, zone, inside)


# `a_loop` turned and run to match `b_loop` vertex for vertex: each of
# `b_loop`'s against the one of `a_loop` that turns with it least.
func aligned(a_loop: PackedInt32Array, b_loop: PackedInt32Array) -> PackedInt32Array:
	var n: int = a_loop.size()
	var best_cost: float = INF
	var best_shift: int = 0
	var best_dir: int = 1
	for dir: int in [1, -1]:
		for shift: int in n:
			var cost: float = 0.0
			for m: int in n:
				cost += _pos[a_loop[posmod(shift + dir * m, n)]].distance_squared_to(_pos[b_loop[m]])
			if cost < best_cost:
				best_cost = cost
				best_shift = shift
				best_dir = dir
	var out := PackedInt32Array()
	for m: int in n:
		out.append(a_loop[posmod(best_shift + best_dir * m, n)])
	return out


# Joins two closed loops already run vertex for vertex with quads, each corner's
# UV `uv` of its position; U wraps round the loops.
func join(a_loop: PackedInt32Array, b_loop: PackedInt32Array, join_zone: int, uv: Callable,
		inside: Vector3) -> void:
	var n: int = a_loop.size()
	for m: int in n:
		var a0: int = a_loop[m]
		var a1: int = a_loop[(m + 1) % n]
		var b0: int = b_loop[m]
		var b1: int = b_loop[(m + 1) % n]
		quad(a0, a1, b1, b0, uv.call(_pos[a0]), uv.call(_pos[a1]), uv.call(_pos[b1]),
				uv.call(_pos[b0]), join_zone, inside, true)


# A fan from `centre` over a closed ring of vertex ids, cap UVs round `uv_centre`
# as SkaterMeshBuilder._cap lays them.
func fan(ring: PackedInt32Array, centre: int, uv_centre: Vector2, fan_zone: int,
		inside: Vector3) -> void:
	var n: int = ring.size()
	for k: int in n:
		var t0: float = TAU * float(k) / float(n)
		var t1: float = TAU * float(k + 1) / float(n)
		tri(centre, ring[k], ring[(k + 1) % n], uv_centre,
				uv_centre + Vector2(sin(t0), cos(t0)) * 0.24,
				uv_centre + Vector2(sin(t1), cos(t1)) * 0.24, fan_zone, inside)


func commit() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var zones := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for corner: int in _face_ids.size():
		var id: int = _face_ids[corner]
		@warning_ignore("integer_division")
		var face: int = corner / 3
		verts.append(_pos[id])
		normals.append(_face_normals[face])
		zones.append(Vector2(float(_face_zones[face]), 0.0))
		for i: int in MAX_INFLUENCES:
			bones.append(_bones[id * MAX_INFLUENCES + i])
			weights.append(_weights[id * MAX_INFLUENCES + i])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = _face_uvs
	arrays[Mesh.ARRAY_TEX_UV2] = zones
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
