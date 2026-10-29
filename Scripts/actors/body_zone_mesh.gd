class_name BodyZoneMesh
extends RefCounted

# Builds a body as ONE surface that BodyZonePaint's material draws, from surfaces
# that would otherwise each be a draw call in every pass. Every surface added
# becomes a zone: its index rides in UV2.x. Vertices are copied as they are;
# a surface without UVs or colours gets zeros and white, which no zone that lacks
# them reads.

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
var _colors := PackedColorArray()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _indices := PackedInt32Array()
var _skinned: bool = false


# Adds one surface's arrays as `zone`. With `bone` >= 0 every vertex is made rigid
# to that bone and `xform` is baked in first (normals by its inverse transpose, so
# a non-uniform scale shades as it would on a node, and a mirror's winding
# reversed, as a node's would be); otherwise the surface keeps the bones and
# weights it carries.
func add(arrays: Array, zone: int, bone: int = -1,
		xform: Transform3D = Transform3D.IDENTITY) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: int = verts.size()
	var base: int = _verts.size()
	var normal_basis: Basis = xform.basis.inverse().transposed()
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	for i: int in n:
		_verts.append(xform * verts[i])
		var nrm: Vector3 = (normals as PackedVector3Array)[i] if normals != null else Vector3.UP
		_normals.append((normal_basis * nrm).normalized())
	_append_or_fill_v2(_uvs, arrays[Mesh.ARRAY_TEX_UV], n, Vector2.ZERO)
	for i: int in n:
		_uv2s.append(Vector2(float(zone), 0.0))
	var colors: Variant = arrays[Mesh.ARRAY_COLOR]
	if colors != null:
		_colors.append_array(colors as PackedColorArray)
	else:
		for i: int in n:
			_colors.append(Color.WHITE)
	if bone >= 0:
		_skinned = true
		for i: int in n:
			_bones.append_array([bone, 0, 0, 0])
			_weights.append_array([1.0, 0.0, 0.0, 0.0])
	elif arrays[Mesh.ARRAY_BONES] != null:
		_skinned = true
		_bones.append_array(arrays[Mesh.ARRAY_BONES] as PackedInt32Array)
		_weights.append_array(arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array)
	assert(not _skinned or _bones.size() == _verts.size() * 4,
			"BodyZoneMesh: a surface without bones joined a skinned body")
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i: int in n:
			indices.append(i)
	var mirrored: bool = xform.basis.determinant() < 0.0
	for t: int in range(0, indices.size(), 3):
		_indices.append(base + indices[t])
		_indices.append(base + indices[t + (2 if mirrored else 1)])
		_indices.append(base + indices[t + (1 if mirrored else 2)])


func is_empty() -> bool:
	return _verts.is_empty()


func commit() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	arrays[Mesh.ARRAY_COLOR] = _colors
	if _skinned:
		arrays[Mesh.ARRAY_BONES] = _bones
		arrays[Mesh.ARRAY_WEIGHTS] = _weights
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_or_fill_v2(out: PackedVector2Array, src: Variant, n: int,
		fill: Vector2) -> void:
	if src != null:
		out.append_array(src as PackedVector2Array)
		return
	for i: int in n:
		out.append(fill)
