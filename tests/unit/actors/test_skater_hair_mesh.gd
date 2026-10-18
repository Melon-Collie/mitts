extends GutTest

# Hair rides between two shells it must not cross: the head under it and the
# helmet and face gear over it. A style tuned to read better pokes through the
# visor or the shell without anything else noticing, and a scalp whose top edge
# clears the rim shows as a hairline drawn on the helmet's underside.

const _CENTRE := Vector3(0.0, 0.0, -SkaterMeshBuilder.HEAD_FORWARD_M)


func _verts(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _scalps() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for style: int in HairStyleRegistry.hair_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_hair(style)
		if mesh != null:
			out.append(mesh)
	return out


func _facials() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for style: int in HairStyleRegistry.facial_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_facial_hair(style)
		if mesh != null:
			out.append(mesh)
	return out


func test_every_style_but_the_bare_ones_has_geometry() -> void:
	for style: int in HairStyleRegistry.hair_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_hair(style)
		if style == HairStyleRegistry.HAIR_BALD:
			assert_null(mesh, "bald grows nothing")
		else:
			assert_not_null(mesh, "hair style %d has a shell" % style)
			assert_gt(_verts(mesh).size(), 0)
	for style: int in HairStyleRegistry.facial_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_facial_hair(style)
		if style == HairStyleRegistry.FACIAL_NONE:
			assert_null(mesh, "clean-shaven grows nothing")
		else:
			assert_not_null(mesh, "facial style %d has a shell" % style)
	assert_null(SkaterHairMesh.shared_hair(99), "a forged index renders bald")
	assert_null(SkaterHairMesh.shared_facial_hair(-1), "a forged index renders clean")


# Above the rim the scalp has to be inside the head, which is inside the helmet;
# anywhere it stood proud there would be a hairline on the shell's inside.
func test_the_scalp_hides_its_top_edge_inside_the_head() -> void:
	for mesh: ArrayMesh in _scalps():
		var worst: float = -1.0
		for v: Vector3 in _verts(mesh):
			var rim: float = SkaterMeshBuilder.helmet_rim_y(atan2(v.x, v.z))
			if v.y > rim + 0.012:
				worst = maxf(worst, (v - _CENTRE).length())
		assert_gt(worst, 0.0, "the scalp carries on above the rim")
		assert_lt(worst, SkaterMeshBuilder.HEAD_RADIUS,
				"hidden scalp reaches %.4f m off the head's centre" % worst)


# The face gear rides a sphere a centimetre or so off the head (the same bound
# test_skater_face_mesh.gd holds the face to). Facial hair lives entirely under
# it; scalp hair only meets it at the sideburns, inside the fishbowl's footprint
# — the widest and deepest of the three pieces.
func test_hair_stays_inside_the_face_gear() -> void:
	var gear_r: float = minf(SkaterMeshBuilder._CAGE_RADIUS,
			SkaterMeshBuilder._FACE_SHIELD_RADIUS) - 0.001
	for mesh: ArrayMesh in _facials():
		var worst: float = 0.0
		for v: Vector3 in _verts(mesh):
			worst = maxf(worst, v.length())
		assert_lt(worst, gear_r,
				"facial hair reaches %.4f m from the helmet centre" % worst)
	var gear_floor: float = SkaterMeshBuilder._FACE_SHIELD_RADIUS \
			* cos(PI * SkaterMeshBuilder._FISHBOWL_V1)
	for mesh: ArrayMesh in _scalps():
		var worst: float = 0.0
		for v: Vector3 in _verts(mesh):
			var off_front: float = absf(wrapf(atan2(v.x, v.z) - PI, -PI, PI))
			if off_front < SkaterMeshBuilder._FISHBOWL_HALF_ARC and v.y > gear_floor:
				worst = maxf(worst, v.length())
		assert_lt(worst, gear_r,
				"a sideburn reaches %.4f m from the helmet centre" % worst)


func test_facial_hair_leaves_the_mouth_bare() -> void:
	var mouth: Vector3 = SkaterFaceMesh._MOUTH   # (y, half width, half height)
	for style: int in HairStyleRegistry.facial_count():
		var mesh: ArrayMesh = SkaterHairMesh.shared_facial_hair(style)
		if mesh == null:
			continue
		var covering: int = 0
		for v: Vector3 in _verts(mesh):
			if absf(v.x) < mouth.y and absf(v.y - mouth.x) < mouth.z and v.z < 0.0:
				covering += 1
		assert_eq(covering, 0, "facial style %d keeps off the mouth" % style)


# Where the hair shows it must stand off the skin, or the head shows through it.
# Sampled where each style is fullest: the nape on the scalp, the chin on a beard.
func test_visible_hair_stands_off_the_head() -> void:
	var ball: ArrayMesh = SkaterMeshBuilder.shared_head_ball()
	var head_far: float = 0.0
	for v: Vector3 in _verts(ball):
		# The ball's own mesh is in head-local space, its centre at the origin.
		if v.z > 0.05 and v.y < -0.105:
			head_far = maxf(head_far, v.z)
	for style: int in [HairStyleRegistry.HAIR_SHORT, HairStyleRegistry.HAIR_MEDIUM,
			HairStyleRegistry.HAIR_FLOW]:
		var reach: float = 0.0
		for v: Vector3 in _verts(SkaterHairMesh.shared_hair(style)):
			if absf(v.x) < 0.01 and v.y < -0.105 and v.y > -0.118:
				reach = maxf(reach, v.z - _CENTRE.z)
		assert_gt(reach, head_far, "style %d covers the nape" % style)


func test_stubble_is_translucent_and_hair_is_not() -> void:
	var hair: StandardMaterial3D = SkaterHairMesh.make_material(1, false)
	assert_eq(hair.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "hair is opaque")
	assert_eq(hair.cull_mode, BaseMaterial3D.CULL_DISABLED, "hair sheets render two-sided")
	var stubble: StandardMaterial3D = SkaterHairMesh.make_material(1, true)
	assert_eq(stubble.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(stubble.albedo_color.a, SkaterHairMesh.STUBBLE_ALPHA, 0.001)
	assert_true(SkaterHairMesh.is_translucent(HairStyleRegistry.FACIAL_STUBBLE))
	assert_false(SkaterHairMesh.is_translucent(HairStyleRegistry.FACIAL_BEARD))
