extends GutTest

# BodyZonePaint compiles each zone's StandardMaterial3D record into the shader's
# arrays: what the record says is what the zone draws.


func _arr(paint: BodyZonePaint, param: StringName) -> Variant:
	return paint.material.get_shader_parameter(param)


func test_a_record_compiles_to_its_zone() -> void:
	var paint := BodyZonePaint.new(4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.1)
	mat.roughness = 0.42
	mat.metallic = 0.6
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.35
	mat.vertex_color_use_as_albedo = true
	paint.set_zone(2, mat)
	var albedo: Vector4 = (_arr(paint, &"zone_albedo") as PackedVector4Array)[2]
	assert_almost_eq(albedo, Vector4(0.8, 0.2, 0.1, 1.0), Vector4.ONE * 1e-6, "authored albedo")
	assert_almost_eq((_arr(paint, &"zone_pbr") as PackedVector4Array)[2],
			Vector4(0.42, 0.6, 0.4, 0.35), Vector4.ONE * 1e-5)
	var tex: Vector4 = (_arr(paint, &"zone_tex") as PackedVector4Array)[2]
	assert_eq(tex.x, -1.0, "untextured")
	assert_eq(tex.z, 1.0, "vertex colour tints it")
	assert_eq(paint.zone(2), mat, "the record is kept")


func test_rim_off_draws_no_rim() -> void:
	var paint := BodyZonePaint.new(1)
	var mat := StandardMaterial3D.new()
	mat.rim = 0.9
	paint.set_zone(0, mat)
	assert_eq((_arr(paint, &"zone_pbr") as PackedVector4Array)[0].z, 0.0)


func test_zones_wearing_one_texture_share_a_slot() -> void:
	var paint := BodyZonePaint.new(3)
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var a: StandardMaterial3D = UniformPaint.textured(tex)
	var b: StandardMaterial3D = UniformPaint.textured(tex)
	b.uv1_offset = Vector3(0.25, 0.0, 0.0)
	paint.set_zone(0, a)
	paint.set_zone(1, b)
	var zone_tex: PackedVector4Array = _arr(paint, &"zone_tex")
	assert_eq(zone_tex[0].x, zone_tex[1].x, "one slot")
	assert_eq(zone_tex[1].y, 0.25, "each keeps its own U offset")
	var slot: int = paint.texture_slot(tex)
	assert_eq(paint.material.get_shader_parameter(&"tex%d" % slot), tex)


func test_a_texture_no_zone_wears_frees_its_slot() -> void:
	var paint := BodyZonePaint.new(1)
	for i: int in BodyZonePaint.MAX_TEXTURES + 2:
		var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
		paint.set_zone(0, UniformPaint.textured(tex))
		assert_gt(paint.texture_slot(tex), -1, "repaint %d still finds a slot" % i)


func test_ghost_swaps_the_shader_and_keeps_the_paint() -> void:
	var paint := BodyZonePaint.new(1)
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	paint.set_zone(0, UniformPaint.textured(tex))
	var opaque: Shader = paint.material.shader
	paint.set_ghost(true)
	assert_ne(paint.material.shader, opaque)
	assert_eq(paint.material.get_shader_parameter(&"ghost_alpha"), BodyZonePaint.GHOST_ALPHA)
	assert_eq(paint.material.get_shader_parameter(&"tex%d" % paint.texture_slot(tex)), tex)
	paint.set_ghost(false)
	assert_eq(paint.material.shader, opaque)


func test_a_seed_is_a_copy_of_the_parts_default() -> void:
	var boot: ArrayMesh = SkaterMeshBuilder.shared_boot_assembly()
	var paint := BodyZonePaint.new(SkaterMeshBuilder.BODY_ZONE_COUNT)
	SkaterRigidParts.seed_paint(paint)
	var runner := SkaterMeshBuilder.LegSurface.FOOT_L_RUNNER
	var shared: StandardMaterial3D = boot.surface_get_material(
			SkaterMeshBuilder.BOOT_SURF_RUNNER) as StandardMaterial3D
	assert_eq(paint.zone(runner).albedo_color, shared.albedo_color, "the steel ships as steel")
	assert_ne(paint.zone(runner), shared, "a copy — painting it must not repaint the roster")
