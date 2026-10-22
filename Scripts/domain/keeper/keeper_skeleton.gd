class_name KeeperSkeleton
extends RefCounted

# The keeper's bones in keeper space, solved from a KeeperPose. Pure: no nodes,
# so the host's collision geometry, the client's rebuild and the planner's
# coverage all solve the same body from the same numbers.
#
# Every bone's origin is its proximal joint. Limb bones hang along −Y (+Y points
# back up the bone toward its parent), −Z is the front of the segment — the
# pad's face on the shin, the palm on the glove hand — and X completes a
# right-handed basis. The trunk bones and the pelvis are upright at rest.
#
# `pose` fills the transforms in place, so a skeleton solved every tick
# allocates nothing.

enum Bone {
	PELVIS, LUMBAR, CHEST, NECK, HEAD,
	THIGH_G, SHIN_G, FOOT_G,
	THIGH_B, SHIN_B, FOOT_B,
	UPPER_ARM_G, FOREARM_G, HAND_G,
	UPPER_ARM_B, FOREARM_B, HAND_B,
}
const BONE_COUNT: int = 17
const _REFLECT := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3.BACK), Vector3.ZERO)

const THIGH: Array[int] = [Bone.THIGH_G, Bone.THIGH_B]
const SHIN: Array[int] = [Bone.SHIN_G, Bone.SHIN_B]
const FOOT: Array[int] = [Bone.FOOT_G, Bone.FOOT_B]

var xf: Array[Transform3D] = []
# A right-catcher: the stances are authored left-catching, and his body is
# theirs reflected across his centre line once solved, the glove on +X. The
# glove side and the blocker side keep their meaning, so a stance's `side`
# is his own; `world_side` turns it into keeper space's.
var mirrored: bool = false

# The stick, rigid: the heel where paddle meets blade, the paddle's direction up
# from it, the blade's direction along the ice from it, and the blade's face.
var stick_heel: Vector3 = Vector3.ZERO
var stick_paddle_dir: Vector3 = Vector3.UP
var stick_blade_dir: Vector3 = Vector3.LEFT
var stick_face: Vector3 = Vector3.FORWARD
var grip: Vector3 = Vector3.ZERO


func _init() -> void:
	xf.resize(BONE_COUNT)
	for i: int in BONE_COUNT:
		xf[i] = Transform3D.IDENTITY


func pose(p: KeeperPose) -> void:
	var pelvis := Transform3D(Basis.from_euler(p.pelvis_rot), p.pelvis)
	xf[Bone.PELVIS] = pelvis
	var lumbar: Transform3D = pelvis * Transform3D(Basis.from_euler(p.lumbar_rot),
			Vector3(0.0, KeeperAnatomy.LUMBAR_ABOVE_PELVIS_M, 0.0))
	xf[Bone.LUMBAR] = lumbar
	var chest: Transform3D = lumbar * Transform3D(Basis.from_euler(p.chest_rot),
			Vector3(0.0, KeeperAnatomy.CHEST_ABOVE_LUMBAR_M, 0.0))
	xf[Bone.CHEST] = chest
	var neck: Transform3D = chest * Transform3D(Basis.from_euler(p.neck_rot),
			Vector3(0.0, KeeperAnatomy.NECK_ABOVE_CHEST_M, 0.0))
	xf[Bone.NECK] = neck
	xf[Bone.HEAD] = neck * Transform3D(Basis.from_euler(p.head_rot),
			Vector3(0.0, KeeperAnatomy.HEAD_ABOVE_NECK_M, 0.0))
	for side: int in 2:
		var sign_x: float = -1.0 if side == 0 else 1.0
		_pose_leg(side, pelvis * Vector3(sign_x * KeeperAnatomy.HIP_HALF_SPACING_M, 0.0, 0.0),
				p.legs[side])
	_pose_stick(p)
	var shoulder_y: float = KeeperAnatomy.SHOULDER_ABOVE_CHEST_M
	var glove_shoulder: Vector3 = chest * Vector3(
			-KeeperAnatomy.SHOULDER_HALF_SPACING_M, shoulder_y, 0.0)
	var blocker_shoulder: Vector3 = chest * Vector3(
			KeeperAnatomy.SHOULDER_HALF_SPACING_M, shoulder_y, 0.0)
	var fwd: Vector3 = -chest.basis.z
	var glove_at: Vector3 = chest * p.glove_hand if p.glove_from_chest else p.glove_hand
	_pose_arm(Bone.UPPER_ARM_G, glove_shoulder, glove_at, p.glove_elbow_pole, fwd)
	xf[Bone.HAND_G] = Transform3D(_limb_basis(-p.glove_fingers, p.glove_palm), glove_at)
	# The blocker's board stands upright on the back of the hand whatever the
	# stick's lean, face to the shooter. The fist holds the stick, so the arm
	# reaches the wrist on the back of it rather than the stick itself.
	xf[Bone.HAND_B] = Transform3D(_limb_basis(Vector3.UP, p.blocker_face), grip)
	_pose_arm(Bone.UPPER_ARM_B, blocker_shoulder, xf[Bone.HAND_B] * KeeperAnatomy.BLOCKER_WRIST,
			p.blocker_elbow_pole, fwd)
	if mirrored:
		_mirror()


# Keeper space's x for a stance's `side` (−1 the glove side, +1 the blocker
# side).
func world_side(side: float) -> float:
	return -side if mirrored else side


# Reflects the solved body across x = 0. Each bone frame is reflected on both
# sides (still a rotation, its own x turned over), so a box on it is the
# reflected box: boxes are symmetric about their own axes. The drawn gear,
# which is not, is turned over on its own x where it is drawn (KeeperGearView).
func _mirror() -> void:
	for i: int in BONE_COUNT:
		xf[i] = _REFLECT * xf[i] * _REFLECT
	var flip := Vector3(-1.0, 1.0, 1.0)
	stick_heel *= flip
	stick_paddle_dir *= flip
	stick_blade_dir *= flip
	stick_face *= flip
	grip *= flip


# A limb bone's basis: +Y along `up_bone` (toward the parent joint), −Z the
# component of `front` square to it.
static func _limb_basis(up_bone: Vector3, front: Vector3) -> Basis:
	var y: Vector3 = up_bone.normalized()
	var f: Vector3 = front - y * front.dot(y)
	if f.length_squared() < 1e-8:
		f = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
		if f.length_squared() < 1e-8:
			f = Vector3.UP - y * Vector3.UP.dot(y)
	var z: Vector3 = -f.normalized()
	return Basis(y.cross(z), y, z)


func _pose_leg(side: int, hip: Vector3, leg: KeeperPose.Leg) -> void:
	var thigh_len: float = KeeperAnatomy.THIGH_M
	var shin_len: float = KeeperAnatomy.SHIN_M
	var knee: Vector3
	var ankle: Vector3
	if leg.knee_pinned:
		knee = toward_at_height(hip, leg.knee, thigh_len)
		ankle = toward_at_height(knee, leg.ankle, shin_len)
	else:
		knee = TwoBoneIK.solve_elbow(hip, leg.ankle, thigh_len, shin_len, leg.knee_pole)
		ankle = knee + (leg.ankle - knee).normalized() * shin_len
	xf[THIGH[side]] = Transform3D(_limb_basis(hip - knee, leg.thigh_front), hip)
	var shin_basis: Basis = _limb_basis(knee - ankle, leg.shin_front)
	xf[SHIN[side]] = Transform3D(shin_basis, knee)
	var foot_basis: Basis
	if leg.foot_mode == KeeperPose.FootMode.FLAT:
		var toe := Vector3(leg.toe.x, 0.0, leg.toe.z)
		if toe.length_squared() < 1e-8:
			toe = Vector3.FORWARD
		var z: Vector3 = -toe.normalized()
		foot_basis = Basis(Vector3.UP.cross(z), Vector3.UP, z)
	else:
		foot_basis = shin_basis * Basis(Vector3.RIGHT, leg.flex)
	xf[FOOT[side]] = Transform3D(foot_basis, ankle)


# A segment of `length` from `from` toward `target` that ends at the target's
# height, turning only in plan: a kneeling knee stays on the ice wherever the
# hips are. Straight at the target when the height is out of reach.
static func toward_at_height(from: Vector3, target: Vector3, length: float) -> Vector3:
	var dy: float = target.y - from.y
	var plan := Vector2(target.x - from.x, target.z - from.z)
	if absf(dy) >= length or plan.length_squared() < 1e-10:
		return from + (target - from).normalized() * length
	var reach: Vector2 = plan.normalized() * sqrt(length * length - dy * dy)
	return Vector3(from.x + reach.x, target.y, from.z + reach.y)


func _pose_arm(upper: int, shoulder: Vector3, hand: Vector3, pole: Vector3,
		fwd: Vector3) -> void:
	var elbow: Vector3 = TwoBoneIK.solve_elbow(shoulder, hand,
			KeeperAnatomy.UPPER_ARM_M, KeeperAnatomy.FOREARM_M, pole)
	xf[upper] = Transform3D(_limb_basis(shoulder - elbow, fwd), shoulder)
	var wrist: Vector3 = elbow + (hand - elbow).normalized() * KeeperAnatomy.FOREARM_M
	xf[upper + 1] = Transform3D(_limb_basis(elbow - wrist, fwd), elbow)


# The stick is rigid and its blade lies flat, so the blade's centre, its yaw
# and the paddle's tilt decide it: the paddle rises from the heel at the lie's
# angle to the blade, in the blade's upright plane, then tilts back about the
# blade by `stick_tilt` — which opens the blade's face by the same angle. The
# grip is up the paddle from the heel.
func _pose_stick(p: KeeperPose) -> void:
	var blade := Vector3(-cos(p.blade_yaw), 0.0, -sin(p.blade_yaw))
	var lie: float = deg_to_rad(KeeperAnatomy.PADDLE_TO_BLADE_DEG)
	var upright: Vector3 = blade * cos(lie) + Vector3.UP * sin(lie)
	# Tilting back turns the paddle's top toward him: about the blade's axis,
	# signed so a positive tilt carries it toward +Z.
	var axis: Vector3 = blade if blade.cross(Vector3.UP).z >= 0.0 else -blade
	var paddle: Vector3 = upright.rotated(axis, p.stick_tilt)
	var heel: Vector3 = p.blade_center - blade * KeeperAnatomy.BLADE_LENGTH_M * 0.5
	heel.y = 0.0
	stick_heel = heel
	stick_paddle_dir = paddle
	stick_blade_dir = blade
	var face: Vector3 = blade.cross(paddle).normalized()
	stick_face = face if face.z <= 0.0 else -face
	grip = heel + paddle * KeeperAnatomy.GRIP_ALONG_STICK_M
