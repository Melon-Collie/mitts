class_name KeeperPoses
extends RefCounted

# The stances a keeper is taught, each written as where the body goes: feet on
# the ice, knees down or loaded, hands out in front, the stick's blade on the
# ice ahead of the five-hole. KeeperSkeleton solves the joints. Keeper space,
# left-catching (KeeperAnatomy); `side` is −1 toward the glove side, +1 toward
# the blocker side.
#
# Every function fills a caller-owned pose and leaves nothing else changed, so
# a stance can be layered: start from one, then move a limb.

const _FORWARD := Vector3(0.0, 0.0, -1.0)

# The taught stance: skates a little wider than the shoulders, toes turned out,
# knees bent and in so the pads stand on their inside edges, hips back, chest
# over the knees, hands out in front, the blade a foot ahead of the skates
# across the five-hole.
const READY_SKATE_HALF_SPACING_M: float = 0.31
const READY_KNEE_IN_M: float = 0.11
const READY_PELVIS := Vector3(0.0, 0.86, 0.12)
const READY_TOE_OUT_RAD: float = 0.25
# The blade sits to the glove side of centre: the lie carries the grip 35 cm
# out from the heel, and centred on the five-hole it would hold the blocker out
# by the post instead of over the pad's outer edge.
const READY_BLADE := Vector3(-0.08, 0.0, -0.40)
# The paddle's tilt back toward him. The lie leans it toward the blocker side
# on its own; a paddle near upright holds the grip out in front of the pads,
# where a tilt toward the hip would tuck the blocker behind them.
const READY_STICK_TILT_RAD: float = deg_to_rad(8.0)

# The butterfly: knees together on the ice, shins flared out behind them with
# the pads' faces to the shooter, hips over the knees and the trunk tall.
# Wide enough that the thigh rises, carried on along the ice past the knees,
# meet under him, overlapping by BUTTERFLY_RISE_OVERLAP_M rather than lying
# across each other.
const BUTTERFLY_RISE_OVERLAP_M: float = 0.06
const BUTTERFLY_KNEE_HALF_SPACING_M: float = KeeperAnatomy.PAD_TOP_ABOVE_KNEE_M \
		- BUTTERFLY_RISE_OVERLAP_M * 0.5
const BUTTERFLY_FLARE_RAD: float = deg_to_rad(18.0)
const BUTTERFLY_KNEE_FORWARD_M: float = -0.04
const BUTTERFLY_HIP_BEHIND_KNEE_M: float = 0.14
# The blade sits a few inches ahead of the pads, to the glove side of centre
# as in the ready stance, and the paddle stands up from it enough to hold the
# blocker beside the hip above the pad.
const BUTTERFLY_BLADE := Vector3(-0.08, 0.0, -0.29)
const BUTTERFLY_STICK_TILT_RAD: float = deg_to_rad(28.0)


static func upright(p: KeeperPose) -> void:
	_reset_trunk(p)
	p.pelvis = Vector3(0.0, KeeperAnatomy.HIP_HEIGHT_M + KeeperAnatomy.SKATE_LIFT_M, 0.0)
	for i: int in 2:
		var sx: float = _side_x(i)
		var leg: KeeperPose.Leg = p.legs[i]
		leg.ankle = Vector3(sx * KeeperAnatomy.HIP_HALF_SPACING_M, KeeperAnatomy.ANKLE_ON_SKATES_M, 0.0)
		leg.knee_pinned = false
		leg.knee_pole = _FORWARD
		leg.thigh_front = _FORWARD
		leg.shin_front = _FORWARD
		leg.foot_mode = KeeperPose.FootMode.FLAT
		leg.toe = _FORWARD
	p.glove_hand = Vector3(-0.38, 0.95, -0.15)
	p.glove_fingers = Vector3(0.0, -1.0, 0.0)
	p.glove_palm = Vector3(1.0, 0.0, 0.0)
	p.blade_center = Vector3(0.10, 0.0, -0.45)
	p.blade_yaw = 0.0
	p.stick_tilt = 0.0
	p.blocker_face = Vector3(1.0, 0.0, -0.3)


static func ready(p: KeeperPose) -> void:
	_reset_trunk(p)
	p.pelvis = READY_PELVIS
	p.pelvis_rot = Vector3(-0.42, 0.0, 0.0)
	p.lumbar_rot = Vector3(-0.15, 0.0, 0.0)
	p.chest_rot = Vector3(0.05, 0.0, 0.0)
	p.neck_rot = Vector3(0.30, 0.0, 0.0)
	p.head_rot = Vector3(0.12, 0.0, 0.0)
	for i: int in 2:
		_ready_leg(p.legs[i], _side_x(i))
	_ready_hands(p, 0.0)


# One leg down in the butterfly (`side`), the other loaded on its skate.
static func half_butterfly(p: KeeperPose, side: float) -> void:
	butterfly(p)
	var up: int = 1 if side < 0.0 else 0
	var sx: float = _side_x(up)
	_ready_leg(p.legs[up], sx)
	# The loaded leg's skate sits under the hip's side with the knee forward of it.
	var leg: KeeperPose.Leg = p.legs[up]
	leg.ankle = Vector3(sx * 0.40, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.24)
	leg.knee_pole = Vector3(-sx * 0.2, 0.0, -1.0)
	p.pelvis = Vector3(-side * 0.04, 0.63, 0.08)
	p.pelvis_rot = Vector3(-0.18, 0.0, -side * 0.30)
	p.lumbar_rot = Vector3(-0.08, 0.0, 0.0)
	_ready_hands(p, 0.12)


static func butterfly(p: KeeperPose) -> void:
	_reset_trunk(p)
	var shin_y: float = KeeperAnatomy.PAD_WIDTH_M * 0.5
	var knee_z: float = BUTTERFLY_KNEE_FORWARD_M
	var hip_z: float = knee_z + BUTTERFLY_HIP_BEHIND_KNEE_M
	var dy: float = sqrt(maxf(KeeperAnatomy.THIGH_M * KeeperAnatomy.THIGH_M
			- BUTTERFLY_HIP_BEHIND_KNEE_M * BUTTERFLY_HIP_BEHIND_KNEE_M, 0.0))
	p.pelvis = Vector3(0.0, shin_y + dy, hip_z)
	# Tall, but leaning his shoulders on over his knees.
	p.pelvis_rot = Vector3(-0.17, 0.0, 0.0)
	p.lumbar_rot = Vector3(-0.10, 0.0, 0.0)
	p.chest_rot = Vector3(-0.03, 0.0, 0.0)
	p.neck_rot = Vector3(0.20, 0.0, 0.0)
	for i: int in 2:
		_butterfly_leg(p.legs[i], _side_x(i), shin_y, knee_z, BUTTERFLY_FLARE_RAD)
	p.glove_hand = Vector3(-0.46, 0.75, -0.38)
	p.blocker_elbow_pole = Vector3(-0.2, -1.0, 0.4)
	p.glove_fingers = Vector3(-0.25, 1.0, -0.1)
	p.glove_palm = _FORWARD
	p.blade_center = BUTTERFLY_BLADE
	p.blade_yaw = 0.0
	p.stick_tilt = BUTTERFLY_STICK_TILT_RAD
	p.blocker_face = Vector3(0.30, 0.0, -1.0)


# The butterfly with one pad pushed out along the ice toward the post on `side`:
# the leg straightens at the knee and the hip opens, the pad's face still to
# the shooter and its toe on the ice.
static func butterfly_extension(p: KeeperPose, side: float) -> void:
	butterfly(p)
	var i: int = 0 if side < 0.0 else 1
	var leg: KeeperPose.Leg = p.legs[i]
	var shin_y: float = KeeperAnatomy.PAD_WIDTH_M * 0.5
	leg.knee = Vector3(side * 0.40, shin_y, -0.02)
	leg.ankle = Vector3(side * 0.88, shin_y, 0.04)
	p.pelvis += Vector3(side * 0.10, -0.06, 0.0)
	p.pelvis_rot.z = -side * 0.18
	p.chest_rot.z = side * 0.10


# Standing, one leg kicked out along the ice to the side: the skate and the
# pad's boot take the low corner.
static func kick(p: KeeperPose, side: float) -> void:
	ready(p)
	var i: int = 0 if side < 0.0 else 1
	var leg: KeeperPose.Leg = p.legs[i]
	leg.ankle = Vector3(side * 0.64, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.10)
	leg.knee_pole = Vector3(0.0, 0.3, -1.0)
	leg.toe = Vector3(side * 0.3, 0.0, -1.0)
	p.pelvis += Vector3(-side * 0.06, -0.06, 0.0)
	p.pelvis_rot.z = side * 0.12


# Reverse-VH on the post at `side`: the post pad flat along the ice from the
# post toward the middle, its toe sealed to the iron, the other leg's knee up
# with its skate on the ice. The keeper's origin is where the brain places him;
# the post pad's toe lands `side * 0.60` from it.
static func rvh(p: KeeperPose, side: float) -> void:
	butterfly(p)
	var post: int = 0 if side < 0.0 else 1
	var shin_y: float = KeeperAnatomy.PAD_WIDTH_M * 0.5
	var leg: KeeperPose.Leg = p.legs[post]
	leg.knee = Vector3(side * 0.12, shin_y, -0.02)
	leg.ankle = Vector3(side * 0.60, shin_y, -0.06)
	leg.shin_front = Vector3(0.0, 0.25, -1.0)
	var other: int = 1 - post
	var sx: float = _side_x(other)
	_ready_leg(p.legs[other], sx)
	p.legs[other].ankle = Vector3(sx * 0.34, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.20)
	p.legs[other].knee_pole = Vector3(sx * 0.1, 0.0, -1.0)
	p.pelvis = Vector3(side * 0.06, 0.62, 0.10)
	p.pelvis_rot = Vector3(-0.12, side * 0.20, -side * 0.10)
	p.chest_rot = Vector3(0.0, 0.0, side * 0.12)
	if side < 0.0:
		p.glove_hand = Vector3(-0.42, 0.95, -0.15)


# VH on the post at `side`: the post leg standing with its pad upright against
# the iron, the other pad down flat across the crease.
static func vh(p: KeeperPose, side: float) -> void:
	butterfly(p)
	var post: int = 0 if side < 0.0 else 1
	var sx: float = _side_x(post)
	_ready_leg(p.legs[post], sx)
	var leg: KeeperPose.Leg = p.legs[post]
	leg.ankle = Vector3(sx * 0.30, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.06)
	leg.knee_pole = Vector3(-sx * 0.3, 0.0, -1.0)
	leg.shin_front = Vector3(sx * 0.6, 0.0, -1.0)
	p.pelvis = Vector3(side * 0.05, 0.72, 0.06)
	p.pelvis_rot = Vector3(-0.20, 0.0, -side * 0.25)
	_ready_hands(p, 0.15)


# Overlap at the post on `side`: standing in the ready stance with the post
# pad's outside edge against the iron, a mobile stance for a shot still live
# from a sharp angle.
static func overlap(p: KeeperPose, side: float) -> void:
	ready(p)
	var i: int = 0 if side < 0.0 else 1
	p.legs[i].shin_front = Vector3(side * 0.35, 0.0, -1.0)
	p.legs[i].toe = Vector3(side * 0.5, 0.0, -1.0)


static func _side_x(leg: int) -> float:
	return -1.0 if leg == 0 else 1.0


static func _reset_trunk(p: KeeperPose) -> void:
	p.pelvis_rot = Vector3.ZERO
	p.lumbar_rot = Vector3.ZERO
	p.chest_rot = Vector3.ZERO
	p.neck_rot = Vector3.ZERO
	p.head_rot = Vector3.ZERO
	p.glove_elbow_pole = Vector3(-0.6, -1.0, 0.3)
	p.blocker_elbow_pole = Vector3(0.6, -1.0, 0.3)


static func _ready_leg(leg: KeeperPose.Leg, sx: float) -> void:
	leg.ankle = Vector3(sx * READY_SKATE_HALF_SPACING_M, KeeperAnatomy.ANKLE_ON_SKATES_M, 0.0)
	leg.knee_pinned = false
	# Knees in and forward: the pole aims each knee toward the middle.
	leg.knee_pole = Vector3(-sx * READY_KNEE_IN_M, 0.0, -1.0)
	leg.thigh_front = _FORWARD
	leg.shin_front = Vector3(-sx * 0.15, 0.0, -1.0)
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = Vector3(sx * sin(READY_TOE_OUT_RAD), 0.0, -cos(READY_TOE_OUT_RAD))


static func _butterfly_leg(leg: KeeperPose.Leg, sx: float, shin_y: float, knee_z: float,
		flare: float) -> void:
	leg.knee_pinned = true
	leg.knee = Vector3(sx * BUTTERFLY_KNEE_HALF_SPACING_M, shin_y, knee_z)
	var dir := Vector3(sx * cos(flare), 0.0, sin(flare))
	leg.ankle = leg.knee + dir * KeeperAnatomy.SHIN_M
	leg.thigh_front = _FORWARD
	leg.shin_front = _FORWARD
	leg.foot_mode = KeeperPose.FootMode.ALONG_SHIN
	# The foot stays square to the shin, toe toward the shooter under the pad's
	# boot, so the skate lies on its side behind the pad's end rather than
	# reaching on out toward the post.
	leg.flex = 0.0


# Hands out in front of the body at the pad tops; `drop` lowers them for a
# keeper whose hips are lower than the stance's.
static func _ready_hands(p: KeeperPose, drop: float) -> void:
	p.glove_hand = Vector3(-0.38, 0.93 - drop, -0.50)
	p.glove_fingers = Vector3(-0.25, 1.0, -0.15)
	p.glove_palm = _FORWARD
	p.blade_center = READY_BLADE
	p.blade_yaw = 0.0
	p.stick_tilt = READY_STICK_TILT_RAD + drop
	p.blocker_face = Vector3(0.30, 0.0, -1.0)
