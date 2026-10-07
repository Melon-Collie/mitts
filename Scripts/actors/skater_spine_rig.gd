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
# it back down to the ice. The trunk keeps only part of the lean
# (Skater.trunk_lean_share) and the neck takes part of that back
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
	var twist: float = clampf(angle_difference(hip.y, trunk.y), -TWIST_LIMIT, TWIST_LIMIT)
	var hip_basis := Basis.from_euler(Vector3(hip.x, trunk.y - twist, 0.0))
	var waist_yaw: float = twist * WAIST_TWIST_SHARE
	var waist_basis := Basis(Vector3.UP, waist_yaw)

	# The lean, in skeleton space (the skater root's frame), as an axis and angle.
	var tilt: Vector2 = _skater.balance_tilt()
	var tilt3: Vector3 = _skater.global_transform.basis.inverse() * Vector3(tilt.x, 0.0, tilt.y)
	var theta: float = tilt3.length()
	var lean := Basis.IDENTITY
	var axis := Vector3.RIGHT
	if theta > 1e-4:
		axis = Vector3.UP.cross(tilt3 / theta)
		lean = Basis(axis, theta)
	# LowerBody already carries the lean's shift; the visible hips sit below it
	# by the part of the crouch the gameplay frame does not take
	# (Skater.set_skating_crouch_drop).
	var hips := Transform3D(lean * hip_basis,
			lower.position - Vector3(0.0, _skater.body_drop_below_frame(), 0.0))
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
	# The trunk hands back the part of the lean it does not keep: a rotation
	# about the same world axis, carried into the waist's frame.
	var under: Basis = hip_basis * waist_basis
	var trunk_back: float = -(1.0 - _skater.trunk_lean_share) * theta
	if theta > 1e-4:
		spine_basis = under.inverse() * Basis(axis, trunk_back) * under * spine_basis
	var spine := Transform3D(spine_basis, Vector3.ZERO)

	# The neck takes back part of what the trunk kept, about its own base.
	var neck := Transform3D.IDENTITY
	if theta > 1e-4:
		var spine_world: Basis = lean * under * spine_basis
		var neck_axis: Vector3 = spine_world.inverse() * axis
		var base := Vector3(0.0, _skater.shoulder.position.y, 0.0)
		var counter := Basis(neck_axis.normalized(),
				-_skater.head_level_share * _skater.trunk_lean_share * theta)
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
	return true
