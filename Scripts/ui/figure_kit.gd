class_name FigureKit
extends RefCounted

# A kit-dressed display figure built from the rink's own body: the body
# skeleton (SkaterBodySkeleton), the skin on it (SkaterConnectedRig) and the
# rigid parts (SkaterRigidParts), painted by the rink's kit paint
# (SkaterKitPaint), the head pieces on the helmet bone, the jersey's tail as the
# rink's cloth (SkaterHemFlaps), and a stick assembly (shaft, blade, tape,
# knob). It builds and it dresses; the figure holding it poses the skeleton —
# the player screen's case stands it holding its stick, the lobby seats it on
# the bench.

const KNOB_HEIGHT_M: float = 0.05
const _SHAFT_CROSS := Vector2(0.04, 0.05)
const _CLOTH_ROUGH: float = 0.9

var skeleton: Skeleton3D = null
# The jersey's tail: the figure settles it once posed, and may step it on.
var hem := SkaterHemFlaps.new()

# The stick in its own frame: heel at the origin, the shaft climbing along the
# lie axis, so placing it is one transform on `stick_root`.
var stick_root: Node3D = null
var shaft: MeshInstance3D = null
var shaft_mat: ShaderMaterial = null
var blade: MeshInstance3D = null
var tape_mesh: MeshInstance3D = null
var knob: MeshInstance3D = null

var _rig: Node3D = null
var _skin := SkaterConnectedRig.new()
var _paint := BodyZonePaint.new(SkaterMeshBuilder.BODY_ZONE_COUNT)
var _kit: SkaterKitPaint = null
var _head_pieces: Array[MeshInstance3D] = []
var _tuck: int = GearModelRegistry.TUCK_NONE


# The skeleton and its meshes under `rig`; the decal viewports under
# `viewport_host`.
func build(rig: Node3D, viewport_host: Node) -> void:
	_rig = rig
	skeleton = SkaterBodySkeleton.new_body_skeleton()
	rig.add_child(skeleton)
	SkaterRigidParts.seed_paint(_paint)
	_skinned(SkaterRigidParts.upper_body_mesh(), SkaterMeshBuilder.shared_upper_skin())
	_skinned(SkaterRigidParts.leg_body_mesh(), SkaterMeshBuilder.shared_leg_skin())
	_skin.build(skeleton, _paint.material, _tuck)
	_kit = SkaterKitPaint.new(_paint, viewport_host)
	var head := BoneAttachment3D.new()
	skeleton.add_child(head)
	# bone_idx after add_child — the setter binds against the parent skeleton.
	head.bone_idx = SkaterMeshBuilder.UpperBone.HELMET
	for i: int in SkaterArmRig.HeadPiece.size():
		var piece := MeshInstance3D.new()
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(piece)
		_head_pieces.append(piece)
	hem.setup(null, skeleton, _tuck)
	_build_stick()


# The skin's deform bones off the bones the figure just posed; `top_side` is
# the side the top hand's arm hangs from (0 left, 1 right).
func pose_skin(top_side: int) -> void:
	_skin.pose(top_side)


# Paints every part, and puts on the jersey's tuck. After the pose: the shaft's
# grip wrap is laid along the length the pose gave it.
func dress(colors: Dictionary, gear: GearStyleConfig, tape: StickTapeConfig,
		skin_tone: int, player_name: String, jersey_number: int) -> void:
	_kit.apply_uniform(colors)
	_kit.apply_gear(gear)
	_kit.set_jersey_info(player_name, jersey_number)
	_kit.set_skin_tone(skin_tone)
	if gear.jersey_tuck != _tuck:
		_tuck = gear.jersey_tuck
		_skin.set_tuck(_tuck)
		hem.set_tuck(_tuck)
	_dress_head(gear)
	_paint_stick(gear, tape, colors)


func _skinned(mesh: ArrayMesh, skin: Skin) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.skin = skin
	mi.skeleton = NodePath("..")
	mi.set_surface_override_material(0, _paint.material)
	skeleton.add_child(mi)


func _build_stick() -> void:
	stick_root = Node3D.new()
	_rig.add_child(stick_root)

	shaft = MeshInstance3D.new()
	var shaft_box := BoxMesh.new()
	shaft_box.size = Vector3(_SHAFT_CROSS.x, _SHAFT_CROSS.y, 1.0)
	shaft.mesh = shaft_box
	shaft_mat = StickStyle.make_shaft_material()
	shaft.material_override = shaft_mat
	stick_root.add_child(shaft)

	blade = MeshInstance3D.new()
	blade.material_override = StickStyle.make_blade_material()
	stick_root.add_child(blade)

	tape_mesh = MeshInstance3D.new()
	blade.add_child(tape_mesh)

	knob = MeshInstance3D.new()
	var knob_cyl := CylinderMesh.new()
	knob_cyl.top_radius = 0.035
	knob_cyl.bottom_radius = 0.03
	knob_cyl.height = KNOB_HEIGHT_M
	knob_cyl.radial_segments = 12
	knob.mesh = knob_cyl
	stick_root.add_child(knob)


# Face gear is a fixed look with no kit zones — the rink's own mesh and
# material, and a null mesh for bare; the hair and brows the same.
func _dress_head(gear: GearStyleConfig) -> void:
	var face: MeshInstance3D = _head_pieces[SkaterArmRig.HeadPiece.FACE_GEAR]
	face.mesh = SkaterMeshBuilder.shared_face_gear(gear.helmet_face)
	face.material_override = SkaterMeshBuilder.make_face_gear_material(gear.helmet_face)
	var scalp: MeshInstance3D = _head_pieces[SkaterArmRig.HeadPiece.SCALP]
	scalp.mesh = SkaterHairMesh.shared_hair(gear.hair_style)
	scalp.material_override = SkaterHairMesh.make_material(gear.hair_color,
			SkaterHairMesh.is_scalp_translucent(gear.hair_style))
	var facial: MeshInstance3D = _head_pieces[SkaterArmRig.HeadPiece.FACIAL_HAIR]
	facial.mesh = SkaterHairMesh.shared_facial_hair(gear.facial_hair)
	facial.material_override = SkaterHairMesh.make_material(gear.hair_color,
			SkaterHairMesh.is_translucent(gear.facial_hair))
	var brows: MeshInstance3D = _head_pieces[SkaterArmRig.HeadPiece.BROWS]
	brows.mesh = SkaterHairMesh.shared_brows()
	brows.material_override = SkaterHairMesh.make_material(gear.hair_color, false)


func _paint_stick(gear: GearStyleConfig, tape: StickTapeConfig,
		colors: Dictionary) -> void:
	var accent: Color = colors.primary
	# Fresh materials from the same factories the rink uses, so the figure's
	# stick IS the in-game stick. The shaft material comes back with default
	# uniforms, so the pose's shaft length has to be re-sent after it.
	shaft_mat = StickStyle.make_shaft_material(gear.stick_model)
	shaft.material_override = shaft_mat
	blade.material_override = StickStyle.make_blade_material(gear.stick_model)

	var knob_color: Color = TapeColorRegistry.resolve(tape.knob_color, accent)
	shaft_mat.set_shader_parameter(&"grip_mode", tape.knob_style)
	shaft_mat.set_shader_parameter(&"grip_color", knob_color)
	shaft_mat.set_shader_parameter(&"shaft_len_m",
			shaft.transform.basis.get_scale().z)
	tape_mesh.material_override = _flat(
			TapeColorRegistry.resolve(tape.blade_color, accent), _CLOTH_ROUGH)
	knob.material_override = _flat(knob_color, _CLOTH_ROUGH)


# Plain material for the stick's non-body pieces (tape, knob) — no body rim:
# they are equipment in the hand, not skin or cloth on the silhouette.
static func _flat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat
