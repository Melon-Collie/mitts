class_name SkaterArmRig
extends RefCounted

# The upper half of the body skeleton: torso, the jersey's tail (TAIL, and its
# flaps below the belt, SkaterHemFlaps), pelvis, helmet, the two deltoid caps,
# and both arms posed by IK from the hand markers.
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

# The deltoid under each cap turns this share of the way from the cap's rest hang
# (SkaterMeshBuilder.SHOULDER_CAP_REST_POLE) toward the cap, which points down
# the upper arm: the shoulder bends between the chest its base rides and the arm
# its seam follows (SkaterMeshBuilder._append_cap_surface).
const _DELTOID_SHARE: float = 0.5
# A cap's frame (+Y up the arm) as an arm prism's (+Z up the arm, X shared).
const _CAP_TO_PRISM := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 1.0, 0.0))
# Each cap's rest basis (left, right), where the deltoid turns from.
var _cap_rest: Array[Basis] = [SkaterMeshBuilder.shoulder_cap_rest(-1.0),
		SkaterMeshBuilder.shoulder_cap_rest(1.0)]
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
# and its side's cap itself. Absent without the extension; native_enabled lets
# the parity test take the GDScript path, which stays the reference.
var native_enabled: bool = true
var _native_arms: Array[RefCounted] = []
var _native_dirty: bool = true
# Per arm, the cap index (0 left, 1 right) its native was configured for.
var _native_side: PackedInt32Array = PackedInt32Array([-1, -1])
# Per cap, the arm whose native posed it last, or -1 when _basis and _girdle
# are current: the native keeps the cap's state, and the rig reads it back
# (_sync_cap) only for a repose of its own.
var _cap_posed_by: PackedInt32Array = PackedInt32Array([-1, -1])
var _trunk_texture := Basis.IDENTITY
# Each cap's share of its arm's girdle give (left, right), in the cap's own
# pose frame — see _update_arm.
var _girdle: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
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


# Reads the scene-authored placement of the four shell parts out of the
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
	_mesh.mesh = SkaterMeshBuilder.shared_upper_body_mesh()
	_mesh.set_surface_override_material(0, body_material)
	_mesh.skin = SkaterMeshBuilder.shared_upper_skin()
	_mesh.skeleton = NodePath("..")
	_skeleton.add_child(_mesh)

	# Torso, helmet and the two deltoid caps: their placement is authored in the
	# scene, so it is read out and seeded onto their bones, same as the legs.
	for bone: int in [SkaterMeshBuilder.UpperBone.TORSO,
			SkaterMeshBuilder.UpperBone.HELMET,
			SkaterMeshBuilder.UpperBone.SHOULDER_L,
			SkaterMeshBuilder.UpperBone.SHOULDER_R]:
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

	# The pelvis has no scene node to read: its profile is authored in the hips'
	# own space (SkaterMeshBuilder._PELVIS_PROFILE), so it rests at the identity
	# the sizing seam then scales about.
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
	var side_i: int = 0 if marker_local.x < 0.0 else 1
	_sync_cap(side_i)
	if not _native_arms.is_empty():
		_native_dirty = true  # the native's cap state is behind the one posed here
	var spine: Transform3D = _skeleton.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	var frame: Transform3D = _skater.drawn_upper_body()
	var hand_s: Vector3 = frame * hand_local
	var shoulder_s: Vector3 = arm_root(marker_local, hand_local)
	# The deltoid cap rides the girdle's give with the arm, in the frame it is
	# posed in (the spine's, before the trunk texture rotates it).
	_girdle[side_i] = _trunk_texture.transposed() \
			* (spine.basis.inverse() * (shoulder_s - spine * _textured_shoulder(marker_local)))
	var pole_s: Vector3 = spine.basis * _arm_pole(marker_local, pole_sign)
	var elbow_s: Vector3 = TwoBoneIK.solve_elbow(shoulder_s, hand_s,
			_skater.upper_arm_length, _skater.forearm_length, pole_s)
	_orient_shoulder_cap(marker_local, spine.affine_inverse() * shoulder_s,
			spine.affine_inverse() * elbow_s)
	var cap: Basis = spine.basis.orthonormalized() * _trunk_texture * _basis[_cap_bone(side_i)]
	_pose_arm_chain(upper, forearm, elbow_bone, cap, shoulder_s, elbow_s, hand_s)
	_pose_cuff(cuff, elbow_s, hand_s)
	_pose_glove(glove, elbow_s, hand_s, frame.basis * grip_local)


# _update_arm in C++ (NativeArmRig), bone writes included. False on a
# degenerate span, which the GDScript path's held poses answer instead.
func _native_update_arm(arm: int, marker_local: Vector3, hand_local: Vector3,
		grip_local: Vector3, pole_sign: float) -> bool:
	var side_i: int = 0 if marker_local.x < 0.0 else 1
	if _native_dirty or _native_side[arm] != side_i:
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
	_cap_posed_by[side_i] = arm
	return true


func _configure_native() -> void:
	# Both arms take the rig's current cap state, so read back whatever the
	# natives hold before handing it out again.
	_sync_cap(0)
	_sync_cap(1)
	_native_dirty = false
	var markers: PackedVector3Array = PackedVector3Array([_skater.shoulder.position,
			_skater.bottom_shoulder.position])
	for arm: int in 2:
		var side_i: int = 0 if markers[arm].x < 0.0 else 1
		_native_side[arm] = side_i
		var parts: Array = _ARM_PARTS[arm]
		var cap: int = _cap_bone(side_i)
		_native_arms[arm].configure(_thickness[parts[0]], _thickness[parts[1]],
				_thickness[parts[2]], _thickness[parts[3]], _thickness[parts[4]],
				cap, _pos[cap], _scale[cap], Transform3D(_basis[cap], _girdle[side_i]),
				deg_to_rad(_skater.wrist_break_max_deg), SkaterBodySkeleton.deltoid_bone(cap),
				_cap_rest[side_i], _DELTOID_SHARE)


# Brings the rig's own view of one cap (_basis, _girdle) up to the native that
# last posed it.
func _sync_cap(side_i: int) -> void:
	var arm: int = _cap_posed_by[side_i]
	if arm < 0:
		return
	_cap_posed_by[side_i] = -1
	var state: Transform3D = _native_arms[arm].get_cap_state()
	_basis[_cap_bone(side_i)] = state.basis
	_girdle[side_i] = state.origin


static func _cap_bone(side_i: int) -> int:
	return SkaterMeshBuilder.UpperBone.SHOULDER_L if side_i == 0 \
			else SkaterMeshBuilder.UpperBone.SHOULDER_R


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
# driven the leading shoulder forward (see repose_bone, which puts both onto the
# cap bones but deliberately not onto the arms).
#
# The arm has to be rooted here, not at the marker: the marker is gameplay
# geometry and never moves with the visible body, so an arm grown from it stays
# put while the shoulder pad it emerges from moves away. The HAND is untouched,
# so the blade keeps the position the IK solved and only the elbow re-solves;
# nothing gameplay reads changes.
func _textured_shoulder(marker_local: Vector3) -> Vector3:
	return _trunk_texture * (marker_local + _check_load_offset(signf(marker_local.x)))


# Load-up displacement of the shoulder on `side_sign`, zero on the trailing side
# and while nobody is committing. The cap bone and the arm root both take it.
func _check_load_offset(side_sign: float) -> Vector3:
	var lead: float = _skater.get_check_lead()
	if lead == 0.0:
		return Vector3.ZERO
	return CheckStanceRules.load_offset(
			CheckStanceRules.side_load(lead, side_sign),
			side_sign, _skater.shoulder_offset)


# One pose write per part, each a whole Transform3D built in skeleton space —
# the arm bones are roots, so that is their pose space. Deliberately NOT
# position/scale/look_at on nodes: that trio costs six transform operations, two
# of which resolve the global chain, and at ten parts per skater this is the
# densest such site in the rig.
#
# The arm is one sleeve, so its frames are one frame carried down it from the
# shoulder cap on its side (`cap`, skeleton space): the upper arm's is the cap's,
# the forearm's that turned through the elbow's bend, the elbow bone's turned
# half of it. Ring k of every stitched ring is then the same facet, from the
# shoulder's seam to the forearm (SkaterMeshBuilder._append_cap_surface,
# _append_elbow_surface), whatever the arm's twist.
#
# scaled_local is basis·S throughout. The plain scaled() is S·basis and puts the
# size on the wrong axes once a part tilts.
func _pose_arm_chain(upper: int, forearm: int, elbow_bone: int, cap: Basis,
		shoulder: Vector3, elbow: Vector3, hand: Vector3) -> void:
	var upper_span: Vector3 = elbow - shoulder
	var fore_span: Vector3 = hand - elbow
	var upper_frame: Basis = _arm_frame(cap, upper_span)
	var bend := Quaternion.IDENTITY
	if upper_span.length_squared() > 1e-8 and fore_span.length_squared() > 1e-8:
		bend = Quaternion(upper_span.normalized(), fore_span.normalized())
	_pose_prism(upper, shoulder, elbow, upper_frame)
	_pose_prism(forearm, elbow, hand, Basis(bend) * upper_frame)
	var half := Basis(Quaternion.IDENTITY.slerp(bend, 0.5))
	_skeleton.set_bone_pose(elbow_bone, Transform3D(
			(half * upper_frame).scaled_local(_thickness[elbow_bone]), elbow))


# The upper arm's prism frame (local −Z down the arm) from its cap's (local −Y
# down it), turned the shortest way onto `span` should the cap lag it.
static func _arm_frame(cap: Basis, span: Vector3) -> Basis:
	var prism: Basis = cap * _CAP_TO_PRISM
	if span.length_squared() < 1e-8:
		return prism
	return Basis(Quaternion(-cap.y.normalized(), span.normalized())) * prism


func _pose_prism(part: int, a: Vector3, b: Vector3, frame: Basis) -> void:
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
	# X/Y are the thickness the sizing seam owns; Z is the live bone length.
	bone_scale.z = length
	_skeleton.set_bone_pose(part, Transform3D(frame.scaled_local(bone_scale), center))


# Positions the gloved fist at the hand. Its long (local Y) axis runs wrist →
# fingers and its knuckle roll across local X; `grip` is the shaft through the
# fist (skeleton space), ZERO off the stick.
func _pose_glove(part: int, elbow: Vector3, hand: Vector3, grip: Vector3) -> void:
	var scale_v: Vector3 = _thickness[part]
	var dir: Vector3 = hand - elbow
	if dir.length_squared() < 0.0001:
		var held: Transform3D = _skeleton.get_bone_pose(part)
		held.origin = hand
		_skeleton.set_bone_pose(part, held)
		return
	var basis: Basis = glove_basis(dir.normalized(), grip, deg_to_rad(_skater.wrist_break_max_deg))
	_skeleton.set_bone_pose(part, Transform3D(basis.scaled_local(scale_v), hand))


# The fist on a forearm pointing `forearm_dir`. Off the stick it lines up with
# the forearm, rolled from world up like the cuff. On it, the knuckle roll lies
# along the shaft and the hand turns toward square across it, bending at the
# wrist by up to `max_bend` radians: the wrist breaks as the stick swings
# against the forearm.
static func glove_basis(forearm_dir: Vector3, grip: Vector3, max_bend: float) -> Basis:
	var straight := Basis.looking_at(forearm_dir, up_for_look_at(forearm_dir)) \
			* Basis(Vector3.RIGHT, PI * 0.5)
	if grip == Vector3.ZERO:
		return straight
	var across: float = forearm_dir.dot(grip)
	var square: Vector3 = forearm_dir - grip * across
	if square.length_squared() < 0.0001:
		return straight
	square = square.normalized()
	var hand_axis: Vector3 = forearm_dir
	var hinge: Vector3 = forearm_dir.cross(square)
	if hinge.length_squared() > 1e-8:
		hand_axis = forearm_dir.rotated(hinge.normalized(),
				minf(asin(clampf(absf(across), 0.0, 1.0)), max_bend))
	var knuckles: Vector3 = grip - hand_axis * grip.dot(hand_axis)
	if knuckles.length_squared() < 0.0001:
		return straight
	knuckles = knuckles.normalized()
	if knuckles.dot(straight.x) < 0.0:
		knuckles = -knuckles
	return Basis(knuckles, -hand_axis, knuckles.cross(-hand_axis))


# Glove cuff ring: its forward end sits at the hand and it extends back toward
# the elbow by its mesh height (no overlap past the hand). The ring's long axis
# is local Y: looking_at puts -Z on the bone, and the post-multiplied X(+90°)
# twist maps local Y onto it. The scale is composed AFTER that rotation
# (scaled_local, R·S) because the cuff's radius is non-uniform on a unit mesh —
# composing it the other way lands the radius on the wrong mesh axes and renders
# metre-wide flickering fins at the wrist.
func _pose_cuff(part: int, elbow: Vector3, hand: Vector3) -> void:
	var scale_v: Vector3 = _thickness[part]
	var bone_dir: Vector3 = hand - elbow
	var bone_len: float = bone_dir.length()
	if bone_len < 0.0001:
		var held: Transform3D = _skeleton.get_bone_pose(part)
		held.origin = hand
		_skeleton.set_bone_pose(part, held)
		return
	var dir: Vector3 = bone_dir / bone_len
	var center: Vector3 = hand - dir * (SkaterMeshBuilder.CUFF_HEIGHT_M * 0.5
			+ _skater.cuff_wrist_offset)
	var basis := Basis.looking_at(dir, up_for_look_at(dir)) * Basis(Vector3.RIGHT, PI * 0.5)
	_skeleton.set_bone_pose(part, Transform3D(basis.scaled_local(scale_v), center))


# Points the cap on the anchor's side down that arm's shoulder→elbow direction:
# it is the top of the sleeve, and the arm's frames are carried down from it
# (_pose_arm_chain). Two texture constraints shape the roll (the shoulder-number
# decal was authored against the caps' identity orientation):
#   - The +Y pole points AWAY from the arm: the equirect texture stays upright —
#     an along-the-arm (downward) pole renders the number flipped and mirrored.
#   - Local +X stays near world +X for BOTH caps; each side's decal picks its
#     outboard face via uv1_offset (±0.25), exactly as at identity. Flipping
#     +X outboard per side turns the left cap's number to the inside. With the
#     arm near ±X there is no such X, so the cap keeps its last one, turned onto
#     the new pole.
# Writes rotation only — the caps' scale is SkaterAppearanceCoordinator's and
# their position is the scene's, plus the girdle's give.
func _orient_shoulder_cap(marker_local: Vector3, anchor_local: Vector3,
		elbow_local: Vector3) -> void:
	var side: float = signf(marker_local.x)
	var bone: int = SkaterMeshBuilder.UpperBone.SHOULDER_L if side < 0.0 \
			else SkaterMeshBuilder.UpperBone.SHOULDER_R
	# repose_bone premultiplies this basis by the trunk texture, so the arm
	# direction has to come back to the UNTEXTURED frame the basis is built in —
	# transposed is the inverse of that pure rotation.
	var arm_dir: Vector3 = _trunk_texture.transposed() * (elbow_local - anchor_local)
	if arm_dir.length_squared() < 0.0001:
		repose_bone(bone)
		return
	var pole: Vector3 = -arm_dir.normalized()
	var toward: Vector3 = Vector3.RIGHT
	if (Vector3.RIGHT - pole * pole.x).length_squared() < 0.01:
		toward = _basis[bone].x
	_basis[bone] = SkaterMeshBuilder.shoulder_cap_basis(pole, toward)
	repose_bone(bone)


# An up vector safely non-colinear with `direction`. Falls back to
# Vector3.FORWARD when `direction` is near-vertical so look_at() doesn't warn
# about colinear basis vectors. Cylindrical meshes (cuffs, the stick knob) are
# rotationally symmetric around their long axis, so the choice of up only matters
# for the warning — not for the rendered geometry. Public because
# SkaterStickRig's knob is composed exactly like the cuffs here.
static func up_for_look_at(direction: Vector3) -> Vector3:
	if absf(direction.normalized().y) > 0.99:
		return Vector3.FORWARD
	return Vector3.UP


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
	repose_bone(SkaterMeshBuilder.UpperBone.SHOULDER_L)
	repose_bone(SkaterMeshBuilder.UpperBone.SHOULDER_R)


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
	# The check load-up displaces one cap before the texture rotates it: the
	# displacement is authored in the trunk's own frame, so it rides the roll.
	if bone == SkaterMeshBuilder.UpperBone.SHOULDER_L \
			or bone == SkaterMeshBuilder.UpperBone.SHOULDER_R:
		var side_i: int = 0 if bone == SkaterMeshBuilder.UpperBone.SHOULDER_L else 1
		_sync_cap(side_i)
		origin += _check_load_offset(signf(origin.x)) + _girdle[side_i]
		var half := Basis(Quaternion(_cap_rest[side_i]).slerp(Quaternion(_basis[bone]),
				_DELTOID_SHARE))
		_skeleton.set_bone_pose(SkaterBodySkeleton.deltoid_bone(bone),
				Transform3D(_trunk_texture, Vector3.ZERO)
				* Transform3D(half.scaled_local(_scale[bone]), origin))
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
	if bone == SkaterMeshBuilder.UpperBone.TORSO \
			or bone == SkaterMeshBuilder.UpperBone.SHOULDER_L \
			or bone == SkaterMeshBuilder.UpperBone.SHOULDER_R:
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
	# One surface on every tuck's mesh, so the body material carries over.
	_mesh.mesh = SkaterMeshBuilder.shared_upper_body_mesh(gear.jersey_tuck)
	if _hem_tuck < 0:
		_hem.setup(_skater, _skeleton, gear.jersey_tuck)
	elif gear.jersey_tuck != _hem_tuck:
		_hem.set_tuck(gear.jersey_tuck)
	_hem_tuck = gear.jersey_tuck
	_head_pieces[HeadPiece.FACE_GEAR].mesh = SkaterMeshBuilder.shared_face_gear(gear.helmet_face)
	_head_pieces[HeadPiece.SCALP].mesh = SkaterHairMesh.shared_hair(gear.hair_style)
	_head_pieces[HeadPiece.FACIAL_HAIR].mesh = SkaterHairMesh.shared_facial_hair(
			gear.facial_hair, gear.helmet_face)
	_head_pieces[HeadPiece.BROWS].mesh = SkaterHairMesh.shared_brows()


# One head piece's render node, for the uniform coordinator's paint and ghost
# fade. Null before the rig is built; its mesh is null while the piece is bare.
func head_piece(piece: HeadPiece) -> MeshInstance3D:
	return _head_pieces[piece] if piece < _head_pieces.size() else null


# ── Sizing seams ─────────────────────────────────────────────────────────────
# The four scene-authored shell parts. Their arm siblings are placed by IK and
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
