class_name KeeperHandsLow
extends RefCounted

# His hands set low while he is down with a carrier of theirs in tight, laid
# over the butterfly: the glove down beside his thigh with its fingers down,
# the blocker down at his hip with its board on the pad, the stick still flat
# on the ice through his fist. A shot from in tight is on him before his hands
# answer it, so they stop only what they already cover, and from there a puck
# is not lifted as high as the butterfly holds them. They are set for the
# height asked, their tops no higher than it and as low as they go, at his
# hands' speed, and come back up as quick. Pure, stepped at the tick.

# The glove hand low, in the chest's frame: as far down beside his thigh as
# the arm reaches.
const GLOVE_FROM_CHEST := Vector3(-0.38, -0.19, -0.41)
const GLOVE_FINGERS := Vector3(-0.15, -1.0, -0.1)
# How far his trunk leans on over his knees with his hands all the way down:
# as far as rests them on his pads, which kneeling tall his arms do not reach.
const LEAN_RAD: float = 0.20

# How fast his hands move (m/s): the tier's slower hand.
var speed_m_s: float = GoalieSkillProfile.hard().blocker_react_max_speed_mps
# The height (m off the ice) his hands are asked to be set for, and the one
# they are set for now; `highest()`, as the butterfly holds them.
var asked: float = 0.0
var set_m: float = 0.0
# Where the stance under them holds the stick, solved to bring the fist down
# from there.
var _skel := KeeperSkeleton.new()

# Within this of where they are going his hands slow into place: the last of
# the way down straightens the blocker's arm, and at full speed the elbow
# would snap.
const SETTLE_M: float = 0.10
const SETTLE_SPEED_SHARE: float = 0.2
const STEPS: int = 16

# Measured once off the butterfly: where its grip is; how far the blocker
# comes down; and each hand's top (the glove's, then the blocker's) at every
# STEPS'th of its way down, highest first.
static var _grip := Vector3.ZERO
static var _blocker_drop: float = 0.0
static var _tops: Array[PackedFloat32Array] = []


func _init() -> void:
	asked = highest()
	set_m = asked


# The height above which the hands are as the butterfly holds them.
static func highest() -> float:
	_measure()
	return maxf(_tops[0][0], _tops[1][0])


# The lowest height they are set for: lower than this they go no further.
static func lowest() -> float:
	_measure()
	return minf(_tops[0][STEPS], _tops[1][STEPS])


# `free`: down, or on his way down for a carrier, with nothing else for his
# hands or his body to do.
func step(dt: float, free: bool) -> void:
	var want: float = clampf(asked, lowest(), highest()) if free else highest()
	var slowed: float = clampf(absf(want - set_m) / SETTLE_M, SETTLE_SPEED_SHARE, 1.0)
	set_m = move_toward(set_m, want, speed_m_s * slowed * dt)


# Taken into the pose a save cuts in from: nothing more of it to lay over.
func cut() -> void:
	set_m = highest()


# `p`, the butterfly or his fall into it, with each hand as far down as brings
# its top to the height they are set for: the fist from wherever `p` holds the
# stick.
func lay_over(p: KeeperPose) -> void:
	if set_m >= highest() or p.blocker_reach:
		return
	_skel.pose(p)
	_lower(p, _share(0, set_m), _share(1, set_m), _skel.grip)


static func _lower(p: KeeperPose, glove: float, blocker: float, grip: Vector3) -> void:
	var lean: float = LEAN_RAD * maxf(glove, blocker)
	p.lumbar_rot.x -= lean * 0.5
	p.chest_rot.x -= lean * 0.5
	p.neck_rot.x += lean
	p.glove_hand += (GLOVE_FROM_CHEST - KeeperPoses.GLOVE_FROM_CHEST) * glove
	p.glove_fingers = p.glove_fingers.lerp(GLOVE_FINGERS, glove)
	if blocker > 0.0:
		p.blocker_reach = true
		p.blocker_grip = grip + Vector3.DOWN * (_blocker_drop * blocker)


# How far down hand `h` (0 the glove, 1 the blocker) is set for `height`,
# 0..1: as far as brings its top down to it.
static func _share(h: int, height: float) -> float:
	var tops: PackedFloat32Array = _tops[h]
	for i: int in STEPS:
		if height >= tops[i + 1]:
			return (i + inverse_lerp(tops[i], tops[i + 1], minf(height, tops[i]))) / STEPS
	return 1.0


static func _measure() -> void:
	if not _tops.is_empty():
		return
	var skel := KeeperSkeleton.new()
	var p := KeeperPose.new()
	KeeperPoses.butterfly(p)
	skel.pose(p)
	_grip = skel.grip
	# As far down as the arm takes the fist, leant on over his knees, with the
	# stick still through it.
	_blocker_drop = KeeperAnatomy.BLOCKER_HEIGHT_M
	_lower(p, 1.0, 1.0, _grip)
	skel.pose(p)
	_blocker_drop = _grip.y - skel.grip.y
	var tops: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	for i: int in STEPS + 1:
		KeeperPoses.butterfly(p)
		_lower(p, float(i) / STEPS, float(i) / STEPS, _grip)
		skel.pose(p)
		tops[0].append(_top(skel, KeeperGear.Part.GLOVE))
		tops[1].append(_top(skel, KeeperGear.Part.BLOCKER))
	# A hand's top never comes back up on its way down.
	for h: int in 2:
		for i: int in STEPS:
			tops[h][i + 1] = minf(tops[h][i + 1], tops[h][i] - 1e-4)
	_tops = tops


static func _top(skel: KeeperSkeleton, part: int) -> float:
	var box: Transform3D = KeeperGear.box(skel, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return box.origin.y + absf(box.basis.x.y) * h.x + absf(box.basis.y.y) * h.y + absf(box.basis.z.y) * h.z


# His state on the wire (KeeperWire); `speed_m_s` is the tier's and the heights
# are measured once.
func wire(w: KeeperWire) -> void:
	asked = w.s16(asked, KeeperWire.MM)
	set_m = w.s16(set_m, KeeperWire.MM)
