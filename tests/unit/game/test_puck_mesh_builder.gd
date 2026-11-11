extends GutTest

# PuckMeshBuilder invariants — the same silent-drift risks the skater/goalie
# builder suites pin (see test_skater_mesh_builder.gd for the reasoning),
# for the one puck mesh.


func test_puck_is_outward_wound_inside_its_envelope() -> void:
	var mesh: ArrayMesh = PuckMeshBuilder._build_puck()
	var vol: float = 0.0
	for surf: int in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]
		for i in range(0, verts.size(), 3):
			vol += verts[i].dot(verts[i + 1].cross(verts[i + 2])) / 6.0
	var arrays: Array = mesh.surface_get_arrays(0)
	assert_lt(vol, -1e-7,
			"puck should be a closed outward-wound solid (negative signed volume)")
	# Envelope of the replaced CylinderMesh: the collision disc.
	var size: Vector3 = mesh.get_aabb().size
	var diameter: float = GameRules.PUCK_COLLISION_RADIUS * 2.0
	assert_lte(size.x, diameter + 0.0001, "puck should stay inside the cylinder's diameter")
	assert_lte(size.z, diameter + 0.0001, "puck should stay inside the cylinder's diameter")
	assert_almost_eq(size.y, GameRules.PUCK_COLLISION_HALF_HEIGHT * 2.0, 0.001,
			"puck should keep the regulation height")
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for uv: Vector2 in uvs:
		assert_between(uv.x, 0.0, 1.0, "puck U inside [0, 1]")
		assert_between(uv.y, 0.0, 1.0, "puck V inside [0, 1]")


# PuckPrint's image is laid out in this mapping: the face's centre at UV
# (0.5, 0.5) and its corners on the radius-0.5 circle, the right way up.
func test_the_face_is_mapped_flat_for_the_print() -> void:
	var mesh: ArrayMesh = PuckMeshBuilder._build_puck()
	var arrays: Array = mesh.surface_get_arrays(PuckMeshBuilder.SURF_FACE)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var face_r: float = PuckMeshBuilder.PROFILE[0].y
	for i in verts.size():
		assert_almost_eq(verts[i].y, PuckMeshBuilder.PROFILE[0].x, 1e-6, "the face is the top")
		assert_gt(normals[i].y, 0.99, "the face looks up")
		var expected := Vector2(0.5, 0.5) + Vector2(verts[i].x, verts[i].z) / (2.0 * face_r)
		assert_almost_eq(uvs[i].distance_to(expected), 0.0, 1e-5, "UV is planar")


func test_the_print_keeps_a_rubber_margin_and_carries_its_bar() -> void:
	var img: Image = PuckPrint.build_image()
	var n: int = PuckPrint.SIZE
	var bar_y: int = roundi((PuckPrint.BAR_V.x + PuckPrint.BAR_V.y) * 0.5 * n)
	assert_gt(img.get_pixel(n / 2, bar_y).r, 0.9, "the bar is inked across the middle")
	# The face's flat sides sit at its inscribed radius; past it is the chamfer.
	var inscribed: float = 0.5 * cos(PI / float(PuckMeshBuilder.SIDES))
	var stray: int = 0
	for y in n:
		for x in n:
			var uv: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / n
			if uv.distance_to(Vector2(0.5, 0.5)) > inscribed - 1.0 / n and img.get_pixel(x, y).r > 0.0:
				stray += 1
	assert_eq(stray, 0, "ink runs off the face's flat sides")
