extends GutTest

# The body's skin (SkaterConnectedMesh): one skin with no seams.
# Its whole point is that nothing is stitched, so the mesh is held closed — every
# edge shared by exactly two faces — and every vertex's weights well formed, in
# every tuck it is built for.

# How far under the seam's top the shoulder's top still counts as level.
const _LEVEL_M: float = 0.03


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


# The widest |x| of the full tuck's vertices painted `zones`, between heights
# `lo` and `hi` (bind space).
func _widest(zones: Array[int], lo: float, hi: float) -> float:
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_FULL) \
			.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zone_of: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var widest: float = 0.0
	for v: int in verts.size():
		if zones.has(roundi(zone_of[v].x)) and verts[v].y >= lo and verts[v].y <= hi:
			widest = maxf(widest, absf(verts[v].x))
	return widest


func test_a_tucked_jersey_blouses_out_over_the_pants_rim() -> void:
	# The rim stands proud of the jersey going in behind it, and the jersey just
	# above blouses wider still, so it overhangs the rim rather than the rim
	# standing out past it.
	var pants: Array[int] = [SkaterMeshBuilder.LegSurface.THIGH_L,
			SkaterMeshBuilder.LegSurface.THIGH_R]
	var rim: float = _widest(pants, 0.04, 1.0)
	var under_rim: float = _widest(pants, -0.01, 0.01)
	var blouse: float = _widest([SkaterConnectedMesh.zone(SkaterMeshBuilder.UpperSurface.TORSO)],
			0.10, 0.15)
	assert_gt(rim, under_rim, "the rim stands out from the pants below it")
	assert_gt(blouse, rim, "the jersey blouses out past the rim it tucks behind")


# The armhole's seam runs from the shoulders' flat top: its loop's top meets
# the jersey's top row of the armhole, just over the bind arm's joint, so the
# sleeve leaves the shoulder level with it. Below it, the sleeve hangs off a
# dent down the trunk and the shoulders slope off the collar.
func test_the_armhole_starts_at_the_shoulders_top() -> void:
	var loop_top: float = SkaterConnectedMesh._ARMHOLE_CENTRE.y \
			+ SkaterConnectedMesh._ARMHOLE_RADII.y * cos(SkaterConnectedMesh._ARMHOLE_TILT)
	var shoulders_top: float = SkaterConnectedMesh._TORSO_Y_M \
			+ SkaterConnectedMesh._CHEST[SkaterConnectedMesh._ARMHOLE_TOP].x
	assert_almost_eq(loop_top, shoulders_top, 0.015,
			"the armhole's top on the shoulders' top row")
	assert_between(SkaterConnectedMesh._BIND_SHOULDER.y, loop_top - 0.1, loop_top,
			"the bind arm's joint just under it")


func test_the_shoulders_top_runs_out_level_over_the_arm() -> void:
	# Square shoulders: the sleeve leaves the seam's top level, out to the arm's
	# outside at the joint, before it turns down the arm. Without the cap the
	# sleeve slopes straight from the seam to the arm and is well under the top
	# by the time it is that far out.
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	for side: float in [-1.0, 1.0]:
		var zone: int = SkaterConnectedMesh.zone(SkaterConnectedMesh.sleeve_surface(side))
		var top: float = -INF
		for v: int in verts.size():
			if int(round(zones[v].x)) == zone:
				top = maxf(top, verts[v].y)
		var reach: float = 0.0
		for v: int in verts.size():
			if int(round(zones[v].x)) == zone and verts[v].y > top - _LEVEL_M:
				reach = maxf(reach, verts[v].x * side)
		var joint: Vector3 = SkaterConnectedMesh.bind_arm(side)[0]
		assert_gt(reach, joint.x * side + SkaterConnectedMesh.BIND_SLEEVE_RADIUS_M * 0.9,
				"side %d: the shoulder's top reaches the arm's outside while still level" % int(side))


# The lowest V the full body's vertices painted `zone` carry.
func _top_v(zone: int) -> float:
	var arrays: Array = SkaterConnectedMesh.shared_mesh(GearModelRegistry.TUCK_NONE) \
			.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var zones: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var top_v: float = INF
	for v: int in uvs.size():
		if roundi(zones[v].x) == zone:
			top_v = minf(top_v, uvs[v].y)
	return top_v


func test_no_sleeve_samples_its_paint_across_the_wrap() -> void:
	# The cap over the shoulder lies above the arm's joint, where the sleeve's V
	# is held at its top. Held on V = 0 itself the repeating texture filters the
	# cuff's color in, and the cap is drawn half shoulder and half cuff.
	for side: float in [-1.0, 1.0]:
		assert_gte(_top_v(SkaterConnectedMesh.zone(SkaterConnectedMesh.sleeve_surface(side))),
				SleeveDecal.TOP_V, "side %d: the sleeve's top a texel inside its paint" % int(side))


func test_the_neckline_samples_no_paint_across_the_wrap() -> void:
	# On V = 0 the jersey's texture filters its caps' last row into the yoke
	# along the collar's foot.
	assert_gte(_top_v(SkaterConnectedMesh.zone(SkaterMeshBuilder.UpperSurface.TORSO)),
			JerseyDecal.SIDE_TOP_V, "the neckline a texel inside the jersey's paint")
