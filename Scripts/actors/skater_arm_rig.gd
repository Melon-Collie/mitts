class_name SkaterArmRig
extends RefCounted

# The upper half of the body skeleton: torso, the jersey's tail (TAIL, and its
# flaps below the belt, SkaterHemFlaps), pelvis, helmet, and both arms posed by
# IK from the hand markers.
#
# The shell parts hang from SPINE and the pelvis from WAIST, and are posed in
# their parent's frame exactly as they used to be in UpperBody's (see
# SkaterMeshBuilder.UpperBone). The arms are root bones posed in skeleton space —
# MeshRoot's, the space the UpperBody frame the hands hang under is placed in —
# so each one runs from the shoulder the spine actually put somewhere to the
# hand gameplay put somewhere, and the body is what gives.
#
# Pose = basis · scale, at position, each part stored separately: `_basis` is the
# authored rest rotation, `_scale` and `_pos` are the sizing seam's, and
# `_thickness` is the arm parts' own radius contract. Every write here is
# cosmetic — the hand and shoulder MARKERS are gameplay geometry Skater owns, and
# this file only reads them.

# Each arm's parts (top, bottom): upper arm, forearm, cuff, elbow, glove.
const _ARM_PARTS: Array[Array] = [
	[SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM, SkaterMeshBuilder.UpperBone.TOP_FOREARM,
			SkaterMeshBuilder.UpperBone.TOP_CUFF, SkaterMeshBuilder.UpperBone.TOP_ELBOW,
			SkaterMeshBuilder.UpperBone.TOP_HAND],
	[SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM, SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_CUFF, SkaterMeshBuilder.UpperBone.BOTTOM_ELBOW,
			SkaterMeshBuilder.UpperBone.BOTTOM_HAND],
]

var _skater: Skater
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
# Per-part pose scale, except a bone's Z, which is its live length.
var _thickness: PackedVector3Array = PackedVector3Array()
var _basis: Array[Basis] = []
var _scale: PackedVector3Array = PackedVector3Array()
var _pos: PackedVector3Array = PackedVector3Array()
var _base_scale: PackedVector3Array = PackedVector3Array()
var _base_pos: PackedVector3Array = PackedVector3Array()
var _helmet_base_euler: Vector3 = Vector3.ZERO
var _head_attach: BoneAttachment3D = null
var _head_pieces: Array[MeshInstance3D] = []

# The gait's trunk texture (stride sway, weight shift, stance and check leans,
# the stagger wobble), applied to the shell bones on top of the spine. The
# helmet rides only part of it — players hold the head steady while the
# shoulders work under it — roll hard-damped because it is the oscillating
# channel, pitch nearly full because a low follow there detaches the helmet
# from the torso top at deep folds. 1.0 / 1.0 is rigid coupling.
var helmet_pitch_follow: float = 0.85
var helmet_roll_follow: float = 0.4

# The arm's C++ port, one per arm (top, bottom), which writes that arm's bones
# itself. Absent without the extension; native_enabled lets the parity test take
# the GDScript path, which stays the reference.
var native_enabled: bool = true
var _native_arms: Array[RefCounted] = []
var _native_dirty: bool = true
var _trunk_texture := Basis.IDENTITY
var _trunk_texture_head := Basis.IDENTITY
var _trunk_texture_pitch: float = 0.0
var _trunk_texture_roll: float = 0.0
# The texture moved the shoulders the arms root on since the mesh pass last
# asked (take_retextured).
var _retextured: bool = false
# The jersey tail's drape below the belt, and the tuck it was draped for.
var _hem := SkaterHemFlaps.new()
var _hem_tuck: int = -1


func setup(skater: Skater) -> void:
	_skater = skater


# Reads the scene-authored placement of the two shell parts out of the
# UpperBody subtree, seeds the body skeleton's upper bones from it, then frees
# those nodes — keeping Scenes/Skater.tscn the place the proportions are
# authored. `body_material` is the skater's BodyZonePaint, which the upper body's
# one surface wears.
func build(skeleton: Skeleton3D, body_material: Material) -> void:
	var count: int = SkaterMeshBuilder.UPPER_BONE_COUNT
	var upper_body: Node3D = _skater.upper_body
	_basis.resize(count)
	_scale.resize(count)
	_pos.resize(count)
	_base_scale.resize(count)
	_base_pos.resize(count)
	_skeleton = skeleton

	if ClassDB.class_exists(&"NativeArmRig"):
		_native_arms = [ClassDB.instantiate(&"NativeArmRig") as RefCounted,
				ClassDB.instantiate(&"NativeArmRig") as RefCounted]
		for arm: int in 2:
			var bones := PackedInt32Array(_ARM_PARTS[arm])
			bones.append(SkaterBodySkeleton.SPINE_BONE)
			_native_arms[arm].bind(skeleton, bones)
	_mesh = MeshInstance3D.new()
	_mesh.name = "UpperMesh"
	_mesh.mesh = SkaterRigidParts.upper_body_mesh()
	_mesh.set_surface_override_material(0, body_material)
	_mesh.skin = SkaterMeshBuilder.shared_upper_skin()
	_mesh.skeleton = NodePath("..")
	_skeleton.add_child(_mesh)

	# Torso and helmet: their placement is authored in the scene, so it is read
	# out and seeded onto their bones, same as the legs.
	for bone: int in [SkaterMeshBuilder.UpperBone.TORSO,
			SkaterMeshBuilder.UpperBone.HELMET]:
		var node: Node3D = upper_body.get_node(
				SkaterMeshBuilder.UPPER_BONE_NODE[bone]) as Node3D
		var xform: Transform3D = node.transform
		_basis[bone] = xform.basis.orthonormalized()
		_scale[bone] = xform.basis.get_scale()
		_pos[bone] = xform.origin
		_base_scale[bone] = _scale[bone]
		_base_pos[bone] = _pos[bone]
		repose_bone(bone)
		node.free()
	_helmet_base_euler = _basis[SkaterMeshBuilder.UpperBone.HELMET].get_euler()

	# The pelvis has no scene node to read: the skin's pants are authored in the
	# waist's own space (SkaterConnectedPants), so it rests at the identity the
	# sizing seam then scales about.
	var pelvis: int = SkaterMeshBuilder.UpperBone.PELVIS
	_basis[pelvis] = Basis.IDENTITY
	_scale[pelvis] = Vector3.ONE
	_pos[pelvis] = Vector3.ZERO
	_base_scale[pelvis] = Vector3.ONE
	_base_pos[pelvis] = Vector3.ZERO
	repose_bone(pelvis)

	_thickness.resize(count)
	var bone_radius: float = _skater.arm_mesh_thickness * 0.5
	set_bone_radius(SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM, bone_radius)
	set_bone_radius(SkaterMeshBuilder.UpperBone.TOP_FOREARM, bone_radius)
	set_bone_radius(SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM, bone_radius)
	set_bone_radius(SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM, bone_radius)
	set_ball_radius(SkaterMeshBuilder.UpperBone.TOP_ELBOW, _skater.elbow_sphere_radius)
	set_ball_radius(SkaterMeshBuilder.UpperBone.BOTTOM_ELBOW, _skater.elbow_sphere_radius)
	set_ball_radius(SkaterMeshBuilder.UpperBone.TOP_HAND, _skater.hand_sphere_radius)
	set_ball_radius(SkaterMeshBuilder.UpperBone.BOTTOM_HAND, _skater.hand_sphere_radius)
	var cuff_radius: float = _skater.arm_mesh_thickness * 0.6
	set_cuff_radius(SkaterMeshBuilder.UpperBone.TOP_CUFF, cuff_radius)
	set_cuff_radius(SkaterMeshBuilder.UpperBone.BOTTOM_CUFF, cuff_radius)

	# The gear style may have landed before the rig (spawn order is
	# registry-driven); now that the mesh and the helmet bone exist, dress them.
	apply_gear_meshes()


# ── Arm pose ─────────────────────────────────────────────────────────────────

func update_top_arm() -> void:
	var hand: Vector3 = _skater.drawn_top_hand()
	_update_arm(0, _skater.shoulder.position, hand, _skater.stick_grip_axis(hand),
			1.0 if _skater.is_left_handed else -1.0,
			SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM,
			SkaterMeshBuilder.UpperBone.TOP_FOREARM,
			SkaterMeshBuilder.UpperBone.TOP_CUFF,
			SkaterMeshBuilder.UpperBone.TOP_ELBOW,
			SkaterMeshBuilder.UpperBone.TOP_HAND)


# The bottom glove rides the drawn shaft's bow: the marker stays on the straight
# gameplay stick, the hand goes where the bent shaft actually is.
func update_bottom_arm() -> void:
	var hand: Vector3 = _skater.bottom_hand.position
	var grip: Vector3 = _skater.stick_grip_axis(hand)
	hand += _skater.stick_bow_offset(hand)
	_update_arm(1, _skater.bottom_shoulder.position, hand, grip,
			-1.0 if _skater.is_left_handed else 1.0,
			SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_CUFF,
			SkaterMeshBuilder.UpperBone.BOTTOM_ELBOW,
			SkaterMeshBuilder.UpperBone.BOTTOM_HAND)


# `grip_local` is the shaft's direction at this hand (upper-body space), ZERO for
# a hand off the stick.
func _update_arm(arm: int, marker_local: Vector3, hand_local: Vector3, grip_local: Vector3,
		pole_sign: float, upper: int, forearm: int, cuff: int, elbow_bone: int,
		glove: int) -> void:
	if native_enabled and not _native_arms.is_empty() \
			and _native_update_arm(arm, marker_local, hand_local, grip_local, pole_sign):
		return
	var spine: Transform3D = _skeleton.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	var frame: Transform3D = _skater.drawn_upper_body()
	var hand_s: Vector3 = frame * hand_local
	var shoulder_s: Vector3 = arm_root(marker_local, hand_local)
	var pole_s: Vector3 = spine.basis * _arm_pole(marker_local, pole_sign)
	var elbow_s: Vector3 = TwoBoneIK.solve_elbow(shoulder_s, hand_s,
			_skater.upper_arm_length, _skater.forearm_length, pole_s)
	_pose_bone(upper, shoulder_s, elbow_s)
	_pose_bone(forearm, elbow_s, hand_s)
	_pose_cuff(cuff, elbow_s, hand_s)
	_pose_elbow(elbow_bone, shoulder_s, elbow_s, hand_s, pole_s)
	_pose_glove(glove, elbow_s, hand_s, frame.basis * grip_local)


# _update_arm in C++ (NativeArmRig), bone writes included. False on a
# degenerate span, which the GDScript path's held poses answer instead.
func _native_update_arm(arm: int, marker_local: Vector3, hand_local: Vector3,
		grip_local: Vector3, pole_sign: float) -> bool:
	if _native_dirty:
		_configure_native()
	var pole: Vector3 = _skater.arm_pole_local
	pole.x *= pole_sign
	var arm_len: float = _skater.upper_arm_length + _skater.forearm_length
	if not _native_arms[arm].pose(marker_local, hand_local, grip_local, _skater.drawn_upper_body(),
			_trunk_texture, pole,
			Vector4(_skater.upper_arm_length, _skater.forearm_length,
			arm_len * _skater.arm_working_extension, _skater.shoulder_reach_m),
			Vector3(_skater.get_check_lead(), _skater.shoulder_offset,
			SkaterMeshBuilder.CUFF_HEIGHT_M * 0.5 + _skater.cuff_wrist_offset)):
		return false
	return true


func _configure_native() -> void:
	_native_dirty = false
	for arm: int in 2:
		var parts: Array = _ARM_PARTS[arm]
		_native_arms[arm].configure(_thickness[parts[0]], _thickness[parts[1]],
				_thickness[parts[2]], _thickness[parts[3]], _thickness[parts[4]],
				deg_to_rad(_skater.wrist_break_max_deg))


# The elbow's pole on this arm's side, tucked by a check load.
func _arm_pole(marker_local: Vector3, pole_sign: float) -> Vector3:
	var pole_local: Vector3 = _skater.arm_pole_local
	pole_local.x *= pole_sign
	return CheckStanceRules.tucked_pole(pole_local, CheckStanceRules.side_load(
			_skater.get_check_lead(), signf(marker_local.x)))


# A shoulder MARKER's place on the visible trunk, in UpperBody's frame — where a
# reactive hand must stay within reach of. Before the rig is built, the marker.
func visible_shoulder(marker_local: Vector3) -> Vector3:
	if _skeleton == null:
		return marker_local
	var spine: Transform3D = _skeleton.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	return _skater.drawn_upper_body().affine_inverse() \
			* (spine * _textured_shoulder(marker_local))


# Where an arm roots, in skeleton space: the shoulder on the visible trunk,
# drawn toward a hand past the arm's working length by the girdle's give
# (TwoBoneIK.reach_root).
func arm_root(marker_local: Vector3, hand_local: Vector3) -> Vector3:
	var spine: Transform3D = _skeleton.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	return TwoBoneIK.reach_root(spine * _textured_shoulder(marker_local),
			_skater.drawn_upper_body() * hand_local,
			(_skater.upper_arm_length + _skater.forearm_length) * _skater.arm_working_extension,
			_skater.shoulder_reach_m)


# Where a shoulder MARKER actually sits on the visible trunk, in the spine's
# frame: once the trunk texture has rolled the shell and the check load-up has
# driven the leading shoulder forward.
#
# The arm has to be rooted here, not at the marker: the marker is gameplay
# geometry and never moves with the visible body, so an arm grown from it stays
# put while the shoulder it emerges from moves away. The HAND is untouched,
# so the blade keeps the position the IK solved and only the elbow re-solves;
# nothing gameplay reads changes.
func _textured_shoulder(marker_local: Vector3) -> Vector3:
	return _trunk_texture * (marker_local + _check_load_offset(signf(marker_local.x)))


# Load-up displacement of the shoulder on `side_sign`, zero on the trailing side
# and while nobody is committing.
func _check_load_offset(side_sign: float) -> Vector3:
	var lead: float = _skater.get_check_lead()
	if lead == 0.0:
		return Vector3.ZERO
	return CheckStanceRules.load_offset(
			CheckStanceRules.side_load(lead, side_sign),
			side_sign, _skater.shoulder_offset)


# One pose write per part, each a whole Transform3D built in skeleton space
# (SkaterArmPoses) — the arm bones are roots, so that is their pose space.
# Deliberately NOT position/scale/look_at on nodes: that trio costs six transform
# operations, two of which resolve the global chain, and at ten parts per skater
# this is the densest such site in the rig.
func _pose_bone(part: int, a: Vector3, b: Vector3) -> void:
	var span: Vector3 = b - a
	var length: float = span.length()
	var center: Vector3 = (a + b) * 0.5
	var bone_scale: Vector3 = _thickness[part]
	if length < 0.0001:
		# Degenerate span: move it, hold the orientation it already had. A pose
		# write replaces the whole transform, so "leave the basis alone" has to be
		# spelled out.
		var held: Transform3D = _skeleton.get_bone_pose(part)
		held.origin = center
		_skeleton.set_bone_pose(part, held)
		return
	_skeleton.set_bone_pose(part, SkaterArmPoses.segment_pose(a, b, bone_scale))


func _pose_elbow(part: int, shoulder: Vector3, elbow: Vector3, hand: Vector3,
		pole: Vector3) -> void:
	_skeleton.set_bone_pose(part, SkaterArmPoses.elbow_pose(shoulder, elbow, hand, pole,
			_thickness[part]))


# Positions the gloved fist at the hand; `grip` is the shaft through the fist
# (skeleton space), ZERO off the stick.
func _pose_glove(part: int, elbow: Vector3, hand: Vector3, grip: Vector3) -> void:
	var scale_v: Vector3 = _thickness[part]
	var dir: Vector3 = hand - elbow
	if dir.length_squared() < 0.0001:
		var held: Transform3D = _skeleton.get_bone_pose(part)
		held.origin = hand
		_skeleton.set_bone_pose(part, held)
		return
	var basis: Basis = SkaterArmPoses.glove_basis(dir.normalized(), grip,
			deg_to_rad(_skater.wrist_break_max_deg))
	_skeleton.set_bone_pose(part, Transform3D(basis.scaled_local(scale_v), hand))


func _pose_cuff(part: int, elbow: Vector3, hand: Vector3) -> void:
	var scale_v: Vector3 = _thickness[part]
	var bone_dir: Vector3 = hand - elbow
	var bone_len: float = bone_dir.length()
	if bone_len < 0.0001:
		var held: Transform3D = _skeleton.get_bone_pose(part)
		held.origin = hand
		_skeleton.set_bone_pose(part, held)
		return
	_skeleton.set_bone_pose(part, SkaterArmPoses.cuff_pose(elbow, hand, scale_v,
			_skater.cuff_wrist_offset))


# ── Trunk texture and head ───────────────────────────────────────────────────

# Whether the trunk texture moved the shoulders since the last call.
func take_retextured() -> bool:
	var moved: bool = _retextured
	_retextured = false
	return moved


func set_trunk_texture(pitch_add: float, roll_add: float) -> void:
	if is_equal_approx(pitch_add, _trunk_texture_pitch) \
			and is_equal_approx(roll_add, _trunk_texture_roll):
		return
	_trunk_texture_pitch = pitch_add
	_trunk_texture_roll = roll_add
	_retextured = true
	_trunk_texture = Basis.from_euler(Vector3(pitch_add, 0.0, roll_add))
	_trunk_texture_head = Basis.from_euler(Vector3(
			pitch_add * helmet_pitch_follow, 0.0, roll_add * helmet_roll_follow))
	repose_bone(SkaterMeshBuilder.UpperBone.TORSO)
	repose_bone(SkaterMeshBuilder.UpperBone.HELMET)


# Drapes the jersey's tail. It steps every frame, so a skater the camera picks
# up mid-swing is mid-swing; its bones are written only when drawn.
func update_hem(delta: float, on_camera: bool) -> void:
	_hem.update(delta, on_camera)


# The head's lerp toward its aim never lands exactly, so it would re-pose the
# helmet (and dirty the whole skeleton) every frame of an idle skater. Writes
# land only once the angle has moved this far (rad) from the last one written,
# so the drawn head is never further than this from the asked-for one.
const HEAD_ANGLE_EPS_RAD: float = 0.0001

var _head_angle_written: float = INF
var _head_nod_written: float = INF
# A nod tips the head and neck about the collar, this far under the helmet
# bone's origin (m) — where SkaterMeshBuilder.NECK_PROFILE sinks into the torso
# — so the neck stays in it rather than the head turning about its own middle;
# the shift that puts it there.
const _NOD_PIVOT_DROP_M: float = 0.17
var _head_nod_shift: Vector3 = Vector3.ZERO


func set_head_angle(angle: float, nod: float = 0.0) -> void:
	if absf(angle - _head_angle_written) < HEAD_ANGLE_EPS_RAD \
			and absf(nod - _head_nod_written) < HEAD_ANGLE_EPS_RAD:
		return
	_head_angle_written = angle
	_head_nod_written = nod
	_head_nod_shift = Basis(Vector3.UP, angle) * Vector3(0.0,
			_NOD_PIVOT_DROP_M * (cos(nod) - 1.0), -_NOD_PIVOT_DROP_M * sin(nod))
	_basis[SkaterMeshBuilder.UpperBone.HELMET] = Basis.from_euler(
			Vector3(_helmet_base_euler.x - nod, angle, _helmet_base_euler.z))
	repose_bone(SkaterMeshBuilder.UpperBone.HELMET)


func repose_bone(bone: int) -> void:
	var origin: Vector3 = _pos[bone]
	if bone == SkaterMeshBuilder.UpperBone.HELMET:
		origin += _head_nod_shift
	var pose := Transform3D(_basis[bone].scaled_local(_scale[bone]), origin)
	# The jersey's tail is the torso as the hips hold it: the same placement, hung
	# from the waist, so it takes neither the spine's fold nor the texture.
	if bone == SkaterMeshBuilder.UpperBone.TORSO:
		_skeleton.set_bone_pose(SkaterBodySkeleton.TAIL_BONE, pose)
	# The trunk texture rotates the upper-body SHELL about the trunk pivot (the
	# shell is posed in the spine's frame, so a zero-origin premultiply is that
	# pivot). Arm bones are excluded — they follow the hands; the helmet takes
	# the stabilized head share instead of the full texture.
	if bone == SkaterMeshBuilder.UpperBone.TORSO:
		pose = Transform3D(_trunk_texture, Vector3.ZERO) * pose
	elif bone == SkaterMeshBuilder.UpperBone.HELMET:
		pose = Transform3D(_trunk_texture_head, Vector3.ZERO) * pose
	_skeleton.set_bone_pose(bone, pose)


# ── Gear meshes ──────────────────────────────────────────────────────────────
# The gear style's shapes: the upper mesh for the jersey's tuck, and the head
# pieces — the face gear, the hair and the brows, per-player meshes riding the
# HELMET bone, so they take its head turn and its head-bulk scale. Kept off the
# skinned mesh because the helmet assembly is shared by every skater; a null
# mesh is a bare head.

enum HeadPiece { FACE_GEAR, SCALP, FACIAL_HAIR, BROWS }


func apply_gear_meshes() -> void:
	if _skeleton == null:
		return
	if _head_attach == null:
		_head_attach = BoneAttachment3D.new()
		_head_attach.name = "HeadPieces"
		_skeleton.add_child(_head_attach)
		# bone_idx after add_child — the setter binds against the parent skeleton.
		_head_attach.bone_idx = SkaterMeshBuilder.UpperBone.HELMET
		for i: int in HeadPiece.size():
			var piece := MeshInstance3D.new()
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_head_attach.add_child(piece)
			_head_pieces.append(piece)
	var gear: GearStyleConfig = _skater.gear_style
	if _hem_tuck < 0:
		_hem.setup(_skater, _skeleton, gear.jersey_tuck)
	elif gear.jersey_tuck != _hem_tuck:
		_hem.set_tuck(gear.jersey_tuck)
	_hem_tuck = gear.jersey_tuck
	_head_pieces[HeadPiece.FACE_GEAR].mesh = SkaterMeshBuilder.shared_face_gear(gear.helmet_face)
	_head_pieces[HeadPiece.SCALP].mesh = SkaterHairMesh.shared_hair(gear.hair_style)
	_head_pieces[HeadPiece.FACIAL_HAIR].mesh = SkaterHairMesh.shared_facial_hair(gear.facial_hair)
	_head_pieces[HeadPiece.BROWS].mesh = SkaterHairMesh.shared_brows()


# One head piece's render node, for the uniform coordinator's paint and ghost
# fade. Null before the rig is built; its mesh is null while the piece is bare.
func head_piece(piece: HeadPiece) -> MeshInstance3D:
	return _head_pieces[piece] if piece < _head_pieces.size() else null


# ── Sizing seams ─────────────────────────────────────────────────────────────
# The scene-authored shell parts. Their arm siblings are placed by IK and
# sized through the radius seams below instead. Scale and position are applied
# in separate passes by SkaterAppearanceCoordinator (a part can take one, the
# other, or both), so each setter writes its own component and recomposes.
func set_bone_scale(bone: int, part_scale: Vector3) -> void:
	_native_dirty = true
	_scale[bone] = part_scale
	repose_bone(bone)


func set_bone_position(bone: int, pos: Vector3) -> void:
	_native_dirty = true
	_pos[bone] = pos
	repose_bone(bone)


func bone_base_scale(bone: int) -> Vector3:
	return _base_scale[bone]


func bone_base_position(bone: int) -> Vector3:
	return _base_pos[bone]


# Three radius setters because the three geometries have three scaling
# contracts. The stored vector is the part's whole pose scale except for a
# bone's Z, which is its live length.
func set_bone_radius(part: int, radius: float) -> void:
	_native_dirty = true
	_thickness[part] = Vector3(radius, radius, 1.0)


func set_ball_radius(part: int, radius: float) -> void:
	_native_dirty = true
	_thickness[part] = Vector3.ONE * radius


# The cuff ring's height is baked at its real size (the wrist placement offsets
# by it), so only its radius scales.
func set_cuff_radius(part: int, radius: float) -> void:
	_native_dirty = true
	_thickness[part] = Vector3(radius, 1.0, radius)


func ball_radius(part: int) -> float:
	return _thickness[part].x
