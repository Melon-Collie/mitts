class_name SkaterSpineRig
extends RefCounted

# The three bones that join the body into one figure: HIPS, the frame the legs
# hang from; WAIST, the pelvis the shorts ride; and SPINE, the trunk frame the
# shell and the arm roots hang from. None carries vertices.
#
# All three are built from the two gameplay-side frames, read and never written:
# `LowerBody` carries the hip yaw and pitch the gait and pose coordinator sum,
# `UpperBody` the facing twist and lean the blade hangs from. What this adds is
# the ORDER a body is built in. The trunk folds forward about the hips' own
# axis and then twists on top of the fold, so turning the shoulders toward the
# stick turns a leaned torso about its spine rather than tipping it sideways
# off the hips; and the shoulders cannot turn further from the hips than a
# spine can, so past that the hips come round with them.

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


func setup(skater: Skater) -> void:
	_skater = skater


func build(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	update()


# Re-derives both bones from the two frames. Returns true when either moved, so
# the arm IK knows its roots did even if no hand marker moved.
func update() -> bool:
	var lower: Node3D = _skater.lower_body
	var upper: Node3D = _skater.upper_body
	var hip: Vector3 = lower.rotation
	var trunk: Vector3 = upper.rotation
	var fold: float = _skater.trunk_fold()
	var twist: float = clampf(angle_difference(hip.y, trunk.y), -TWIST_LIMIT, TWIST_LIMIT)
	var hips := Transform3D(Basis.from_euler(Vector3(hip.x, trunk.y - twist, 0.0)),
			lower.position)
	var waist_yaw: float = twist * WAIST_TWIST_SHARE
	var waist := Transform3D(Basis(Vector3.UP, waist_yaw), Vector3.ZERO)
	# Relative to the hips, the trunk folds about THEIR axis by the share of the
	# lean they have not already taken, then twists; what is left of the frame's
	# pitch and roll (the reach toward the hand, the recoil) is relative to where
	# the shoulders point, so it goes on after the twist. The leading inverse
	# takes it into the waist's frame, which is the spine's parent.
	var spine := Transform3D(Basis(Vector3.UP, -waist_yaw)
			* Basis(Vector3.RIGHT, fold - hip.x)
			* Basis(Vector3.UP, twist)
			* Basis.from_euler(Vector3(trunk.x - fold, 0.0, trunk.z)), Vector3.ZERO)
	if hips.is_equal_approx(_hips_pose) and waist.is_equal_approx(_waist_pose) \
			and spine.is_equal_approx(_spine_pose):
		return false
	_hips_pose = hips
	_waist_pose = waist
	_spine_pose = spine
	_skeleton.set_bone_pose(SkaterBodySkeleton.HIPS_BONE, hips)
	_skeleton.set_bone_pose(SkaterBodySkeleton.WAIST_BONE, waist)
	_skeleton.set_bone_pose(SkaterBodySkeleton.SPINE_BONE, spine)
	return true
