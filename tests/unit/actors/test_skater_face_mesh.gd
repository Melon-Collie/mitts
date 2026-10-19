extends GutTest

# The face sits under the face gear, which rides a sphere only a centimetre or so
# off the head ball — so a nose or chin tuned to read better pokes through the
# visor, cage and fishbowl without anything else noticing.


func test_the_face_stays_inside_the_face_gear() -> void:
	var gear_r: float = minf(SkaterMeshBuilder._CAGE_RADIUS,
			SkaterMeshBuilder._FACE_SHIELD_RADIUS)
	var face: ArrayMesh = SkaterFaceMesh.build(SkaterMeshBuilder.HEAD_RADIUS, 10, 5)
	var verts: PackedVector3Array = face.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_gt(verts.size(), 0, "the face has geometry")
	var worst: float = 0.0
	for v: Vector3 in verts:
		# Helmet-local: the head ball sits HEAD_FORWARD_M ahead of the helmet centre.
		var r: float = (v + Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)).length()
		worst = maxf(worst, r)
	assert_lt(worst, gear_r - 0.001,
			"the face reaches %.4f m from the helmet centre; the face gear is at %.3f"
			% [worst, gear_r])


func test_the_face_has_its_dark_features() -> void:
	var face: ArrayMesh = SkaterFaceMesh.build(SkaterMeshBuilder.HEAD_RADIUS, 10, 5)
	var colors: PackedColorArray = face.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var eyes: int = 0
	for c: Color in colors:
		# Vertex colour is stored at 8 bits a channel.
		if _near(c, SkaterFaceMesh.EYE_TINT):
			eyes += 1
	assert_eq(eyes, 12, "two eyes, two triangles each")


# The features are vertex tints, which the skin material drops silently unless it
# reads vertex colour — and the skin tone repaint must keep that.
func test_the_painted_skin_reads_the_face_tints() -> void:
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate()
	add_child_autofree(skater)
	skater.set_skin_tone(3)
	var mat: StandardMaterial3D = skater.upper_surface_material(
			SkaterMeshBuilder.UpperSurface.HELMET_SKIN)
	assert_true(mat.vertex_color_use_as_albedo, "the skin multiplies the face's tints")
	var colors: PackedColorArray = SkaterMeshBuilder.shared_helmet_assembly() \
			.surface_get_arrays(SkaterMeshBuilder.HELMET_SURF_SKIN)[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = SkaterMeshBuilder.shared_helmet_assembly() \
			.surface_get_arrays(SkaterMeshBuilder.HELMET_SURF_SKIN)[Mesh.ARRAY_VERTEX]
	assert_eq(colors.size(), verts.size(), "every skin vertex carries a tint")
	var white: int = 0
	for c: Color in colors:
		if _near(c, Color.WHITE):
			white += 1
	assert_gt(white, colors.size() / 2, "the head and neck stay pure skin")


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.02
