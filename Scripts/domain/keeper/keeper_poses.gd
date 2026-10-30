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
# Far enough in that the blocker it puts the hand under sits against the hip
# rather than a puck's width off it.
const READY_BLADE := Vector3(-0.11, 0.0, -0.40)
# The paddle's tilt back toward him. The lie leans it toward the blocker side
# on its own; a paddle near upright holds the grip out in front of the pads,
# where a tilt toward the hip would tuck the blocker behind them.
const READY_STICK_TILT_RAD: float = deg_to_rad(8.0)

# The low ready: the ready stance sat down into a deep A, for a shot he may not
# have time to read (Carey Price's). Skates wide and straight ahead, a little
# behind his hips; knees driven in and forward, no closer than keeps the pads
# off each other; the pads' faces rolled in toward the five-hole, so their
# inside edges come down to the ice and nothing that meets them is turned on
# into the net; the chest folded on over the knees from the small of the back,
# the head up; the glove up and out in front, open to the shooter; the blade on
# the ice ahead of the five-hole on the glove side, the paddle stood nearly
# upright in front of the pads, not through them. Its knees are nearer the ice,
# so the drop into the butterfly from here is the shorter fall. The pads settle
# on the ice and their toes flex off it (KeeperGear); the knee and the skate are
# where the solve puts them.
const LOW_READY_SKATE_HALF_SPACING_M: float = 0.47
const LOW_READY_SKATE_BACK_M: float = 0.085
const LOW_READY_KNEE := Vector3(0.27, 0.40, -0.26)
const LOW_READY_PAD_FACE := Vector3(0.45, -0.10, -1.0)
const LOW_READY_PELVIS := Vector3(0.0, 0.65, 0.10)
const LOW_READY_BLADE := Vector3(-0.25, 0.0, -0.58)
const LOW_READY_STICK_TILT_RAD: float = deg_to_rad(5.0)
# Its glove, in the chest's frame as every stance holds it: up at the chest
# as the ready stance's, which with the chest folded on carries it out in front.
const LOW_READY_GLOVE_FROM_CHEST := Vector3(-0.42, 0.16, -0.46)

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
# face so the paddle rises in front of it, its heel up to the standing skate
# along the ice.
const HALF_BUTTERFLY_BLADE := Vector3(-0.04, 0.0, -0.52)
# The butterfly push's loaded skate: out wide where the butterfly flares it, a
# little ahead of him, its inside edge on the ice; its knee drawn in and
# forward off the ice, so the pad lies across from the knee to the skate,
# its face to the shooter tipped up just far enough for its bottom edge to
# rest on the ice rather than dig.
const BUTTERFLY_PUSH_SKATE := Vector3(0.55, KeeperAnatomy.ANKLE_ON_SKATES_M, -0.15)
const BUTTERFLY_PUSH_KNEE_POLE := Vector3(-0.8, 0.0, -1.0)
const BUTTERFLY_PUSH_PAD_FACE := Vector3(0.0, 0.3, -1.0)
const EXTENSION_BLADE := Vector3(-0.08, 0.0, -0.45)
# Low enough that the extended leg lies within 30° of straight, high enough that
# its knee still lands near enough the middle for the thigh rise to meet the
# paddle along the ice. He is still up on the knee that is down, so the
# extended thigh slopes from the hip to the ice and the five-hole opens above
# the blade, as a real extension's does.
const EXTENSION_PELVIS_HEIGHT_M: float = 0.38
const RVH_OFF_PAD_RISE_RAD: float = deg_to_rad(30.0)
const RVH_BLOCKER_SIDE_BLADE := Vector3(-0.35, 0.0, -0.50)
const RVH_BLOCKER_SIDE_BLADE_TURN_RAD: float = deg_to_rad(10.0)
const BUTTERFLY_KNEE_FORWARD_M: float = -0.04
const BUTTERFLY_HIP_BEHIND_KNEE_M: float = 0.14
# The blade sits a few inches ahead of the pads, to the glove side of centre
# as in the ready stance, and the paddle stands up from it enough to hold the
# blocker beside the hip above the pad, against it rather than a puck's width
# off it.
const BUTTERFLY_BLADE := Vector3(-0.11, 0.0, -0.29)
# Folded over the pads to cover: hips, trunk and chest, each further on.
const COVER_HIP_FOLD_RAD: float = deg_to_rad(25.0)
const COVER_TRUNK_FOLD_RAD: float = deg_to_rad(40.0)
const COVER_CHEST_FOLD_RAD: float = deg_to_rad(25.0)
# Turned on the hips toward a puck beside or behind him, his glove shoulder
# coming round and down after it; and sunk back between his skates (the W-sit
# a butterfly allows) and over toward it, all of it for one beside him or
# behind, none for one ahead, so the glove reaches the ice off his front.
const COVER_TURN_MAX_RAD: float = deg_to_rad(90.0)
const COVER_SIT_M: float = 0.3
const COVER_SIT_OVER_M: float = 0.10
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
		leg.flex = 0.0
		leg.along_shin = 0.0
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


static func low_ready(p: KeeperPose) -> void:
	ready(p)
	p.pelvis = LOW_READY_PELVIS
	p.pelvis_rot = Vector3(-0.35, 0.0, 0.0)
	p.lumbar_rot = Vector3(-0.35, 0.0, 0.0)
	p.neck_rot = Vector3(0.45, 0.0, 0.0)
	for i: int in 2:
		var sx: float = _side_x(i)
		var leg: KeeperPose.Leg = p.legs[i]
		leg.ankle = Vector3(sx * LOW_READY_SKATE_HALF_SPACING_M, KeeperAnatomy.ANKLE_ON_SKATES_M,
				LOW_READY_SKATE_BACK_M)
		leg.knee_pinned = true
		leg.knee = Vector3(sx * LOW_READY_KNEE.x, LOW_READY_KNEE.y, LOW_READY_KNEE.z)
		leg.shin_front = Vector3(-sx * LOW_READY_PAD_FACE.x, LOW_READY_PAD_FACE.y, LOW_READY_PAD_FACE.z).normalized()
		leg.toe = _FORWARD
	p.blade_center = LOW_READY_BLADE
	p.stick_tilt = LOW_READY_STICK_TILT_RAD
	p.glove_hand = LOW_READY_GLOVE_FROM_CHEST


# The butterfly, loaded to push toward `side`: the pad on that side stays down
# sealing the ice, and the other leg's knee comes up off the ice and in while
# its skate plants out wide to drive off. The push from the butterfly, where
# the half butterfly, its pad standing, is the push from the feet.
static func butterfly_push(p: KeeperPose, side: float) -> void:
	butterfly(p)
	var push: int = 1 if side < 0.0 else 0
	var sx: float = _side_x(push)
	var leg: KeeperPose.Leg = p.legs[push]
	leg.knee_pinned = false
	leg.ankle = Vector3(sx * BUTTERFLY_PUSH_SKATE.x, BUTTERFLY_PUSH_SKATE.y, BUTTERFLY_PUSH_SKATE.z)
	leg.knee_pole = Vector3(sx * BUTTERFLY_PUSH_KNEE_POLE.x, BUTTERFLY_PUSH_KNEE_POLE.y,
			BUTTERFLY_PUSH_KNEE_POLE.z)
	leg.shin_front = Vector3(sx * BUTTERFLY_PUSH_PAD_FACE.x, BUTTERFLY_PUSH_PAD_FACE.y,
			BUTTERFLY_PUSH_PAD_FACE.z)
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = ready_toe(sx)
	leg.along_shin = 0.0


# The half butterfly with its standing skate where the ready stance has it,
# toward `side`: the slide from his feet's stance as the lead knee lands, and
# the recovery's as the push leg comes up, the skate a T-push toward `side`
# drives off.
static func half_butterfly_loaded(p: KeeperPose, side: float) -> void:
	half_butterfly(p, side)
	var up: int = 1 if side < 0.0 else 0
	var sx: float = _side_x(up)
	p.legs[up].ankle = Vector3(sx * READY_SKATE_HALF_SPACING_M, KeeperAnatomy.ANKLE_ON_SKATES_M, 0.0)
	p.legs[up].toe = ready_toe(sx)


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
	if side < 0.0:
		# Out on the glove side, the blade comes in a touch so the blocker sits
		# against the hip, and the glove drops toward the pad it seals.
		p.blade_center.x -= 0.03
		p.glove_hand.y -= 0.03


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
		p.blade_center = READY_BLADE + Vector3(-0.12, 0.0, -0.14)
		p.stick_tilt = READY_STICK_TILT_RAD + deg_to_rad(10.0)
	else:
		# The lie carries the grip out past the kick: the hips go with it to keep
		# it in the blocker arm's reach, over a glove skate drawn in under them.
		p.legs[0].ankle.x = -0.18
		p.pelvis += Vector3(0.12, -0.03, 0.0)
		p.blade_center = READY_BLADE + Vector3(0.26, 0.0, -0.12)
		p.stick_tilt = READY_STICK_TILT_RAD + deg_to_rad(12.0)


# Reverse-VH on the post at `side`, compact and sealed to the iron: sat back on
# the post leg's calf, its pad flat along the goal line from the knee out to
# the toe hooked on the post; the other pad standing. Upright, his shoulder on
# the post no further out than the pad's toe, so the pad seals the ice up to
# the iron; the hands in close and the blade on the ice in front of the pads,
# the stick leaning no further toward the post than he does. The brain puts
# KeeperGear.post_pad_contact on the post.
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
	p.lumbar_rot = Vector3(-0.08, 0.0, 0.0)
	p.chest_rot = Vector3.ZERO
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
		# In front at the waist, toward the middle; the paddle out in front
		# toward the glove side and turned in, so the shaft the lie leans to
		# the post's side keeps its butt inside the pad's toe.
		p.glove_hand = Vector3(-0.30, -0.10, -0.38)
		p.blade_center = RVH_BLOCKER_SIDE_BLADE
		p.blade_yaw += RVH_BLOCKER_SIDE_BLADE_TURN_RAD


# Leaning on over the pads to cover a puck at his feet at `toward`, `share` of
# the way: the trunk folding forward from the hips and the chest after it, and
# turning until the puck is ahead of his glove shoulder, so that shoulder comes
# down and out over the ice the glove reaches for; for one off his front, his
# hips sunk back and over toward it as far as it is off his front.
static func cover_lean(p: KeeperPose, toward: Vector3, share: float) -> void:
	p.pelvis_rot.x -= COVER_HIP_FOLD_RAD * share
	p.lumbar_rot.x -= COVER_TRUNK_FOLD_RAD * share
	p.chest_rot.x -= COVER_CHEST_FOLD_RAD * share
	# The elbows still hang from the shoulders as they fold: a pole left
	# pointing down comes into line with an arm reaching down and flips it.
	var fold := Basis(Vector3.RIGHT, -(COVER_HIP_FOLD_RAD + COVER_TRUNK_FOLD_RAD + COVER_CHEST_FOLD_RAD) * share)
	p.glove_elbow_pole = fold * p.glove_elbow_pole
	p.blocker_elbow_pole = fold * p.blocker_elbow_pole
	var turn: float = cover_turn(toward)
	var off_front: float = clampf(absf(turn) / (PI * 0.5), 0.0, 1.0)
	var over := Vector3(toward.x, 0.0, toward.z)
	p.pelvis += (over.normalized() * COVER_SIT_OVER_M if over.length() > 1e-4 else Vector3.ZERO) * share * off_front \
			+ Vector3.DOWN * COVER_SIT_M * share * off_front
	turn_trunk(p, turn * share)


# How far a full cover lean turns his trunk toward a puck at `toward`: until
# it is ahead of his glove shoulder, no further than COVER_TURN_MAX_RAD.
static func cover_turn(toward: Vector3) -> float:
	return clampf(atan2(-(toward.x + KeeperAnatomy.SHOULDER_HALF_SPACING_M), -toward.z),
			-COVER_TURN_MAX_RAD, COVER_TURN_MAX_RAD)


# His trunk turned `turn` from the waist, about the vertical through his hips,
# the hands and the stick they hold with it. The pelvis stays with the legs:
# turned, it would carry the hips round over skates that stay on their line and
# pitch a pad into the ice.
static func turn_trunk(p: KeeperPose, turn: float) -> void:
	var about := Basis(Vector3.UP, turn)
	var hips := Vector3(p.pelvis.x, 0.0, p.pelvis.z)
	p.lumbar_rot.y += turn
	p.blade_center = hips + about * (p.blade_center - hips)
	p.blade_yaw -= turn
	p.blocker_face = about * p.blocker_face
	p.glove_fingers = about * p.glove_fingers
	p.glove_palm = about * p.glove_palm
	p.glove_elbow_pole = about * p.glove_elbow_pole
	p.blocker_elbow_pole = about * p.blocker_elbow_pole
	if not p.glove_from_chest:
		p.glove_hand = hips + about * (p.glove_hand - hips)


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
	# A stance holds the stick by where it lays the blade.
	p.blocker_reach = false


static func _ready_leg(leg: KeeperPose.Leg, sx: float) -> void:
	leg.ankle = Vector3(sx * READY_SKATE_HALF_SPACING_M, KeeperAnatomy.ANKLE_ON_SKATES_M, 0.0)
	leg.knee_pinned = false
	# Knees in and forward: the pole aims each knee toward the middle.
	leg.knee_pole = Vector3(-sx * READY_KNEE_IN_M, 0.0, -1.0)
	leg.thigh_front = _FORWARD
	leg.shin_front = Vector3(-sx * 0.15, 0.0, -1.0)
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = ready_toe(sx)
	leg.flex = 0.0
	leg.along_shin = 0.0


# The ready stance's skate on side `sx` (+1 his blocker side), toed out.
static func ready_toe(sx: float) -> Vector3:
	return Vector3(sx * sin(READY_TOE_OUT_RAD), 0.0, -cos(READY_TOE_OUT_RAD))


static func _butterfly_leg(leg: KeeperPose.Leg, sx: float, shin_y: float, knee_z: float,
		flare: float) -> void:
	leg.knee_pinned = true
	leg.knee = Vector3(sx * BUTTERFLY_KNEE_HALF_SPACING_M, shin_y, knee_z)
	var dir := Vector3(sx * cos(flare), 0.0, sin(flare))
	leg.ankle = leg.knee + dir * KeeperAnatomy.SHIN_M
	leg.thigh_front = _FORWARD
	leg.shin_front = _FORWARD
	leg.foot_mode = KeeperPose.FootMode.ALONG_SHIN
	# The foot lies in the pad's toe, turned with it, so the skate lies on its
	# side inside the pad's end rather than reaching on out toward the post.
	leg.flex = KeeperAnatomy.PAD_TOE_ANGLE_RAD


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
