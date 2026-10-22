class_name GoalieLimbRig
extends Node3D

# The goalie's drawn limbs: both arms (upper arm, forearm, elbow cap), the
# shoulder floaters and the hip connectors, built here and posed every rendered
# frame onto the parts Goalie moves. Nothing here feeds a save — the colliders
# and the blocker's elbow are Goalie's — so a skipped frame is purely cosmetic.
# The rig sits at the goalie's origin, so its children are in goalie-local space.

# A chest protector's arms are padded: a thick bicep (GoalieAnatomy, since the
# blocker's elbow solve clears the trunk by it), an elbow cap, and a forearm pad
# tapering to the wrist.
const _FOREARM_RADIUS: float = 0.075
const _ELBOW_SPHERE_RADIUS: float = 0.09
# Shoulder floaters: the broad caps a chest protector carries over each
# shoulder, set outboard and up of the joint so they stand past the trunk and
# above the collar, which is the goalie's shoulder line from the top-down
# camera. Semi-axes in the body's frame; tilt with the trunk.
const FLOATER_SEMI_AXES := Vector3(0.13, 0.10, 0.125)
const FLOATER_OUTSET := Vector3(0.02, 0.03, 0.0)
# The glove forearm ends here, in the Glove's frame, rather than at its origin:
# behind the trapper's heel, where the cuff opening takes a real forearm, so
# the arm meets the back of the hand instead of running through its thumb.
const _GLOVE_CUFF_IN_GLOVE := Vector3(0.0, -0.03, 0.07)

var left_hip_connector: MeshInstance3D = null
var right_hip_connector: MeshInstance3D = null
var glove_upper_arm: Node3D = null
var glove_forearm: Node3D = null
var blocker_upper_arm: Node3D = null
var blocker_forearm: Node3D = null
var glove_shoulder_sphere: MeshInstance3D = null
var blocker_shoulder_sphere: MeshInstance3D = null
var glove_elbow_sphere: MeshInstance3D = null
var blocker_elbow_sphere: MeshInstance3D = null

var _goalie: Goalie
var _body: Node3D
var _left_pad: Node3D
var _right_pad: Node3D
var _glove: Node3D
var _block_arm: Node3D

# Dirty-skip cache for `update`: a settled goalie holds its stance for seconds,
# and his parts only move when a pose is applied. Default-mismatched so the
# first frame always poses.
var _last_body_xform: Transform3D
var _last_left_pad_pos: Vector3 = Vector3.INF
var _last_right_pad_pos: Vector3
var _last_glove_xform: Transform3D = Transform3D()
var _last_block_arm_xform: Transform3D = Transform3D()


func _init(goalie: Goalie) -> void:
	_goalie = goalie
	name = "LimbRig"
	_body = goalie.get_node("Body") as Node3D
	_left_pad = goalie.get_node("LeftPad") as Node3D
	_right_pad = goalie.get_node("RightPad") as Node3D
	_glove = goalie.get_node("Glove") as Node3D
	_block_arm = goalie.get_node("BlockArm") as Node3D
	left_hip_connector = _add_connector()
	right_hip_connector = _add_connector()
	glove_upper_arm = _add_arm_bone(GoalieAnatomy.ARM_UPPER_RADIUS_M)
	glove_forearm = _add_arm_bone(_FOREARM_RADIUS)
	blocker_upper_arm = _add_arm_bone(GoalieAnatomy.ARM_UPPER_RADIUS_M)
	blocker_forearm = _add_arm_bone(_FOREARM_RADIUS)
	glove_shoulder_sphere = _add_sphere(1.0)
	blocker_shoulder_sphere = _add_sphere(1.0)
	glove_elbow_sphere = _add_sphere(_ELBOW_SPHERE_RADIUS)
	blocker_elbow_sphere = _add_sphere(_ELBOW_SPHERE_RADIUS)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		update()


# Bridges each part pair with its limb. Root translation and yaw don't dirty
# the pose: the limbs ride the goalie rigidly, so only the body-local part
# transforms matter.
func update() -> void:
	if not _pose_changed():
		return
	# Anchor offsets are body-local against the torso box in Goalie.tscn
	# (half-height 0.36): hips near the box bottom, shoulders a hand's width
	# below the box top.
	_point_connector(left_hip_connector,
		_body.position + _body.basis * Vector3(-0.10, -0.30, 0.0),
		_left_pad.position)
	_point_connector(right_hip_connector,
		_body.position + _body.basis * Vector3(0.10, -0.30, 0.0),
		_right_pad.position)
	var glove_shoulder: Vector3 = _body.position + _body.basis * Vector3(
			-GoalieAnatomy.SHOULDER_OFFSET.x, GoalieAnatomy.SHOULDER_OFFSET.y, 0.0)
	var blocker_shoulder: Vector3 = _body.position + _body.basis * GoalieAnatomy.SHOULDER_OFFSET
	var floater_basis: Basis = _body.basis.scaled_local(FLOATER_SEMI_AXES)
	glove_shoulder_sphere.transform = Transform3D(floater_basis, glove_shoulder
			+ _body.basis * Vector3(-FLOATER_OUTSET.x, FLOATER_OUTSET.y, FLOATER_OUTSET.z))
	blocker_shoulder_sphere.transform = Transform3D(floater_basis,
			blocker_shoulder + _body.basis * FLOATER_OUTSET)
	# Glove arm: shoulder on body's left side (goalie's catch hand).
	_update_arm_ik(glove_upper_arm, glove_forearm,
		glove_shoulder, _glove.position + _glove.basis * _GLOVE_CUFF_IN_GLOVE, Vector3.LEFT,
		glove_elbow_sphere)
	# Blocker arm: drawn to the elbow the board was seated from, so it is the
	# arm the board rides.
	var blocker_elbow: Vector3 = _goalie.get_blocker_elbow()
	blocker_elbow_sphere.position = blocker_elbow
	_update_arm_bone(blocker_upper_arm, blocker_shoulder, blocker_elbow)
	_update_arm_bone(blocker_forearm, blocker_elbow, _block_arm.position)


# Returns true (and refreshes the snapshot) when any input to `update` moved
# since the last pose. Exact equality is sufficient: a converged lerp produces
# bit-identical transforms tick over tick. The blocker elbow is a function of
# the body and BlockArm transforms, so those cover it.
func _pose_changed() -> bool:
	if _body.transform == _last_body_xform \
			and _left_pad.position == _last_left_pad_pos \
			and _right_pad.position == _last_right_pad_pos \
			and _glove.transform == _last_glove_xform \
			and _block_arm.transform == _last_block_arm_xform:
		return false
	_last_body_xform = _body.transform
	_last_left_pad_pos = _left_pad.position
	_last_right_pad_pos = _right_pad.position
	_last_glove_xform = _glove.transform
	_last_block_arm_xform = _block_arm.transform
	return true


# Two-bone arm IK. shoulder_local / hand_local are in goalie-local space;
# outward_local is the arm's side (±X), which the elbow may not fold inside of.
func _update_arm_ik(upper: Node3D, forearm_bone: Node3D,
		shoulder_local: Vector3, hand_local: Vector3, outward_local: Vector3,
		elbow_sphere: MeshInstance3D) -> void:
	var shoulder_w: Vector3 = _goalie.to_global(shoulder_local)
	var hand_w: Vector3 = _goalie.to_global(hand_local)
	var basis_w: Basis = _goalie.global_transform.basis
	# He faces local -Z.
	var elbow_w: Vector3 = TwoBoneIK.solve_elbow_hanging(
			shoulder_w, hand_w, GoalieAnatomy.ARM_UPPER_M, GoalieAnatomy.ARM_FOREARM_M,
			basis_w * Vector3.FORWARD, basis_w * outward_local,
			GoalieAnatomy.ELBOW_CLEARS_TRUNK_M)
	var elbow_local: Vector3 = _goalie.to_local(elbow_w)
	elbow_sphere.position = elbow_local
	_update_arm_bone(upper, shoulder_local, elbow_local)
	_update_arm_bone(forearm_bone, elbow_local, hand_local)


func _update_arm_bone(bone: Node3D, a_local: Vector3, b_local: Vector3) -> void:
	var span: Vector3 = b_local - a_local
	var length: float = span.length()
	var center: Vector3 = (a_local + b_local) * 0.5
	if length < 0.0001:
		bone.position = center
		return
	# One local transform write, not position + scale + look_at. look_at costs
	# six transform operations, two of which resolve the global chain; the prism
	# is rotationally symmetric so the up vector only has to dodge colinearity.
	# X/Y carry the arm thickness and stay as the sizing seam left them.
	var bone_scale: Vector3 = bone.scale
	bone_scale.z = length
	bone.transform = Transform3D(
			Basis.looking_at(span / length, _up_for_look_at(span)).scaled_local(bone_scale),
			center)


static func _up_for_look_at(direction: Vector3) -> Vector3:
	if absf(direction.normalized().y) > 0.99:
		return Vector3.FORWARD
	return Vector3.UP


func _point_connector(mesh: MeshInstance3D, from_pos: Vector3, to_pos: Vector3) -> void:
	var diff: Vector3 = to_pos - from_pos
	var length: float = diff.length()
	if length < 0.02:
		mesh.visible = false
		return
	mesh.visible = true
	mesh.position = (from_pos + to_pos) * 0.5
	# Orient the unit tube (Y-axis aligned) to point from from_pos to to_pos.
	# The stretch to the span's length rides the basis Y column — mesh
	# mutation would leak through the shared connector mesh to every goalie.
	var y_axis: Vector3 = diff / length
	var ref: Vector3 = Vector3.FORWARD if abs(y_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = ref.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	mesh.basis = Basis(x_axis, y_axis * length, z_axis)


# Unit-height shared tube (radius baked at HIP_CONNECTOR_RADIUS); the
# per-frame stretch lives in _point_connector's basis, not the mesh.
func _add_connector() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = GoalieMeshBuilder.shared_connector_tube()
	add_child(mi)
	return mi


# ONE MeshInstance3D per bone, carrying the prism whose long axis is already local
# Z (shared_arm_bone_z bakes that rotation into the mesh, so no child node has to
# apply it). X/Y are the arm THICKNESS; Z is the length _update_arm_bone() rewrites
# per frame — each writer reads the other's components back rather than overwriting
# the whole vector.
func _add_arm_bone(radius: float) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = SkaterMeshBuilder.shared_arm_bone_z()
	mi.scale = Vector3(radius, radius, 1.0)
	add_child(mi)
	return mi


func _add_sphere(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = SkaterMeshBuilder.shared_joint_ball()
	mi.scale = Vector3.ONE * radius
	add_child(mi)
	return mi
