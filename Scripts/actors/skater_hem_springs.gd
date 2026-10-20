class_name SkaterHemSprings
extends SkaterHemSim

# The tail below the belt as Godot's own skirt solver: a SpringBoneSimulator3D
# with one chain per torso facet column — root at the belt point, a bend, a tip
# at the hem — whose two segments the column's vertices ride (SkaterJerseyHem
# TAIL_COLUMNS, bound at the joints' rests: SkaterMeshBuilder.shared_hem_skin).
# Colliders are the engine's: a capsule on each thigh and two across the pants,
# from the numbers SkaterHemColliders uses.
#
# The solver runs in the skeleton's frame (its drag would otherwise damp the
# skater's whole skating speed, and the hem would stream behind him as if in a
# gale), with the skater's own acceleration put back as an external force, as
# the flaps take it. It runs in the skeleton's modifier pass, after every pose
# this rig writes, which is the one place this prototype steps outside the rig's
# clock and off-camera rules: it simulates every frame, seen or not.

var stiffness: float = 1.6
var drag: float = 0.45
var gravity: float = 1.2
var joint_radius_m: float = 0.015

var _sim: SpringBoneSimulator3D = null
var _drawn := PackedVector3Array()


func setup(skater: Skater, skeleton: Skeleton3D, tuck: int) -> void:
	super.setup(skater, skeleton, tuck)
	_sim = SpringBoneSimulator3D.new()
	_sim.name = "HemSprings"
	_skeleton.add_child(_sim)
	_sim.setting_count = columns
	for k: int in columns:
		_sim.set_root_bone(k, _bone(k, 0))
		_sim.set_end_bone(k, _bone(k, 2))
		_sim.set_extend_end_bone(k, false)
		_sim.set_center_from(k, SpringBoneSimulator3D.CENTER_FROM_NODE)
		_sim.set_center_node(k, NodePath(".."))
	_configure()
	for side: int in 2:
		var leg := SpringBoneCollisionCapsule3D.new()
		leg.set_bone(SkaterBodySkeleton.LEG_BONE_OFFSET
				+ (SkaterMeshBuilder.LegBone.LEG_L if side == 0 else SkaterMeshBuilder.LegBone.LEG_R))
		leg.set_position_offset(Vector3(0.0, -SkaterMeshBuilder.THIGH_CAPSULE_LENGTH_M * 0.5, 0.0))
		leg.set_radius(SkaterMeshBuilder.THIGH_CAPSULE_RADIUS_M)
		leg.set_height(SkaterMeshBuilder.THIGH_CAPSULE_LENGTH_M
				+ 2.0 * SkaterMeshBuilder.THIGH_CAPSULE_RADIUS_M)
		_sim.add_child(leg)
	# The pants: two capsules lying across the hips, through the waistband and
	# the seat, each as wide and as deep as the lathe there.
	for y: float in [-0.02, -0.12]:
		var ring: Vector2 = SkaterMeshBuilder.pelvis_ring(y)
		var pants := SpringBoneCollisionCapsule3D.new()
		pants.set_bone(SkaterMeshBuilder.UpperBone.PELVIS)
		pants.set_position_offset(Vector3(0.0, y, ring.y))
		pants.set_rotation_offset(Quaternion(Vector3.BACK, PI * 0.5))
		pants.set_radius(ring.x * SkaterMeshBuilder.PELVIS_XZ_SCALE.y)
		pants.set_height(2.0 * ring.x * SkaterMeshBuilder.PELVIS_XZ_SCALE.x)
		_sim.add_child(pants)
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)


func _bone(column: int, joint: int) -> int:
	return SkaterBodySkeleton.column_bone(HemSimMode.SPRINGS, column, joint)


# Chain rests are the tucked drape's points, each joint's relative to the one
# above it (the root's to TAIL).
func _rested() -> void:
	for k: int in columns:
		var points: Array[Vector3] = [rest[0][k], rest[BEND][k], rest[HEM][k]]
		for joint: int in 3:
			var at: Vector3 = points[joint] - (points[joint - 1] if joint > 0 else Vector3.ZERO)
			_skeleton.set_bone_rest(_bone(k, joint), Transform3D(Basis.IDENTITY, at))
			_skeleton.reset_bone_pose(_bone(k, joint))
	if _sim != null:
		_configure()
		_sim.reset()


# A tucked chain is held to its rest by the belt: stiff, weightless, and out of
# the colliders it sits inside of.
func _configure() -> void:
	for k: int in columns:
		var t: float = tuck_share[k]
		_sim.set_radius(k, joint_radius_m)
		_sim.set_stiffness(k, lerpf(stiffness, 40.0, t))
		_sim.set_drag(k, drag)
		_sim.set_gravity(k, gravity * (1.0 - t))
		_sim.set_gravity_direction(k, Vector3.DOWN)
		_sim.set_enable_all_child_collisions(k, t < 0.5)


func update(_delta: float, _on_camera: bool) -> void:
	var tail: Transform3D = _tail()
	var anchor: PackedVector3Array = anchors(_torso(), tail)
	var to_tail: Transform3D = tail.affine_inverse()
	for k: int in columns:
		_skeleton.set_bone_pose_position(_bone(k, 0), to_tail * anchor[k])
	# Gravity's own scale: `gravity` stands for one g.
	_sim.external_force = _skeleton.global_basis * -_acceleration() * (gravity / 9.8)


func _on_skeleton_updated() -> void:
	_drawn.resize(columns * 4)
	for k: int in columns:
		var root: Vector3 = _skeleton.get_bone_global_pose(_bone(k, 0)).origin
		var bend: Vector3 = _skeleton.get_bone_global_pose(_bone(k, 1)).origin
		var tip: Vector3 = _skeleton.get_bone_global_pose(_bone(k, 2)).origin
		_drawn[k * 4] = bend
		_drawn[k * 4 + 1] = tip
		_drawn[k * 4 + 2] = (root + bend) * 0.5
		_drawn[k * 4 + 3] = (bend + tip) * 0.5


func hem_points() -> PackedVector3Array:
	return _drawn
