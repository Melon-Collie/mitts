extends GutTest

# The goal frame and its netting are drawn as one mesh per pipe color and one
# netting mesh, not a node per pipe segment and panel: each node is a draw call
# in the main pass and in every shadowed light that reaches the net. The bounds
# hold the merge to where the parts were placed — a pipe appended without its
# transform lands at the goal's origin and moves them.

const EPS: float = 1e-3


func _goal(facing: int) -> HockeyGoal:
	var goal := HockeyGoal.new()
	goal.facing = facing
	add_child_autofree(goal)
	return goal


func _meshes(goal: HockeyGoal) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in goal.get_children():
		if c is MeshInstance3D and not c.is_queued_for_deletion():
			out.append(c as MeshInstance3D)
	return out


func _pipe_bounds(goal: HockeyGoal) -> AABB:
	var box := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(goal):
		if mi.material_override is ShaderMaterial:
			continue
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_two_pipe_colors_and_one_netting() -> void:
	var meshes: Array[MeshInstance3D] = _meshes(_goal(1))
	assert_eq(meshes.size(), 3, "red pipe, white pipe, netting")
	var nets: int = 0
	for mi: MeshInstance3D in meshes:
		assert_eq(mi.mesh.get_surface_count(), 1, "%s is one surface" % mi.name)
		if mi.material_override is ShaderMaterial:
			nets += 1
	assert_eq(nets, 1, "the netting carries the ripple material")


# A pipe merged under a mirrored transform keeps its normals but reverses its
# winding, so it draws inside out. Every triangle's winding must agree with its
# normals the same way.
func test_every_pipe_triangle_winds_the_same_way() -> void:
	for mi: MeshInstance3D in _meshes(_goal(1)):
		if mi.material_override is ShaderMaterial:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var outward: int = 0
		var inward: int = 0
		for t: int in range(0, idx.size(), 3):
			var a: int = idx[t]
			var b: int = idx[t + 1]
			var c: int = idx[t + 2]
			var wound: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
			if wound.length_squared() < 1e-14:
				continue
			if wound.dot(normals[a] + normals[b] + normals[c]) > 0.0:
				outward += 1
			else:
				inward += 1
		assert_true(outward == 0 or inward == 0,
				"%d triangles wind one way and %d the other" % [outward, inward])


func test_frame_spans_the_regulation_footprint() -> void:
	for facing: int in [1, -1]:
		var goal: HockeyGoal = _goal(facing)
		var box: AABB = _pipe_bounds(goal)
		var goal_z: float = goal.goal_line_z()
		var outer_x: float = HockeyGoal.POST_HALF_WIDTH + HockeyGoal.POST_RADIUS
		assert_almost_eq(box.position.x, -outer_x, EPS, "left post's outside, facing %d" % facing)
		assert_almost_eq(box.end.x, outer_x, EPS, "right post's outside, facing %d" % facing)
		assert_almost_eq(box.position.y, 0.0, EPS, "skirt on the ice, facing %d" % facing)
		assert_almost_eq(box.end.y, HockeyGoal.NET_HEIGHT + HockeyGoal.POST_RADIUS, EPS,
				"crossbar top, facing %d" % facing)
		var front: float = goal_z - facing * HockeyGoal.POST_RADIUS
		var back: float = goal_z + facing * (HockeyGoal.BASE_DEPTH + HockeyGoal.POST_RADIUS)
		assert_almost_eq(box.position.z, minf(front, back), EPS, "frame depth, facing %d" % facing)
		assert_almost_eq(box.end.z, maxf(front, back), EPS, "frame depth, facing %d" % facing)
