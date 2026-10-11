class_name SkaterSpineRig
extends RefCounted

# The four bones that join the body into one figure: HIPS, the frame the legs
# hang from; WAIST, the pelvis the shorts ride; SPINE, the trunk frame the shell
# and the arm roots hang from; and NECK, which carries the head. None carries
# vertices.
#
# All four are built from the two gameplay-side frames, read and never written:
# `LowerBody` carries the hip yaw and pitch the gait and pose coordinator sum,
# `UpperBody` the facing twist and lean the blade hangs from. What this adds is
# the ORDER a body is built in. The trunk folds forward about the hips' own
# axis and then twists on top of the fold, so turning the shoulders toward the
# stick turns a leaned torso about its spine rather than tipping it sideways
# off the hips; and the shoulders cannot turn further from the hips than a
# spine can, so past that the hips come round with them.
#
# On top of that order sits the balance lean (Skater.balance_tilt, stepped in
# the physics tick): the whole body tilts toward its horizontal acceleration
# about the ice under the skater, so the blades stay where they are and the body
# goes over them. The tip itself is LowerBody's shift (Skater._update_lean_shift)
# — the hips bone sits on that frame and takes the full lean, the legs hang from
# it back down to the ice. The trunk leans by its own tilt (Skater.trunk_tilt:
# part of the lean, trailing the hips') and the neck takes part of that back
# (Skater.head_level_share).

# Shoulders against hips: the trunk's comfortable axial rotation, thoracic and
# lumbar together.
const TWIST_LIMIT: float = deg_to_rad(55.0)
# Share of that twist the pelvis takes over the hip joints. The shorts are one
# rigid shell and so is the jersey, so the twist shows as a seam wherever it
# happens; splitting it puts half at the hem and half at the hip balls instead of
# all of it at the hem.
const WAIST_TWIST_SHARE: float = 0.5

var _skater: Skater
var _skeleton: Skeleton3D = null
var _hips_pose := Transform3D.IDENTITY
var _waist_pose := Transform3D.IDENTITY
var _spine_pose := Transform3D.IDENTITY
var _neck_pose := Transform3D.IDENTITY
# Everything update() reads, as of its last solve. The render pass asks for the
# spine from several places a frame (the crouch, the arm rebuilds, the pass
# itself); a call whose inputs all match is answered without building a basis.
var _in_hip := Vector3(NAN, NAN, NAN)
var _in_trunk := Vector3.ZERO
var _in_lower_pos := Vector3.ZERO
var _in_basis := Basis.IDENTITY
var _in_tilt := Vector2.ZERO
var _in_trunk_tilt := Vector2.ZERO
var _in_fold: float = 0.0
var _in_drop: float = 0.0
var _in_shoulder_y: float = 0.0
var _in_plant: float = 0.0
var _in_legs: int = -1
# Moved since the mesh pass last asked (take_moved): the render pass solves the
# spine early, from the crouch, so the arms cannot read it off update()'s answer.
var _moved_unseen: bool = true


func setup(skater: Skater) -> void:
	_skater = skater


func build(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	update()


# Re-derives the four bones from the two frames and the balance lean. Returns
# true when any moved, so the arm IK knows its roots did even if no hand marker
# moved.
func update() -> bool:
	var lower: Node3D = _skater.lower_body
	var upper: Node3D = _skater.upper_body
	var hip: Vector3 = lower.rotation
	var trunk: Vector3 = upper.rotation
	var fold: float = _skater.trunk_fold()
	var skater_basis: Basis = _skater.global_transform.basis
	var tilt_in: Vector2 = _skater.balance_tilt()
	var trunk_tilt_in: Vector2 = _skater.trunk_tilt()
	var drop: float = _skater.body_drop_below_frame()
	var shoulder_y: float = _skater.shoulder.position.y
	var plant: float = _skater.ground_plant()
	var legs: int = _skater.leg_pose_version()
	if hip == _in_hip and trunk == _in_trunk and fold == _in_fold \
			and lower.position == _in_lower_pos and skater_basis == _in_basis \
			and tilt_in == _in_tilt and trunk_tilt_in == _in_trunk_tilt \
			and drop == _in_drop and shoulder_y == _in_shoulder_y \
			and plant == _in_plant and legs == _in_legs:
		return false
	_in_hip = hip
	_in_trunk = trunk
	_in_fold = fold
	_in_lower_pos = lower.position
	_in_basis = skater_basis
	_in_tilt = tilt_in
	_in_trunk_tilt = trunk_tilt_in
	_in_drop = drop
	_in_shoulder_y = shoulder_y
	_in_plant = plant
	_in_legs = legs
	var twist: float = clampf(angle_difference(hip.y, trunk.y), -TWIST_LIMIT, TWIST_LIMIT)
	var hip_basis := Basis.from_euler(Vector3(hip.x, trunk.y - twist, 0.0))
	var waist_yaw: float = twist * WAIST_TWIST_SHARE
	var waist_basis := Basis(Vector3.UP, waist_yaw)

	# The lean, in skeleton space (the skater root's frame), as an axis and angle.
	var to_body: Basis = skater_basis.inverse()
	var tilt3: Vector3 = to_body * Vector3(tilt_in.x, 0.0, tilt_in.y)
	var theta: float = tilt3.length()
	var lean := Basis.IDENTITY
	if theta > 1e-4:
		lean = Basis(Vector3.UP.cross(tilt3 / theta), theta)
	# The trunk's own lean, trailing the hips' (Skater.trunk_tilt).
	var trunk3: Vector3 = to_body * Vector3(trunk_tilt_in.x, 0.0, trunk_tilt_in.y)
	var trunk_theta: float = trunk3.length()
	var trunk_lean := Basis.IDENTITY
	var trunk_axis := Vector3.RIGHT
	if trunk_theta > 1e-4:
		trunk_axis = Vector3.UP.cross(trunk3 / trunk_theta)
		trunk_lean = Basis(trunk_axis, trunk_theta)
	# LowerBody already carries the lean's shift; the visible hips sit below it
	# by the part of the crouch the gameplay frame does not take
	# (Skater.set_skating_crouch_drop), then are seated on the blades
	# (SkaterLegRig.seat_on_ice, which also plants the second foot).
	var hips := Transform3D(lean * hip_basis,
			lower.position - Vector3(0.0, drop, 0.0))
	var seat: Vector3 = _skater.seat_on_ice(hips)
	if plant > 0.0:
		hips.origin += seat * plant
	var waist := Transform3D(waist_basis, Vector3.ZERO)

	# Relative to the hips, the trunk folds about THEIR axis by the share of the
	# lean they have not already taken, then twists; what is left of the frame's
	# pitch and roll (the reach toward the hand, the recoil) is relative to where
	# the shoulders point, so it goes on after the twist. The leading inverse
	# takes it into the waist's frame, which is the spine's parent.
	var spine_basis: Basis = Basis(Vector3.UP, -waist_yaw) \
			* Basis(Vector3.RIGHT, fold - hip.x) \
			* Basis(Vector3.UP, twist) \
			* Basis.from_euler(Vector3(trunk.x - fold, 0.0, trunk.z))
	# The trunk leans by its own tilt, not the hips': the hips' lean undone and
	# the trunk's put on, about skeleton-space axes, carried into the waist's
	# frame. With no trail this is the trunk handing back the share of the lean
	# it does not keep.
	var under: Basis = hip_basis * waist_basis
	if theta > 1e-4 or trunk_theta > 1e-4:
		spine_basis = under.inverse() * (lean.inverse() * trunk_lean) * under * spine_basis
	var spine := Transform3D(spine_basis, Vector3.ZERO)

	# The neck takes back part of what the trunk leans, about its own base.
	var neck := Transform3D.IDENTITY
	if trunk_theta > 1e-4:
		var spine_world: Basis = lean * under * spine_basis
		var neck_axis: Vector3 = spine_world.inverse() * trunk_axis
		var base := Vector3(0.0, shoulder_y, 0.0)
		var counter := Basis(neck_axis.normalized(), -_skater.head_level_share * trunk_theta)
		neck = Transform3D(counter, base - counter * base)

	if hips.is_equal_approx(_hips_pose) and waist.is_equal_approx(_waist_pose) \
			and spine.is_equal_approx(_spine_pose) and neck.is_equal_approx(_neck_pose):
		return false
	_hips_pose = hips
	_waist_pose = waist
	_spine_pose = spine
	_neck_pose = neck
	_skeleton.set_bone_pose(SkaterBodySkeleton.HIPS_BONE, hips)
	_skeleton.set_bone_pose(SkaterBodySkeleton.WAIST_BONE, waist)
	_skeleton.set_bone_pose(SkaterBodySkeleton.SPINE_BONE, spine)
	_skeleton.set_bone_pose(SkaterBodySkeleton.NECK_BONE, neck)
	_moved_unseen = true
	return true


# Whether any of the four bones moved since the last call.
func take_moved() -> bool:
	var moved: bool = _moved_unseen
	_moved_unseen = false
	return moved
