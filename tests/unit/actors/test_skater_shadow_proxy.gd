extends GutTest

# SkaterShadowProxy — the figure's shadow comes from one shadow-only surface on
# the same skeleton, so a shadowed light draws a skater once instead of once
# per body part.


func before_each() -> void:
	SkaterShadowProxy.set_enabled(true)


func after_each() -> void:
	SkaterShadowProxy.set_enabled(true)


func _skater() -> Skater:
	var sk: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(sk)
	sk.set_process(false)
	sk.set_physics_process(false)
	return sk


func _body(sk: Skater) -> Skeleton3D:
	return sk.mesh_root.get_node("BodyRig") as Skeleton3D


func _proxy(sk: Skater) -> MeshInstance3D:
	return _body(sk).get_node("ShadowProxy") as MeshInstance3D


func test_the_figure_casts_through_the_proxy_alone() -> void:
	var sk: Skater = _skater()
	for node_name: String in ["LegMesh", "UpperMesh"]:
		var mesh: MeshInstance3D = _body(sk).get_node(node_name) as MeshInstance3D
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s does not cast" % node_name)
	var proxy: MeshInstance3D = _proxy(sk)
	assert_eq(proxy.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(proxy.mesh.get_surface_count(), 1, "one draw per shadowed light")
	assert_true(proxy.visible)


func test_the_proxy_is_the_figure_bone_for_bone() -> void:
	# Every vertex of both rig meshes appears in the proxy, weighted to the same
	# body-skeleton bone — so the skeleton poses the shadow exactly as it poses
	# the body, attribute scaling included.
	var merged: Array = SkaterShadowProxy.shared_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = merged[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = merged[Mesh.ARRAY_BONES]
	var at: int = 0
	# The upper skin's binds name their bones (the tail's are past the parts');
	# the leg skin's are offset by LEG_BONE_OFFSET.
	var upper_skin: Skin = SkaterMeshBuilder.shared_upper_skin()
	var sources: Array = [
		[SkaterMeshBuilder.shared_upper_skin_mesh(), -1],
		[SkaterMeshBuilder.shared_leg_skin_mesh(), SkaterBodySkeleton.LEG_BONE_OFFSET],
	]
	for source: Array in sources:
		var mesh: ArrayMesh = source[0]
		var offset: int = source[1]
		for surface: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var src_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for i: int in src_verts.size():
				var bone: int = upper_skin.get_bind_bone(src_bones[i * 4]) if offset < 0 \
						else src_bones[i * 4] + offset
				if verts[at + i] != src_verts[i] or bones[(at + i) * 4] != bone:
					fail_test("vertex %d of a surface diverged from its source" % i)
					return
			at += src_verts.size()
	assert_eq(at, verts.size(), "nothing but the two rig meshes")
	assert_eq(SkaterShadowProxy.shared_skin().get_bind_count(), SkaterBodySkeleton.BODY_BONE_COUNT)


func test_a_ghost_casts_no_shadow() -> void:
	var sk: Skater = _skater()
	sk.set_ghost(true)
	assert_false(_proxy(sk).visible, "translucent, so no shadow")
	sk.set_ghost(false)
	assert_true(_proxy(sk).visible)


func test_the_setting_reaches_skaters_already_on_the_ice() -> void:
	var sk: Skater = _skater()
	SkaterShadowProxy.set_enabled(false)
	assert_false(_proxy(sk).visible)
	assert_eq(sk.stick_mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"the stick goes with the body")
	SkaterShadowProxy.set_enabled(true)
	assert_true(_proxy(sk).visible)
	assert_eq(sk.stick_mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
