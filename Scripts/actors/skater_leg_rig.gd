class_name SkaterLegRig
extends RefCounted

# The lower-body skeleton and the gait written onto it.
#
# Both legs are one skinned mesh on the body skeleton, fourteen bones in the
# chain Hips → Leg → Shin (see SkaterMeshBuilder.LegBone). Bone indices here are
# LegBone values; the skeleton holds them past the upper bones, at _OFFSET. Twelve of the bones
# carry geometry; the four pivots exist to be rotated by the gait
# (SkaterSkatingCoordinator).
#
# Pose = basis · scale, at position, each part stored separately: `_basis` is the
# authored rest rotation (constant for the twelve geometry bones; the four pivots
# are rewritten by set_swing), `_scale` and `_pos` are the sizing seam's.
#
# Also the source of the ice VFX's two reads — where a skate is being DRAWN and
# how hard its edge is loaded — because both are properties of this skeleton and
# of nothing else.

const _OFFSET: int = SkaterBodySkeleton.LEG_BONE_OFFSET

var _skater: Skater
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _basis: Array[Basis] = []
var _scale: PackedVector3Array = PackedVector3Array()
var _pos: PackedVector3Array = PackedVector3Array()
# The scene's authored shin euler, kept so the knee write can preserve its Y/Z
# the way a node's `rotation.x = v` did. Index 0 = left, 1 = right.
var _shin_base_euler: PackedVector3Array = PackedVector3Array()
# True while the skate bones carry an ankle angle, so set_ankle_flatten knows it
# still owes one write to put them back (see there).
var _ankles_posed: bool = false
# The ankle weights the gait last asked for (set_ankle_flatten).
var _ankle_l: float = 0.0
var _ankle_r: float = 0.0
# The bounds of a skate's two assemblies, in their bones' frames: the boot
# (shell, holder, runner) on FOOT, the cuff on SKATE.
var _skate_boxes: Array[AABB] = []
# Untouched baselines the sizing seam multiplies against, captured off the scene
# subtree before it is freed.
var _base_scale: PackedVector3Array = PackedVector3Array()
var _base_pos: PackedVector3Array = PackedVector3Array()

# Last gait-authored leg pose (hip pivot euler (pitch, yaw, roll) + knee fold
# per leg), cached so the knockdown sprawl can compose ON TOP of whatever the
# gait wrote this frame instead of guessing it: the gait's own crumple blend
# keeps easing underneath the overlay through the get-up, so the handoff back
# to the live stride stays continuous at both ends.
var _gait_leg_l: Vector3 = Vector3.ZERO
var _gait_leg_r: Vector3 = Vector3.ZERO
var _gait_knee_l: float = 0.0
var _gait_knee_r: float = 0.0

# Per-blade edge load [0, 1], published by the gait each pose pass (push
# extension, carve under-push, hockey-stop scrape): the ice VFX scale mark
# intensity by it, so a loaded edge bites visibly harder than a glide.
var _edge_load_l: float = 0.0
var _edge_load_r: float = 0.0


func setup(skater: Skater) -> void:
	_skater = skater


# Reads the leg segment offsets out of the scene's LowerBody subtree, seeds the
# body skeleton's leg bones from them, then frees the subtree.
#
# Reading the scene rather than hard-coding the offsets keeps Scenes/Skater.tscn
# the place leg proportions are authored — the nodes are still what you edit to
# move a knee, they just stop existing at runtime. Hard-coding them here would
# fork the numbers into two files that no test compares.
func build(skeleton: Skeleton3D) -> void:
	var count: int = SkaterMeshBuilder.LEG_BONE_COUNT
	var lower_body: Node3D = _skater.lower_body
	_basis.resize(count)
	_scale.resize(count)
	_pos.resize(count)
	_base_scale.resize(count)
	_base_pos.resize(count)
	_shin_base_euler.resize(2)

	_skeleton = skeleton
	for bone: int in count:
		var node: Node3D = lower_body.get_node(
				SkaterMeshBuilder.LEG_BONE_NODE[bone]) as Node3D
		var xform: Transform3D = node.transform
		var part_scale: Vector3 = xform.basis.get_scale()
		_basis[bone] = xform.basis.orthonormalized()
		_scale[bone] = part_scale
		_pos[bone] = xform.origin
		_base_scale[bone] = part_scale
		_base_pos[bone] = xform.origin
	_shin_base_euler[0] = _basis[SkaterMeshBuilder.LegBone.SHIN_L].get_euler()
	_shin_base_euler[1] = _basis[SkaterMeshBuilder.LegBone.SHIN_R].get_euler()

	for bone: int in count:
		_repose_bone(bone)
	# Freed only after every offset is read — the whole point of the subtree.
	# free() rather than queue_free(): a deferred free renders the scene's
	# placeholder primitives through the real legs for the frame it waits. Safe
	# here — these are plain children whose _ready has run, and nothing is
	# iterating the subtree.
	lower_body.get_node("LegL").free()
	lower_body.get_node("LegR").free()

	_skate_boxes = [SkaterMeshBuilder.shared_boot_assembly().get_aabb(),
			SkaterMeshBuilder.shared_skate_assembly().get_aabb()]
	_mesh = MeshInstance3D.new()
	_mesh.name = "LegMesh"
	_mesh.mesh = SkaterMeshBuilder.shared_leg_skin_mesh()
	_mesh.skin = SkaterMeshBuilder.shared_leg_skin()
	_mesh.skeleton = NodePath("..")
	_skeleton.add_child(_mesh)


func _repose_bone(bone: int) -> void:
	_skeleton.set_bone_pose(_OFFSET + bone, Transform3D(
			_basis[bone].scaled_local(_scale[bone]), _pos[bone]))


# ── Gait ─────────────────────────────────────────────────────────────────────

# Hip pitch/roll and knee bend, straight onto the four pivot bones. All radians:
# pitch = fore/aft swing (local X) and roll = side-to-side splay (local Z) of the
# whole leg about the hip; knee = flex of the lower leg (local X) about the knee.
#
# The pivots carry no scale and their authored rotation is overwritten outright,
# so the pose is the gait's basis over the sizing seam's position. The knee write
# owns X only — `_shin_base_euler` carries the scene's authored Y/Z into the
# composed basis.
func set_swing(left_pitch: float, left_roll: float, left_knee: float,
		right_pitch: float, right_roll: float, right_knee: float,
		left_yaw: float = 0.0, right_yaw: float = 0.0) -> void:
	var base_l: Vector3 = _shin_base_euler[0]
	var base_r: Vector3 = _shin_base_euler[1]
	_gait_leg_l = Vector3(left_pitch, left_yaw, left_roll)
	_gait_leg_r = Vector3(right_pitch, right_yaw, right_roll)
	_gait_knee_l = left_knee
	_gait_knee_r = right_knee
	# Yaw rides the hip pivot's free Y slot: YXZ euler order puts it outermost,
	# so the leg externally rotates about vertical and the shin + boot carry it
	# — the mohawk open hip. Defaults keep the pre-yaw callers unchanged.
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_L,
			Vector3(left_pitch, left_yaw, left_roll))
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_L,
			Vector3(left_knee, base_l.y, base_l.z))
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_R,
			Vector3(right_pitch, right_yaw, right_roll))
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_R,
			Vector3(right_knee, base_r.y, base_r.z))


# Knockdown leg sprawl: re-poses the leg pivots as the cached gait pose plus the
# sprawl overlay, which arrives already eased (SkaterController
# ._apply_knockdown_fall calls this after the gait and the tilt, only while a
# skater is down). `weight` is the down pose's share, which the ankles hold by.
func apply_knockdown_overlay(pose: KnockdownFallRules.SprawlPose,
		weight: float) -> void:
	if weight <= 0.001:
		return
	var base_l: Vector3 = _shin_base_euler[0]
	var base_r: Vector3 = _shin_base_euler[1]
	var leg_l: Vector3 = _gait_leg_l + Vector3(pose.l_pitch, 0.0, pose.l_roll)
	var leg_r: Vector3 = _gait_leg_r + Vector3(pose.r_pitch, 0.0, pose.r_roll)
	var knee_l: float = _gait_knee_l + pose.l_knee
	var knee_r: float = _gait_knee_r + pose.r_knee
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_L, leg_l)
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_L, Vector3(knee_l, base_l.y, base_l.z))
	_pose_pivot(SkaterMeshBuilder.LegBone.LEG_R, leg_r)
	_pose_pivot(SkaterMeshBuilder.LegBone.SHIN_R, Vector3(knee_r, base_r.y, base_r.z))
	# The ankles give the buckle back as they do any deep sit: a shin folded
	# back by it otherwise drives the toe into the ice.
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_L, leg_l, knee_l, base_l,
			lerpf(_ankle_l, 1.0, weight))
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_R, leg_r, knee_r, base_r,
			lerpf(_ankle_r, 1.0, weight))
	_ankles_posed = true
	_rest_on_ice(SkaterMeshBuilder.LegBone.LEG_L, SkaterMeshBuilder.LegBone.FOOT_L,
			SkaterMeshBuilder.LegBone.SKATE_L)
	_rest_on_ice(SkaterMeshBuilder.LegBone.LEG_R, SkaterMeshBuilder.LegBone.FOOT_R,
			SkaterMeshBuilder.LegBone.SKATE_R)


# The ice holds a downed leg up. Tipping the body puts the skates wherever the
# hips carry them — under the ice on the side it falls toward, and wherever the
# sprawl flings them — so a leg whose skate ends up below swings about its hip,
# toward up, until the skate rests on the ice: the leg the body tips over stays
# planted, and a leg lying on the ice lies on it. Reads the MeshRoot tilt the
# fall wrote this frame (Skater.set_knockdown_fall runs first). A few passes,
# because the swing can hand the lowest point to another corner of the skate.
# Works in MeshRoot's parent frame, the skater's own, where the ice is flat at
# −global_position.y.
func _rest_on_ice(leg: int, foot: int, skate: int) -> void:
	var to_body: Transform3D = _skater.mesh_root.transform * _skeleton.transform
	var ice: float = -_skater.global_position.y
	for _pass: int in 4:
		var hip: Vector3 = to_body * _skeleton.get_bone_global_pose(_OFFSET + leg).origin
		var low: Vector3 = _lowest_corner(to_body, foot, skate)
		var sink: float = ice - low.y
		if sink <= 0.0:
			return
		var r: Vector3 = low - hip
		var r_h := Vector2(r.x, r.z)
		var reach: float = r.length()
		if r_h.length() < 0.01 or reach < 0.01:
			return
		# Swing r in the vertical plane through it until it is `sink` higher:
		# its height is reach·sin(φ + β), β its current elevation.
		var beta: float = atan2(r.y, r_h.length())
		var phi: float = asin(clampf((r.y + sink) / reach, -1.0, 1.0)) - beta
		var axis_body: Vector3 = r.cross(Vector3.UP).normalized()
		var axis: Vector3 = (to_body.basis * _skeleton.get_bone_global_pose(
				_skeleton.get_bone_parent(_OFFSET + leg)).basis).inverse() * axis_body
		var pose: Transform3D = _skeleton.get_bone_pose(_OFFSET + leg)
		_skeleton.set_bone_pose(_OFFSET + leg, Transform3D(
				Basis(axis.normalized(), phi) * pose.basis, pose.origin))


# The lowest corner of a skate's two boxes — the boot on `foot`, the cuff on
# `skate` — in `to_body`'s space. Corners rather than vertices: a downed skater
# runs this every frame, and a corner only ever errs high.
func _lowest_corner(to_body: Transform3D, foot: int, skate: int) -> Vector3:
	var lowest := Vector3(0.0, INF, 0.0)
	for i: int in 2:
		var part: Transform3D = to_body * _skeleton.get_bone_global_pose(
				_OFFSET + (foot if i == 0 else skate))
		var box: AABB = _skate_boxes[i]
		for corner: int in 8:
			var p: Vector3 = part * box.get_endpoint(corner)
			if p.y < lowest.y:
				lowest = p
	return lowest


func _pose_pivot(bone: int, euler: Vector3) -> void:
	_skeleton.set_bone_pose(_OFFSET + bone, Transform3D(Basis.from_euler(euler), _pos[bone]))


# Levels a skate against everything the leg above it did: `weight` of the hip's
# splay and the knee's fold unwound at the ankle, that leg's yaw kept. The boot
# hangs off the end of the shin and inherits the whole chain, so a leg rolled far
# out of vertical — the shot block's extended leg — swings its blade up onto an
# edge and clear of the ice, and a shin folded far back — the faceoff centre's
# deep sit — stands it on its heel. A real ankle gives that back, which is what
# lets a player hold either pose on a flat blade.
#
# Stated as a weight rather than two angles because two angles cannot undo this
# chain: the splay is taken at the hip, ahead of a knee fold that can pass 90°,
# so by the time it reaches the boot it is no longer a roll about anything the
# ankle owns. The give-back is the chain's own rotation inverted, which is exact
# at any depth — and needs nothing passed in, since set_swing just wrote it.
#
# Unlike the pivots this bone carries an authored rotation and the sizing seam's
# scale, so the give-back composes onto the rest basis rather than replacing it.
# Skipped while both ankles are square (and once more to settle back), so the
# common case adds no writes to the render-rate rig pass.
func set_ankle_flatten(left: float, right: float) -> void:
	_ankle_l = left
	_ankle_r = right
	var square: bool = is_zero_approx(left) and is_zero_approx(right)
	if square and not _ankles_posed:
		return
	_ankles_posed = not square
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_L, _gait_leg_l, _gait_knee_l,
			_shin_base_euler[0], left)
	_pose_foot(SkaterMeshBuilder.LegBone.FOOT_R, _gait_leg_r, _gait_knee_r,
			_shin_base_euler[1], right)


func _pose_foot(bone: int, leg: Vector3, knee: float, shin_base: Vector3,
		weight: float) -> void:
	# What the chain did to this boot, and what it would have done carrying the
	# leg's yaw alone. Their difference, in the boot's own frame, is the ankle's
	# give-back; the slerp eases it in from square.
	var shin: Basis = Basis.from_euler(Vector3(knee, shin_base.y, shin_base.z))
	var posed: Basis = Basis.from_euler(leg) * shin
	var level: Basis = Basis.from_euler(Vector3(0.0, leg.y, 0.0)) \
			* Basis.from_euler(Vector3(0.0, shin_base.y, shin_base.z))
	var give_back: Basis = (posed.inverse() * level).orthonormalized()
	var basis: Basis = Basis.IDENTITY.slerp(give_back, weight) * _basis[bone]
	_skeleton.set_bone_pose(_OFFSET + bone,
			Transform3D(basis.scaled_local(_scale[bone]), _pos[bone]))


# ── Ice VFX seams ────────────────────────────────────────────────────────────

func set_edge_loads(left: float, right: float) -> void:
	_edge_load_l = left
	_edge_load_r = right


func edge_load(left: bool) -> float:
	return _edge_load_l if left else _edge_load_r


# World position of a FOOT bone, composed through everything the gait wrote —
# lower-body yaw (alignment / pivot / stop), stride pitch, the mohawk yaw — so
# ice marks made from here follow the SKATES, not the torso. Falls back to the
# old body-center offset until the rig is built.
#
# The transform half is read INTERPOLATED, the bone pose half as-is: the body
# renders between tick poses, while the bone pose is whatever the render-rate
# gait wrote this frame. Composing the two gives the drawn body carrying the
# drawn foot; a plain global_transform read lays every stroke up to a tick of
# travel ahead of the skate that cut it.
func mark_position(left: bool) -> Vector3:
	if _skeleton == null:
		var t: Transform3D = _skater.get_global_transform_interpolated()
		return t.origin + t.basis.x * (-0.12 if left else 0.12)
	var bone: int = SkaterMeshBuilder.LegBone.FOOT_L if left \
			else SkaterMeshBuilder.LegBone.FOOT_R
	return (_skeleton.get_global_transform_interpolated()
			* _skeleton.get_bone_global_pose(_OFFSET + bone)).origin


# ── Sizing seam ──────────────────────────────────────────────────────────────
# Scale and position are applied in separate passes by
# SkaterAppearanceCoordinator (a part can take one, the other, or both), so each
# setter writes its own component and recomposes. Attribute-apply rate, not per
# frame.
func set_bone_scale(bone: int, part_scale: Vector3) -> void:
	_scale[bone] = part_scale
	_repose_bone(bone)


func set_bone_position(bone: int, pos: Vector3) -> void:
	_pos[bone] = pos
	_repose_bone(bone)


# Read seams for the gait tests: the rotation the gait wrote and the position the
# sizing seam wrote. The euler round-trips exactly for the four pivots, whose
# basis is built from one (set_swing).
func bone_euler(bone: int) -> Vector3:
	return _skeleton.get_bone_pose(_OFFSET + bone).basis.get_euler()


func bone_position(bone: int) -> Vector3:
	return _skeleton.get_bone_pose(_OFFSET + bone).origin


func bone_base_scale(bone: int) -> Vector3:
	return _base_scale[bone]


func bone_base_position(bone: int) -> Vector3:
	return _base_pos[bone]


func surface_material(surface: int) -> StandardMaterial3D:
	return SkaterMeshBuilder.surface_override(_mesh, surface)


func set_surface_material(surface: int, mat: Material) -> void:
	_mesh.set_surface_override_material(surface, mat)
