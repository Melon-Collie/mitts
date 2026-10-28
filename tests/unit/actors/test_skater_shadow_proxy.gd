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
	# Every vertex of both rig meshes appears in the proxy, each influence bound
	# to the same body-skeleton bone by the same bind pose as the rig's skin binds
	# it — so the skeleton poses the shadow exactly as it poses the body,
	# attribute scaling and either handedness's sleeves included.
	var merged: Array = SkaterShadowProxy.shared_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = merged[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = merged[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = merged[Mesh.ARRAY_WEIGHTS]
	for top_on_right: bool in [true, false]:
		var proxy_skin: Skin = SkaterShadowProxy.shared_skin(top_on_right)
		var at: int = 0
		var sources: Array = [
			[SkaterMeshBuilder.shared_upper_skin_mesh(),
					SkaterMeshBuilder.shared_upper_skin(top_on_right)],
			[SkaterMeshBuilder.shared_leg_skin_mesh(), SkaterMeshBuilder.shared_leg_skin()],
		]
		for source: Array in sources:
			var mesh: ArrayMesh = source[0]
			var skin: Skin = source[1]
			for surface: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var src_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var src_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				for i: int in src_verts.size():
					if verts[at + i] != src_verts[i]:
						fail_test("vertex %d of a surface diverged from its source" % i)
						return
					for j: int in 4:
						var w: float = src_weights[i * 4 + j]
						if w == 0.0:
							continue
						var mine: int = bones[(at + i) * 4 + j]
						var theirs: int = src_bones[i * 4 + j]
						if weights[(at + i) * 4 + j] != w \
								or proxy_skin.get_bind_bone(mine) != skin.get_bind_bone(theirs) \
								or proxy_skin.get_bind_pose(mine) != skin.get_bind_pose(theirs):
							fail_test("vertex %d of a surface is bound apart from its source" % i)
							return
				at += src_verts.size()
		assert_eq(at, verts.size(), "nothing but the two rig meshes")


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
