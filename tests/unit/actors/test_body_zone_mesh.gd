extends GutTest

# BodyZoneMesh joins surfaces into one without moving a vertex: a body drawn as
# zones must be the body its parts would draw as surfaces.


func _two_surface_mesh() -> ArrayMesh:
	var m := ArrayMesh.new()
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	b.radial_segments = 6
	b.rings = 3
	for prim: PrimitiveMesh in [a, b]:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prim.get_mesh_arrays())
	return m


func test_adding_keeps_every_triangle_and_numbers_each_surface() -> void:
	var src: ArrayMesh = _two_surface_mesh()
	var b := BodyZoneMesh.new()
	for s: int in src.get_surface_count():
		b.add(src.surface_get_arrays(s), 5 + s)
	var merged: ArrayMesh = b.commit()
	assert_eq(merged.get_surface_count(), 1)
	var out: Array = merged.surface_get_arrays(0)
	var out_v: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	var out_i: PackedInt32Array = out[Mesh.ARRAY_INDEX]
	var out_uv2: PackedVector2Array = out[Mesh.ARRAY_TEX_UV2]
	var tri: int = 0
	for s: int in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for k: int in idx.size():
			var merged_vertex: int = out_i[tri + k]
			assert_eq(out_v[merged_vertex], v[idx[k]], "surface %d corner %d" % [s, k])
			assert_eq(int(out_uv2[merged_vertex].x), 5 + s, "zone of surface %d" % s)
		tri += idx.size()
	assert_eq(out_i.size(), tri, "no triangle added or lost")


func test_rigid_bone_bakes_the_transform_and_corrects_normals() -> void:
	var b := BodyZoneMesh.new()
	var box := BoxMesh.new()
	var xform := Transform3D(Basis.from_scale(Vector3(2.0, 1.0, 1.0)), Vector3(0.0, 3.0, 0.0))
	b.add(box.get_mesh_arrays(), 0, 7, xform)
	var out: Array = b.commit().surface_get_arrays(0)
	var src: Array = box.get_mesh_arrays()
	var src_v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var out_v: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	var out_n: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = out[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = out[Mesh.ARRAY_WEIGHTS]
	for i: int in src_v.size():
		assert_almost_eq(out_v[i], xform * src_v[i], Vector3.ONE * 1e-5)
		# A box's face normals are axis-aligned, which a diagonal scale leaves
		# alone once normalised.
		assert_almost_eq(out_n[i], src_n[i], Vector3.ONE * 1e-5)
		assert_eq(bones[i * 4], 7)
		assert_eq(weights[i * 4], 1.0)


func test_a_skinned_surface_keeps_its_own_bones_and_weights() -> void:
	var arrays: Array = BoxMesh.new().get_mesh_arrays()
	var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i: int in n:
		bones.append_array([i % 3, 4, 0, 0])
		weights.append_array([0.75, 0.25, 0.0, 0.0])
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var b := BodyZoneMesh.new()
	b.add(arrays, 0)
	var out: Array = b.commit().surface_get_arrays(0)
	assert_eq(out[Mesh.ARRAY_BONES], bones)
	# The engine stores weights in 16 bits.
	var kept: PackedFloat32Array = out[Mesh.ARRAY_WEIGHTS]
	assert_eq(kept.size(), weights.size())
	for i: int in weights.size():
		assert_almost_eq(kept[i], weights[i], 1e-4)
