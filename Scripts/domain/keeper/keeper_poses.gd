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
const READY_PELVIS := Vector3(0.0, 0.83, 0.12)
const READY_TOE_OUT_RAD: float = 0.25
# The blade sits to the glove side of centre: the lie carries the grip 35 cm
# out from the heel, and centred on the five-hole it would hold the blocker out
# by the post instead of over the pad's outer edge.
# The glove's place on the body, in the chest's frame, the same up or down: just
# outside the chest's width with the elbow a little out from the body, held
# out in front a little above the chest's centre. It moves out from here to
# make a save; it does not drop when he does.
const GLOVE_FROM_CHEST := Vector3(-0.40, 0.07, -0.48)
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
# With a pad standing on the blocker side, the blade sits out ahead of its
# face so the paddle rises in front of it.
const HALF_BUTTERFLY_BLADE := Vector3(-0.08, 0.0, -0.56)
const EXTENSION_BLADE := Vector3(-0.08, 0.0, -0.45)
# Low enough that the extended leg lies within 30° of straight, high enough that
# its knee still lands near enough the middle for the thigh rise to meet the
# paddle along the ice.
const EXTENSION_PELVIS_HEIGHT_M: float = 0.38
const RVH_OFF_PAD_RISE_RAD: float = deg_to_rad(30.0)
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
	p.glove_from_chest = false
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
	p.lumbar_rot = Vector3(-0.19, 0.0, 0.0)
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
	# The loaded leg stands its pad up: knee over the skate, face square to the
	# shooter, its inner edge closing toward the pad that is down.
	var leg: KeeperPose.Leg = p.legs[up]
	leg.ankle = Vector3(sx * 0.36, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.16)
	leg.knee_pole = Vector3(sx * 0.8, 0.0, -1.0)
	leg.shin_front = _FORWARD
	# Weight down onto the knee that is down, the shoulders near level and
	# leaning as far as the butterfly's.
	p.pelvis = Vector3(side * 0.04, 0.60, 0.08)
	p.pelvis_rot = Vector3(-0.17, 0.0, -side * 0.10)
	p.lumbar_rot = Vector3(-0.10, 0.0, 0.0)
	_ready_hands(p, 0.0)
	if up == 1:
		# The pad standing on the blocker side: the blade sits out ahead of its
		# face, so the paddle rises in front of it rather than through it.
		p.blade_center = HALF_BUTTERFLY_BLADE
	else:
		# The blocker side is down: the stick lies as the butterfly's does, the
		# blade a little further out over a pad whose knee sits nearer the middle.
		p.blade_center = BUTTERFLY_BLADE + Vector3(0.0, 0.0, -0.08)
		p.stick_tilt = BUTTERFLY_STICK_TILT_RAD


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
	p.glove_hand = GLOVE_FROM_CHEST
	p.glove_from_chest = true
	p.blocker_elbow_pole = Vector3(-0.2, -1.0, 0.4)
	p.glove_fingers = Vector3(-0.25, 1.0, -0.1)
	p.glove_palm = _FORWARD
	p.blade_center = BUTTERFLY_BLADE
	p.blade_yaw = 0.0
	p.stick_tilt = BUTTERFLY_STICK_TILT_RAD
	p.blocker_face = Vector3(0.30, 0.0, -1.0)


# The butterfly with one pad driven out along the ice toward the post on `side`:
# hip, knee and ankle in one line out from the hip, square to the shooter, as
# straight as the dropped hips let a leg lie on the ice; the other knee stays
# down under him. The trunk rolls over the push and the neck brings the eyes
# back toward level.
static func butterfly_extension(p: KeeperPose, side: float) -> void:
	butterfly(p)
	var leg: KeeperPose.Leg = p.legs[0 if side < 0.0 else 1]
	p.pelvis.y = EXTENSION_PELVIS_HEIGHT_M
	var hip := Vector3(side * KeeperAnatomy.HIP_HALF_SPACING_M, KeeperAnatomy.PAD_WIDTH_M * 0.5,
			p.pelvis.z)
	var out := Vector3(side, 0.0, 0.0)
	leg.knee = hip + out * KeeperAnatomy.THIGH_M
	leg.ankle = leg.knee + out * KeeperAnatomy.SHIN_M
	p.pelvis_rot.z = -side * 0.12
	p.lumbar_rot.z = -side * 0.06
	p.chest_rot.z = -side * 0.04
	p.neck_rot.z = side * 0.10
	# The extended leg lies across the paddle's path: the blade goes out ahead.
	p.blade_center = EXTENSION_BLADE


# Standing, one leg kicked out along the ice to the side: the skate and the
# pad's boot take the low corner, the stick goes with them.
static func kick(p: KeeperPose, side: float) -> void:
	ready(p)
	var i: int = 0 if side < 0.0 else 1
	var leg: KeeperPose.Leg = p.legs[i]
	leg.ankle = Vector3(side * 0.56, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.10)
	leg.knee_pole = Vector3(0.0, 0.3, -1.0)
	# The leg turns out from the hip, the foot furthest: the skate's instep
	# faces the shooter.
	leg.toe = Vector3(side * sin(deg_to_rad(60.0)), 0.0, -cos(deg_to_rad(60.0)))
	leg.shin_front = Vector3(side * sin(deg_to_rad(30.0)), 0.0, -cos(deg_to_rad(30.0)))
	# The support skate comes in under him and takes his weight; the hips stay
	# near square, the head over the kick. The blade slides with the kick to
	# meet its pad along the ice.
	p.pelvis_rot.z = -side * 0.05
	if side < 0.0:
		# The paddle crosses in front of the blocker pad: that skate stays wide
		# and the blade goes out ahead of it.
		p.legs[1].ankle.x = 0.24
		p.pelvis += Vector3(-0.03, -0.02, 0.0)
		p.blade_center = READY_BLADE + Vector3(-0.15, 0.0, -0.14)
		p.stick_tilt = READY_STICK_TILT_RAD + deg_to_rad(10.0)
	else:
		# The lie carries the grip out past the kick: the hips go with it to keep
		# it in the blocker arm's reach, over a glove skate drawn in under them.
		p.legs[0].ankle.x = -0.18
		p.pelvis += Vector3(0.12, -0.03, 0.0)
		p.blade_center = READY_BLADE + Vector3(0.19, 0.0, -0.12)
		p.stick_tilt = READY_STICK_TILT_RAD + deg_to_rad(12.0)


# Reverse-VH on the post at `side`, compact and sealed to the iron: sat back on
# the post leg's calf, its pad flat along the goal line from the knee out to
# the toe hooked on the post; the other pad standing. Upright and leaning into
# the post, the hands in close and the blade on the ice in front of the pads.
# The brain puts KeeperGear.post_contact on the post.
static func rvh(p: KeeperPose, side: float) -> void:
	butterfly(p)
	var post: int = 0 if side < 0.0 else 1
	var shin_y: float = KeeperAnatomy.PAD_WIDTH_M * 0.5
	var leg: KeeperPose.Leg = p.legs[post]
	leg.knee = Vector3(-side * 0.05, shin_y, 0.0)
	leg.ankle = Vector3(side * 0.42, shin_y, 0.05)
	# The off-post pad stands on its skate toward the middle, loaded to push, its
	# face square to the shooter and laid back RVH_OFF_PAD_RISE_RAD off the ice.
	var off: KeeperPose.Leg = p.legs[1 - post]
	var sx: float = -side
	_ready_leg(off, sx)
	off.knee_pinned = true
	off.knee = Vector3(sx * 0.30, KeeperAnatomy.ANKLE_ON_SKATES_M
			+ KeeperAnatomy.SHIN_M * sin(RVH_OFF_PAD_RISE_RAD), -0.25)
	off.ankle = Vector3(sx * 0.75, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.20)
	off.shin_front = _FORWARD
	p.pelvis = Vector3(side * 0.12, 0.55, 0.10)
	p.pelvis_rot = Vector3(-0.10, -side * 0.25, -side * 0.12)
	p.lumbar_rot = Vector3(-0.08, 0.0, -side * 0.12)
	p.chest_rot = Vector3(0.0, 0.0, -side * 0.08)
	p.neck_rot = Vector3(0.20, 0.0, side * 0.06)
	if side < 0.0:
		# Low by the post, over the pad: the seal between pad and body. The glove is
		# turned down, palm out, so the forearm reaching down to it goes into its
		# cuff rather than through its fingers.
		p.glove_hand = Vector3(-0.40, 0.42, -0.10)
		p.glove_from_chest = false
		p.glove_fingers = Vector3(0.0, -1.0, 0.0)
		# The paddle rises in front of the standing blocker-side pad.
		p.blade_center = Vector3(-0.28, 0.0, -0.40)
		p.blade_yaw = deg_to_rad(-15.0)
		p.stick_tilt = deg_to_rad(18.0)
	else:
		# In front at the waist, toward the middle.
		p.glove_hand = Vector3(-0.30, -0.10, -0.38)
		p.blade_center = Vector3(-0.15, 0.0, -0.30)


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


# The ready stance's hands: the glove at its place on the chest and the stick
# out in front, its paddle tilted `extra_tilt` (radians) further back for a
# keeper whose hips sit lower than the stance's, which lowers the blocker with
# them.
static func _ready_hands(p: KeeperPose, extra_tilt: float) -> void:
	p.glove_hand = GLOVE_FROM_CHEST
	p.glove_from_chest = true
	p.glove_fingers = Vector3(-0.25, 1.0, -0.15)
	p.glove_palm = _FORWARD
	p.blade_center = READY_BLADE
	p.blade_yaw = 0.0
	p.stick_tilt = READY_STICK_TILT_RAD + extra_tilt
	p.blocker_face = Vector3(0.30, 0.0, -1.0)
