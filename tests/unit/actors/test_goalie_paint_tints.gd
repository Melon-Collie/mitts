extends GutTest

# GoalieMeshBuilder draws detail the flat-shaded solids cannot show by shape
# alone — the mask's cage, the pads' creases and leg channel — as baked
# per-facet vertex tints, which GoalieUniformCoordinator's paint multiplies
# under the kit colour. A material that does not read vertex colour drops the
# tint without a sound, and only a render would show it missing.


func test_goalie_paint_reads_the_baked_tints() -> void:
	var g: Goalie = load("res://Scenes/Goalie.tscn").instantiate()
	add_child_autofree(g)
	g.apply_uniform(TeamColorRegistry.get_colors(0, 0))
	var tinted: int = 0
	var stack: Array[Node] = [g]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		if (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			continue
		tinted += 1
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		assert_not_null(mat, "%s carries a tint but no paint" % mi.name)
		if mat != null:
			assert_true(mat.vertex_color_use_as_albedo,
					"%s bakes a tint its paint ignores" % mi.get_path())
	assert_gt(tinted, 2, "the mask and both pads bake tints")
