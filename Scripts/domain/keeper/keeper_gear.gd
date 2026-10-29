class_name KeeperGear
extends RefCounted

# What stops the puck: one box per piece of gear, each strapped to the bone that
# carries it, so the gear goes wherever the pose puts the body. The boxes are
# the save geometry — `fill_boxes` writes them in GoalieContactDetector's packed
# layout (basis columns, origin, half extents: 15 floats a box) — and the
# meshes are drawn inside them.
#
# Every part rebounds as one of GoalieSaveRules' materials (`save_part`).

enum Part {
	PAD_G, PAD_B, RISE_G, RISE_B, BOOT_G, BOOT_B, SKATE_G, SKATE_B, THIGH_G, THIGH_B,
	PANTS, CHEST, UPPER_ARM_G, FOREARM_G, UPPER_ARM_B, FOREARM_B,
	GLOVE, BLOCKER, MASK, BLADE, PADDLE, SHAFT,
}
const PART_COUNT: int = 22
const FLOATS_PER_BOX: int = 15

const _SP := GoalieSaveRules.SavePart
const _B := KeeperSkeleton.Bone

# Per part: the bone it rides (-1: placed from the skeleton by its own rule — the
# thigh rises at the break, the boots at their toe's angle, the stick by its
# solve), its centre and half extents
# in that bone's frame, and its material.
const _BONE: Array[int] = [
	_B.SHIN_G, _B.SHIN_B, -1, -1, -1, -1, _B.FOOT_G, _B.FOOT_B,
	_B.THIGH_G, _B.THIGH_B, _B.PELVIS, _B.CHEST,
	_B.UPPER_ARM_G, _B.FOREARM_G, _B.UPPER_ARM_B, _B.FOREARM_B,
	_B.HAND_G, _B.HAND_B, _B.HEAD, -1, -1, -1,
]
const _SAVE_PART: Array[int] = [
	_SP.PAD, _SP.PAD, _SP.PAD, _SP.PAD, _SP.PAD, _SP.PAD, _SP.PAD, _SP.PAD, _SP.PAD, _SP.PAD,
	_SP.CHEST, _SP.CHEST, _SP.CHEST, _SP.CHEST, _SP.CHEST, _SP.CHEST,
	_SP.GLOVE, _SP.BLOCKER, _SP.MASK, _SP.STICK, _SP.STICK, _SP.STICK,
]

# Pad: from below the ankle, over the skate's toe, up through the knee stack;
# its face stands proud of the shin.
const _PAD_CENTER := Vector3(0.0,
		(KeeperAnatomy.PAD_ABOVE_KNEE_M - KeeperAnatomy.SHIN_M - KeeperAnatomy.PAD_BELOW_ANKLE_M) * 0.5,
		-KeeperAnatomy.PAD_FORWARD_OF_SHIN_M)
const _PAD_HALF := Vector3(KeeperAnatomy.PAD_WIDTH_M * 0.5, KeeperAnatomy.PAD_LENGTH_M * 0.5, KeeperAnatomy.PAD_DEPTH_M * 0.5)
# The thigh rise: the pad carried on past the knee stack, thinner, its face
# flush with the pad's.
const _RISE_HALF := Vector3(KeeperAnatomy.PAD_WIDTH_M * 0.5, KeeperAnatomy.PAD_THIGH_RISE_M * 0.5, 0.04)
const _RISE_FACE_Z: float = -KeeperAnatomy.PAD_FORWARD_OF_SHIN_M \
		- KeeperAnatomy.PAD_DEPTH_M * 0.5 + _RISE_HALF.z
# A pad settles on the ice (`_pad_settle`) past this much of its foam's give,
# up to this far up its leg, and only on a shin standing up at least this much
# (its up axis's height): a pad laid flat rests on the ice already.
const PAD_SETTLE_GIVE_M: float = 0.025
const PAD_SETTLE_MAX_M: float = 0.12
const PAD_SETTLE_MIN_RISE: float = 0.1
# Settled this much clear of the give, so it rests inside it to the float.
const PAD_SETTLE_SLACK_M: float = 1.0e-5
# The boot's toe flexes up off the ice by at most this past its built angle,
# found to within BOOT_FLEX_MAX_RAD / 2^BOOT_FLEX_STEPS (about half a degree).
const BOOT_FLEX_MAX_RAD: float = deg_to_rad(30.0)
const BOOT_FLEX_STEPS: int = 6

# The pad's boot: the pad's toe, a stiff section of it jutting forward over
# the skate's toe from the pad's lower face, as wide as the pad and on the
# shin with it (`_boot_box`), turned up by KeeperAnatomy.PAD_TOE_ANGLE_RAD
# so in the stance it lies along the skate just off the ice. Where the foot
# pitches down under the shin instead (a kick), the skate shows beneath it, as
# a real one does. Measured in that turned frame from the ankle.
const _BOOT_BACK_M: float = -0.02
const _BOOT_FRONT_M: float = -(KeeperAnatomy.FOOT_LENGTH_M - KeeperAnatomy.HEEL_BEHIND_ANKLE_M) - 0.04
const _BOOT_BOTTOM_M: float = -KeeperAnatomy.ANKLE_ON_SKATES_M + 0.06
const _BOOT_TOP_M: float = 0.05
const _BOOT_CENTER := Vector3(0.0, (_BOOT_BOTTOM_M + _BOOT_TOP_M) * 0.5,
		(_BOOT_BACK_M + _BOOT_FRONT_M) * 0.5)
const _BOOT_HALF := Vector3(KeeperAnatomy.PAD_WIDTH_M * 0.5, (_BOOT_TOP_M - _BOOT_BOTTOM_M) * 0.5,
		(_BOOT_BACK_M - _BOOT_FRONT_M) * 0.5)
# The skate, ice to above the ankle, heel to toe.
const _SKATE_CENTER := Vector3(0.0, -KeeperAnatomy.ANKLE_ON_SKATES_M * 0.5 + 0.01,
		-(KeeperAnatomy.FOOT_LENGTH_M * 0.5 - KeeperAnatomy.HEEL_BEHIND_ANKLE_M))
const _SKATE_HALF := Vector3(KeeperAnatomy.SKATE_HALF_WIDTH_M, KeeperAnatomy.ANKLE_ON_SKATES_M * 0.5 + 0.01,
		KeeperAnatomy.FOOT_LENGTH_M * 0.5)
const _THIGH_CENTER := Vector3(0.0, -KeeperAnatomy.THIGH_M * 0.5, 0.0)
const _THIGH_HALF := Vector3(KeeperAnatomy.THIGH_PAD_WIDTH_M * 0.5, KeeperAnatomy.THIGH_M * 0.5,
		KeeperAnatomy.THIGH_PAD_DEPTH_M * 0.5)
# The pants on the pelvis: from below the seat up to the belly, 15 cm over the
# hip joints, where the jersey's hem and tail hang over them.
const _PANTS_TOP_M: float = 0.15
const _PANTS_BOTTOM_M: float = -0.14
const _PANTS_CENTER := Vector3(0.0, (_PANTS_TOP_M + _PANTS_BOTTOM_M) * 0.5, 0.01)
const _PANTS_HALF := Vector3(KeeperAnatomy.PANTS_WIDTH_M * 0.5, (_PANTS_TOP_M - _PANTS_BOTTOM_M) * 0.5, 0.16)
# The chest protector, floaters to the pants' waistband.
const _CHEST_TOP: float = KeeperAnatomy.SHOULDER_ABOVE_CHEST_M + 0.05
# The chest protector ends at the belt, on the chest bone; the jersey's tail
# hangs on from there over the pants (KeeperJerseyTail), drawn only.
const CHEST_BOTTOM_M: float = -0.15
const _CHEST_CENTER := Vector3(0.0, (_CHEST_TOP + CHEST_BOTTOM_M) * 0.5, -0.01)
const _CHEST_HALF := Vector3(KeeperAnatomy.CHEST_WIDTH_M * 0.5, (_CHEST_TOP - CHEST_BOTTOM_M) * 0.5,
		KeeperAnatomy.CHEST_DEPTH_M * 0.5)
# The upper arm's pad and sleeve, its shoulder cap riding the top of it over the
# joint and up under the jersey's slope to the neck.
const SHOULDER_CAP_ABOVE_JOINT_M: float = 0.05
const SHOULDER_CAP_RADIUS_M: float = 0.10
const _UPPER_ARM_CENTER := Vector3(0.0,
		(SHOULDER_CAP_ABOVE_JOINT_M - KeeperAnatomy.UPPER_ARM_M) * 0.5, 0.0)
const _UPPER_ARM_HALF := Vector3(SHOULDER_CAP_RADIUS_M,
		(KeeperAnatomy.UPPER_ARM_M + SHOULDER_CAP_ABOVE_JOINT_M) * 0.5, SHOULDER_CAP_RADIUS_M)
# The forearm's pad and sleeve, from the wrist up through the elbow pad: a
# ball round the joint, just proud of the sleeves, that fills the bend.
const FOREARM_PAD_RADIUS_M: float = KeeperAnatomy.ARM_PAD_WIDTH_M * 0.47
const ELBOW_PAD_RADIUS_M: float = FOREARM_PAD_RADIUS_M * 1.04
const _FOREARM_CENTER := Vector3(0.0, (ELBOW_PAD_RADIUS_M - KeeperAnatomy.FOREARM_M) * 0.5, 0.0)
const _FOREARM_HALF := Vector3(ELBOW_PAD_RADIUS_M,
		(KeeperAnatomy.FOREARM_M + ELBOW_PAD_RADIUS_M) * 0.5, ELBOW_PAD_RADIUS_M)
# The trapper rides the hand from the cuff past the fingertips, the hand in its
# back half behind the pocket.
const _GLOVE_CENTER := Vector3(0.0, -0.06, -0.03)
const _GLOVE_HALF := Vector3(KeeperAnatomy.GLOVE_WIDTH_M * 0.5, KeeperAnatomy.GLOVE_HEIGHT_M * 0.5,
		KeeperAnatomy.GLOVE_DEPTH_M * 0.5)
# The blocker: the board standing on the back of the hand, toward its face,
# and the gloved fist behind it on the stick.
const _BLOCKER_FRONT_M: float = -KeeperAnatomy.BLOCKER_FACE_OFF_GRIP_M - KeeperAnatomy.BLOCKER_DEPTH_M * 0.5
const _BLOCKER_BACK_M: float = KeeperAnatomy.BLOCKER_FIST_CENTER.z + KeeperAnatomy.BLOCKER_FIST_HALF.z
const _BLOCKER_CENTER := Vector3(0.0, KeeperAnatomy.BLOCKER_ABOVE_GRIP_M,
		(_BLOCKER_FRONT_M + _BLOCKER_BACK_M) * 0.5)
const _BLOCKER_HALF := Vector3(KeeperAnatomy.BLOCKER_WIDTH_M * 0.5, KeeperAnatomy.BLOCKER_HEIGHT_M * 0.5,
		(_BLOCKER_BACK_M - _BLOCKER_FRONT_M) * 0.5)
# The mask on the head bone (its origin on the neck's line at chin height): the
# shell's chin 4.5 cm under the chin, its dome 2 cm over the skull, the cage
# 17.5 cm ahead of the neck and the backplate 12.5 cm behind it.
const MASK_BELOW_CHIN_M: float = 0.045
const MASK_TOP_M: float = KeeperAnatomy.SKULL_TOP_ABOVE_HEAD_M + 0.02
const MASK_FRONT_M: float = 0.175
const MASK_BACK_M: float = 0.125
const _MASK_CENTER := Vector3(0.0, (MASK_TOP_M - MASK_BELOW_CHIN_M) * 0.5,
		(MASK_BACK_M - MASK_FRONT_M) * 0.5)
const _MASK_HALF := Vector3(0.12, (MASK_TOP_M + MASK_BELOW_CHIN_M) * 0.5,
		(MASK_BACK_M + MASK_FRONT_M) * 0.5)

const _CENTER: Array[Vector3] = [
	_PAD_CENTER, _PAD_CENTER, Vector3.ZERO, Vector3.ZERO, _BOOT_CENTER, _BOOT_CENTER, _SKATE_CENTER, _SKATE_CENTER,
	_THIGH_CENTER, _THIGH_CENTER, _PANTS_CENTER, _CHEST_CENTER,
	_UPPER_ARM_CENTER, _FOREARM_CENTER, _UPPER_ARM_CENTER, _FOREARM_CENTER,
	_GLOVE_CENTER, _BLOCKER_CENTER, _MASK_CENTER,
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
]
const _HALF: Array[Vector3] = [
	_PAD_HALF, _PAD_HALF, _RISE_HALF, _RISE_HALF, _BOOT_HALF, _BOOT_HALF, _SKATE_HALF, _SKATE_HALF,
	_THIGH_HALF, _THIGH_HALF, _PANTS_HALF, _CHEST_HALF,
	_UPPER_ARM_HALF, _FOREARM_HALF, _UPPER_ARM_HALF, _FOREARM_HALF,
	_GLOVE_HALF, _BLOCKER_HALF, _MASK_HALF,
	Vector3(KeeperAnatomy.BLADE_LENGTH_M * 0.5, KeeperAnatomy.BLADE_HEIGHT_M * 0.5, KeeperAnatomy.BLADE_THICKNESS_M * 0.5),
	Vector3(KeeperAnatomy.PADDLE_WIDTH_M * 0.5,
			(KeeperAnatomy.PADDLE_LENGTH_M - KeeperAnatomy.PADDLE_ROOT_ABOVE_HEEL_M) * 0.5,
			KeeperAnatomy.PADDLE_THICKNESS_M * 0.5),
	Vector3(KeeperAnatomy.SHAFT_WIDTH_M * 0.5, KeeperAnatomy.SHAFT_LENGTH_M * 0.5, KeeperAnatomy.PADDLE_THICKNESS_M * 0.5),
]


static func save_part(part: int) -> int:
	return _SAVE_PART[part]


static func half_extents(part: int) -> Vector3:
	return _HALF[part]


# Where a part's box sits on its bone: its centre in the bone's frame.
static func center_on_bone(part: int) -> Vector3:
	return _CENTER[part]


# The part's box in keeper space: basis columns are its axes, origin its centre.
static func box(skel: KeeperSkeleton, part: int) -> Transform3D:
	if part == Part.PAD_G or part == Part.PAD_B:
		return _pad_box(skel, part - Part.PAD_G).translated(_pad_settle(skel, part - Part.PAD_G))
	if part == Part.RISE_G or part == Part.RISE_B:
		return _rise_box(skel, part - Part.RISE_G).translated(_pad_settle(skel, part - Part.RISE_G))
	if part == Part.BOOT_G or part == Part.BOOT_B:
		return _boot_box(skel, part - Part.BOOT_G).translated(_pad_settle(skel, part - Part.BOOT_G))
	var bone: int = _BONE[part]
	if bone >= 0:
		var b: Transform3D = skel.xf[bone]
		return Transform3D(b.basis, b * _CENTER[part])
	return _stick_box(skel, part)


# The pad strapped on its shin, where the leg holds it.
static func _pad_box(skel: KeeperSkeleton, side: int) -> Transform3D:
	var shin: Transform3D = skel.xf[KeeperSkeleton.SHIN[side]]
	return Transform3D(shin.basis, shin * _PAD_CENTER)


# How far the pad on `side`, its boot and its rise ride up the shin to rest on
# the ice: a shin tilted in (knees driven in, skates wide) would put the rigid
# pad's bottom corner, or its boot's toe, into the ice, where a real pad,
# strapped loose round the leg, settles onto it instead. Past its foam's give,
# and no further than its straps let it. Keeper space.
static func _pad_settle(skel: KeeperSkeleton, side: int) -> Vector3:
	var low: float = minf(lowest(_pad_box(skel, side), _PAD_HALF), lowest(_boot_box(skel, side), _BOOT_HALF))
	var sink: float = -low - PAD_SETTLE_GIVE_M
	if sink <= 0.0:
		return Vector3.ZERO
	var up: Vector3 = skel.xf[KeeperSkeleton.SHIN[side]].basis.y.normalized()
	if up.y < PAD_SETTLE_MIN_RISE:
		return Vector3.ZERO
	return up * minf((sink + PAD_SETTLE_SLACK_M) / up.y, PAD_SETTLE_MAX_M)


# A box's lowest point.
static func lowest(t: Transform3D, h: Vector3) -> float:
	return t.origin.y - absf(t.basis.x.y) * h.x - absf(t.basis.y.y) * h.y - absf(t.basis.z.y) * h.z


# The boot on the shin, turned toe-up at the ankle by its built-in angle; where
# that would drive its toe into the ice past the foam's give (a shin leant on
# over it), the toe bridge flexes it up off the ice instead, no further than
# BOOT_FLEX_MAX_RAD.
static func _boot_box(skel: KeeperSkeleton, side: int) -> Transform3D:
	var shin: Transform3D = skel.xf[KeeperSkeleton.SHIN[side]]
	var ankle: Vector3 = shin * Vector3(0.0, -KeeperAnatomy.SHIN_M, 0.0)
	var built: Transform3D = _boot_turned(shin.basis, ankle, KeeperAnatomy.PAD_TOE_ANGLE_RAD)
	if lowest(built, _BOOT_HALF) >= -PAD_SETTLE_GIVE_M:
		return built
	var flexed: float = KeeperAnatomy.PAD_TOE_ANGLE_RAD
	var most: float = KeeperAnatomy.PAD_TOE_ANGLE_RAD + BOOT_FLEX_MAX_RAD
	if lowest(_boot_turned(shin.basis, ankle, most), _BOOT_HALF) < -PAD_SETTLE_GIVE_M:
		return _boot_turned(shin.basis, ankle, most)
	for _i: int in BOOT_FLEX_STEPS:
		var mid: float = (flexed + most) * 0.5
		if lowest(_boot_turned(shin.basis, ankle, mid), _BOOT_HALF) < -PAD_SETTLE_GIVE_M:
			flexed = mid
		else:
			most = mid
	return _boot_turned(shin.basis, ankle, most)


static func _boot_turned(shin: Basis, ankle: Vector3, toe_up: float) -> Transform3D:
	var basis: Basis = shin * Basis(Vector3.RIGHT, toe_up)
	return Transform3D(basis, ankle + basis * _BOOT_CENTER)


# The thigh rise rides the shin as the pad's continuation and bends at the break
# toward the thigh, about the pad's width: as far as the knee has folded, up to
# the break's limit, and only as far as the shin stands up. Upright, the rise
# leans back onto the thigh; with the pad flat on the ice it lies flat with it,
# carrying the pad on toward the middle.
static func _rise_box(skel: KeeperSkeleton, side: int) -> Transform3D:
	var shin: Transform3D = skel.xf[KeeperSkeleton.SHIN[side]]
	var thigh_dir: Vector3 = skel.xf[KeeperSkeleton.THIGH[side]].basis.y
	var hinge_axis: Vector3 = shin.basis.x.normalized()
	var shin_dir: Vector3 = shin.basis.y.normalized()
	var toward: Vector3 = thigh_dir - hinge_axis * thigh_dir.dot(hinge_axis)
	var fold: float = 0.0
	if toward.length_squared() > 1e-8:
		fold = shin_dir.signed_angle_to(toward, hinge_axis)
	var bend: float = clampf(fold, -KeeperAnatomy.PAD_BREAK_MAX_RAD, KeeperAnatomy.PAD_BREAK_MAX_RAD) \
			* clampf(shin_dir.y, 0.0, 1.0)
	var basis: Basis = shin.basis.rotated(hinge_axis, bend)
	var root: Vector3 = shin * Vector3(0.0, KeeperAnatomy.PAD_RISE_ROOT_ABOVE_KNEE_M, 0.0)
	return Transform3D(basis, root + basis * Vector3(0.0, _RISE_HALF.y, _RISE_FACE_Z))


# The stick's box from its solved lie. A right-catcher's lie is reflected
# vectors, whose cross turns the other way: his box is turned half round its
# own y to the reflected frame his bones have, so his drawn stick is the true
# mirror.
static func _stick_box(skel: KeeperSkeleton, part: int) -> Transform3D:
	var lie: Transform3D = _stick_box_from_lie(skel, part)
	if skel.mirrored:
		lie.basis = Basis(-lie.basis.x, lie.basis.y, -lie.basis.z)
	return lie


static func _stick_box_from_lie(skel: KeeperSkeleton, part: int) -> Transform3D:
	var paddle: Vector3 = skel.stick_paddle_dir
	var blade: Vector3 = skel.stick_blade_dir
	var h: Vector3 = _HALF[part]
	if part == Part.BLADE:
		# The blade's height runs up its face, in the plane the paddle shares, and
		# it rests on the ice on its lowest edge.
		var up: Vector3 = (paddle - blade * paddle.dot(blade)).normalized()
		var flat := Basis(blade, up, blade.cross(up))
		var center: Vector3 = skel.stick_heel + blade * h.x
		center.y = skel.stick_heel.y + h.y * absf(up.y) + h.z * absf(flat.z.y)
		return Transform3D(flat, center)
	var across: Vector3 = (blade - paddle * blade.dot(paddle)).normalized()
	var basis := Basis(across, paddle, across.cross(paddle))
	var along: float = (KeeperAnatomy.PADDLE_ROOT_ABOVE_HEEL_M + KeeperAnatomy.PADDLE_LENGTH_M) * 0.5
	if part == Part.SHAFT:
		along = KeeperAnatomy.PADDLE_LENGTH_M + KeeperAnatomy.SHAFT_LENGTH_M * 0.5
	return Transform3D(basis, skel.stick_heel + paddle * along)


# Where a post stance meets the post at `side` of keeper space (−1 the −X
# post; a stance's own side through KeeperSkeleton.world_side): the post's
# inner face at the outermost reach of that side's leg (pad, boot, skate), on
# the goal line through its ankle: the pad overlaps the post along the ice,
# where a puck is jammed in, not the stick's shaft or a hand held out wider.
static func post_contact(skel: KeeperSkeleton, side: float) -> Vector3:
	var g: Vector3 = skel.xf[KeeperSkeleton.FOOT[0]].origin
	var b: Vector3 = skel.xf[KeeperSkeleton.FOOT[1]].origin
	var leg: int = 0 if g.x * side > b.x * side else 1
	var reach: float = -INF
	for part: int in [Part.PAD_G + leg, Part.BOOT_G + leg, Part.SKATE_G + leg]:
		reach = maxf(reach, reach_x(skel, part, side))
	return Vector3(side * reach, 0.0, (g if leg == 0 else b).z)


# Where a pad laid along the goal line meets the post at `side` of keeper
# space: the post's inner face at that leg's pad's toe, on the line through its
# ankle. The skate turned out under the toe reaches past it, beside the iron,
# and the pad seals the ice up to it.
static func post_pad_contact(skel: KeeperSkeleton, side: float) -> Vector3:
	var g: Vector3 = skel.xf[KeeperSkeleton.FOOT[0]].origin
	var b: Vector3 = skel.xf[KeeperSkeleton.FOOT[1]].origin
	var leg: int = 0 if g.x * side > b.x * side else 1
	var reach: float = maxf(reach_x(skel, Part.PAD_G + leg, side), reach_x(skel, Part.BOOT_G + leg, side))
	return Vector3(side * reach, 0.0, (g if leg == 0 else b).z)


# How far toward `side` (±1 across keeper space) `part`'s box reaches.
static func reach_x(skel: KeeperSkeleton, part: int, side: float) -> float:
	var t: Transform3D = box(skel, part)
	var h: Vector3 = _HALF[part]
	return side * t.origin.x + absf(t.basis.x.x) * h.x + absf(t.basis.y.x) * h.y + absf(t.basis.z.x) * h.z


# Every part's box into `packed`, in GoalieContactDetector's layout, from
# `start` boxes in; returns the number written. `to_world` places keeper space
# in the rink. The array grows only the first time.
static func fill_boxes(skel: KeeperSkeleton, to_world: Transform3D,
		packed: PackedFloat32Array, start: int = 0) -> int:
	var need: int = (start + PART_COUNT) * FLOATS_PER_BOX
	if packed.size() < need:
		packed.resize(need)
	for part: int in PART_COUNT:
		var t: Transform3D = to_world * box(skel, part)
		var h: Vector3 = _HALF[part]
		var i: int = (start + part) * FLOATS_PER_BOX
		packed[i] = t.basis.x.x
		packed[i + 1] = t.basis.x.y
		packed[i + 2] = t.basis.x.z
		packed[i + 3] = t.basis.y.x
		packed[i + 4] = t.basis.y.y
		packed[i + 5] = t.basis.y.z
		packed[i + 6] = t.basis.z.x
		packed[i + 7] = t.basis.z.y
		packed[i + 8] = t.basis.z.z
		packed[i + 9] = t.origin.x
		packed[i + 10] = t.origin.y
		packed[i + 11] = t.origin.z
		packed[i + 12] = h.x
		packed[i + 13] = h.y
		packed[i + 14] = h.z
	return PART_COUNT


# The nearest part a puck's swept disc meets between `prev` and `curr`, or -1.
# Fills `out` with the contact (keeper space in, keeper space out).
static func nearest(skel: KeeperSkeleton, prev: Vector3, curr: Vector3, radius: float,
		out: SweptDiscOBB.Result, scratch: SweptDiscOBB.Result) -> int:
	var best: int = -1
	var best_toi: float = INF
	for part: int in PART_COUNT:
		if not SweptDiscOBB.contact(prev, curr, radius, box(skel, part), _HALF[part], scratch):
			continue
		if scratch.toi < best_toi:
			best_toi = scratch.toi
			best = part
			out.hit = true
			out.toi = scratch.toi
			out.point = scratch.point
			out.normal = scratch.normal
			out.depth = scratch.depth
	return best
