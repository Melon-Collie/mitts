extends GutTest

# The connected-body prototype (SkaterConnectedMesh): one skin with no seams.
# Its whole point is that nothing is stitched, so the mesh is held closed — every
# edge shared by exactly two faces — and every vertex's weights well formed, in
# every tuck it is built for.


func _edges_used_other_than_twice(mesh: ArrayMesh) -> int:
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var uses: Dictionary = {}
	for t: int in range(0, verts.size(), 3):
		for e: int in 3:
			var a: Vector3 = verts[t + e]
			var b: Vector3 = verts[t + (e + 1) % 3]
			var key: String = "%s|%s" % [a, b] if str(a) < str(b) else "%s|%s" % [b, a]
			uses[key] = int(uses.get(key, 0)) + 1
	var open: int = 0
	for key: String in uses:
		if uses[key] != 2:
			open += 1
	return open


func test_the_skin_is_closed_in_every_tuck() -> void:
	for tuck: int in [GearModelRegistry.TUCK_NONE, GearModelRegistry.TUCK_FULL,
			GearModelRegistry.TUCK_LEFT, GearModelRegistry.TUCK_RIGHT]:
		assert_eq(_edges_used_other_than_twice(SkaterConnectedMesh.shared_mesh(tuck)), 0,
				"tuck %d: every edge of the connected skin borders exactly two faces" % tuck)


func test_every_vertex_rides_real_binds_by_a_whole_weight() -> void:
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var binds: int = SkaterConnectedMesh.shared_skin().get_bind_count()
	assert_eq(binds, SkaterConnectedMesh.bind_rests().size())
	var bad: int = 0
	for v: int in range(0, bones.size(), 4):
		var total: float = 0.0
		for i: int in 4:
			total += weights[v + i]
			if weights[v + i] > 0.0 and (bones[v + i] < 0 or bones[v + i] >= binds):
				bad += 1
		if absf(total - 1.0) > 1e-4:
			bad += 1
	assert_eq(bad, 0, "every vertex's weights sum to one over binds the skin has")


func test_the_sleeve_frames_rest_where_the_bind_arm_puts_them() -> void:
	# The rig poses the sleeve's bones with sleeve_frames over the live arm, so at
	# the bind arm they must land on their binds' rests: the skin is then the
	# identity there, and the sleeve is drawn as it was authored.
	var rests: Array[Transform3D] = SkaterConnectedMesh.bind_rests()
	for side: int in 2:
		var frames: Array[Transform3D] = SkaterConnectedMesh.sleeve_frames(
				SkaterConnectedMesh.bind_arm(-1.0 if side == 0 else 1.0))
		var first: int = SkaterConnectedMesh.Bind.UPPER_L if side == 0 \
				else SkaterConnectedMesh.Bind.UPPER_R
		for i: int in 3:
			assert_true(frames[i].is_equal_approx(rests[first + i]),
					"side %d frame %d sits on its rest" % [side, i])
