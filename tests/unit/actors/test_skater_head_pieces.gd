extends GutTest

# The face gear and the hair are per-player meshes riding the helmet bone of a
# rig whose helmet assembly every skater shares. What a headless run can pin:
# a pick reaches the bone, a bare pick leaves nothing drawn, and the ghost fade
# both reaches the hair and gives back each piece's design alpha afterwards.

var _skater: Skater = null


func before_each() -> void:
	_skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate()
	add_child_autofree(_skater)


func _look(hair: int, facial: int, color: int) -> GearStyleConfig:
	return GearStyleConfig.new(0, 0, GearStyleConfig.LACE_DEFAULT_INDEX, 0,
			GearModelRegistry.FACE_VISOR, hair, facial, color)


func _mat(piece: SkaterArmRig.HeadPiece) -> StandardMaterial3D:
	return _skater.head_piece(piece).material_override as StandardMaterial3D


func test_a_pick_rides_the_helmet_bone() -> void:
	_skater.set_gear_style(_look(HairStyleRegistry.HAIR_MULLET, HairStyleRegistry.FACIAL_BEARD, 2))
	var scalp: MeshInstance3D = _skater.head_piece(SkaterArmRig.HeadPiece.SCALP)
	assert_eq(scalp.mesh, SkaterHairMesh.shared_hair(HairStyleRegistry.HAIR_MULLET))
	assert_eq(_skater.head_piece(SkaterArmRig.HeadPiece.FACIAL_HAIR).mesh,
			SkaterHairMesh.shared_facial_hair(HairStyleRegistry.FACIAL_BEARD))
	var attach: BoneAttachment3D = scalp.get_parent() as BoneAttachment3D
	assert_not_null(attach, "the hair hangs off a bone attachment")
	assert_eq(attach.bone_idx, SkaterMeshBuilder.UpperBone.HELMET, "on the helmet bone")
	assert_eq(_mat(SkaterArmRig.HeadPiece.SCALP).albedo_color, HairStyleRegistry.color_for(2),
			"painted the picked colour")
	assert_eq(_mat(SkaterArmRig.HeadPiece.BROWS).albedo_color, HairStyleRegistry.color_for(2),
			"and so are the brows")


func test_a_bare_pick_draws_nothing() -> void:
	_skater.set_gear_style(_look(HairStyleRegistry.HAIR_MEDIUM, HairStyleRegistry.FACIAL_GOATEE, 0))
	_skater.set_gear_style(_look(HairStyleRegistry.HAIR_BALD, HairStyleRegistry.FACIAL_NONE, 0))
	assert_null(_skater.head_piece(SkaterArmRig.HeadPiece.SCALP).mesh, "bald")
	assert_null(_skater.head_piece(SkaterArmRig.HeadPiece.FACIAL_HAIR).mesh, "no facial hair")
	assert_not_null(_skater.head_piece(SkaterArmRig.HeadPiece.BROWS).mesh,
			"a bald head keeps its brows")


func test_the_ghost_fade_reaches_the_hair_and_gives_it_back() -> void:
	_skater.set_gear_style(_look(HairStyleRegistry.HAIR_SHORT, HairStyleRegistry.FACIAL_STUBBLE, 1))
	_skater.set_ghost(true)
	assert_almost_eq(_mat(SkaterArmRig.HeadPiece.SCALP).albedo_color.a, 0.3, 0.001,
			"the scalp fades with the body")
	assert_lt(_mat(SkaterArmRig.HeadPiece.FACIAL_HAIR).albedo_color.a,
			SkaterHairMesh.STUBBLE_ALPHA, "stubble fades below its own translucency")
	_skater.set_ghost(false)
	assert_eq(_mat(SkaterArmRig.HeadPiece.SCALP).transparency,
			BaseMaterial3D.TRANSPARENCY_DISABLED, "the scalp comes back opaque")
	assert_almost_eq(_mat(SkaterArmRig.HeadPiece.FACIAL_HAIR).albedo_color.a,
			SkaterHairMesh.STUBBLE_ALPHA, 0.001, "stubble comes back to its design alpha")
	assert_lt(_mat(SkaterArmRig.HeadPiece.FACE_GEAR).albedo_color.a, 1.0,
			"and the visor to its own")
