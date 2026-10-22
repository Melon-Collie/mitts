extends GutTest

# The goalie's rigid parts drawn as one skinned mesh must be the parts: each
# vertex, skinned by its bone, lands where its own node would have drawn it, and
# nothing is drawn twice.

const _SCENE: String = "res://Scenes/Goalie.tscn"


func _goalie() -> Goalie:
	var g: Goalie = (load(_SCENE) as PackedScene).instantiate() as Goalie
	add_child_autofree(g)
	g.position = Vector3(1.0, 0.0, -24.0)
	g.rotation.y = 0.4
	g.apply_uniform(TeamColorRegistry.get_colors(1, 0))
	return g


func _rig(g: Goalie) -> GoalieBodyRig:
	for c: Node in g.get_children():
		if c is GoalieBodyRig:
			return c as GoalieBodyRig
	return null


func _merged_parts(g: Goalie) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_walk(g, out)
	return out


func _walk(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).layers == 0:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_walk(c, out)


func test_the_parts_draw_as_one_surface_and_the_jersey_draws_itself() -> void:
	var g: Goalie = _goalie()
	var rig: GoalieBodyRig = _rig(g)
	assert_gt(rig.part_count(), 10, "the pads, gloves, stick, arms and joints merge")
	assert_eq(rig.body_mesh().mesh.get_surface_count(), 1)
	assert_eq(rig.body_mesh().cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(rig.shadow_mesh().cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(_merged_parts(g).size(), rig.part_count(), "every merged part is off screen")
	assert_ne(g.body_mesh.layers, 0, "the jersey's ShaderMaterial draws itself")
	assert_eq(rig.body_mesh().get_surface_override_material(0), rig.paint().material)


func test_every_vertex_lands_where_its_part_draws_it() -> void:
	var g: Goalie = _goalie()
	var rig: GoalieBodyRig = _rig(g)
	rig.update()
	var arrays: Array = rig.body_mesh().mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var root_inv: Transform3D = g.global_transform.affine_inverse()
	var checked: Dictionary = {}
	for i: int in verts.size():
		var bone: int = bones[i * 4]
		if checked.has(bone):
			continue
		checked[bone] = true
		var part: MeshInstance3D = rig.part(bone)
		if not part.is_visible_in_tree():
			continue
		var skinned: Vector3 = rig.get_bone_pose(bone) * verts[i]
		# Back in the part's own space, a skinned vertex is a point of its mesh.
		var own: Vector3 = (root_inv * part.global_transform).affine_inverse() * skinned
		var aabb: AABB = part.mesh.get_aabb().grow(1e-3)
		assert_true(aabb.has_point(own), "%s: a vertex skinned to %s, outside its mesh" % [
				part.name, own])
	assert_eq(checked.size(), rig.part_count(), "every part has vertices")


# The shadow is the whole figure: a limb left out of it leaves the glove and the
# blocker floating in the shadow, joined to nothing. Only the mask's wire cage,
# finer than a shadow map resolves, stays out.
func test_every_part_but_the_cage_casts() -> void:
	var g: Goalie = _goalie()
	var rig: GoalieBodyRig = _rig(g)
	var bones: PackedInt32Array = rig.shadow_mesh().mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES]
	var casting: Dictionary = {}
	for i: int in range(0, bones.size(), 4):
		casting[bones[i]] = true
	for bone: int in rig.part_count():
		var part: MeshInstance3D = rig.part(bone)
		assert_eq(casting.has(bone), part.name != "Cage", "%s casts" % part.name)
	var limbs := g.get_node("LimbRig") as GoalieLimbRig
	for limb: Node3D in [limbs.glove_upper_arm, limbs.glove_forearm, limbs.blocker_upper_arm,
			limbs.blocker_forearm, limbs.glove_elbow_sphere, limbs.blocker_elbow_sphere,
			limbs.left_hip_connector, limbs.right_hip_connector]:
		assert_eq((limb as MeshInstance3D).layers, 0, "%s is merged" % limb.name)


func test_a_repaint_rebuilds_without_drawing_anything_twice() -> void:
	var g: Goalie = _goalie()
	var before: int = _rig(g).part_count()
	g.apply_uniform(TeamColorRegistry.get_colors(2, 1))
	g.apply_jersey_info("REPAINT", 31)
	assert_eq(_rig(g).part_count(), before)
	assert_eq(_merged_parts(g).size(), before)
	var rigs: int = 0
	for c: Node in g.get_children():
		if c is GoalieBodyRig:
			rigs += 1
			assert_eq(c.get_child_count(), 2, "one body, one shadow")
	assert_eq(rigs, 1)
