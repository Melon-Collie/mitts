class_name KeeperDrop
extends RefCounted

# His drop from the ready stance into the butterfly and his rise back up, as
# how far down he is (0 standing, 1 down), stepped at the tick; and the pose
# that far between the two stances. Pure.
#
# The drop is a fall: the hips go from rest and the knees land on the ice at
# the speed the fall has built, so it eases in and not out. The rise is a push,
# eased both ways. A drop called mid-rise, or a rise mid-drop, goes from where
# he is.
#
# Between the stances the knees go the shortest way, pinned from where the ready
# stance's solve puts them down to the ice, so the drop's first frame is the
# stance's own. The skates kick out ahead of them and come off the ice as they
# go, turning into the pads' toes: a knee that came down over a skate still
# where it stood would pitch the shin over it and drive the pad's rigid toe
# into the ice.

enum State { UP, DROPPING, DOWN, RISING }

# How high the skates come off the ice at most, a quarter of the way down.
const SKATES_OFF_M: float = 0.06

# Seconds to the ice from standing, and back up.
var drop_s: float = GoalieSkillProfile.hard().butterfly_drop_s
# The old goalie's rise: the new body moves no faster than the old one until
# it is meant to (docs/goalie-rebuild-plan.md, Phase 2).
var rise_s: float = 0.35

var state: int = State.UP
# How far down he is, 0 to 1.
var down: float = 0.0

# Where the drop or rise under way started, and how far through it he is.
var _from: float = 0.0
var _clock: float = 0.0

static var _ready_knees: Array[Vector3] = []
var _up := KeeperPose.new()
var _low := KeeperPose.new()


func _init() -> void:
	KeeperPoses.ready(_up)
	KeeperPoses.butterfly(_low)


func drop() -> void:
	if state == State.UP or state == State.RISING:
		state = State.DROPPING
		_from = down
		_clock = 0.0


func rise() -> void:
	if state == State.DOWN or state == State.DROPPING:
		state = State.RISING
		_from = down
		_clock = 0.0


func step(dt: float) -> void:
	match state:
		State.DROPPING:
			_clock = minf(_clock + dt / (drop_s * (1.0 - _from)), 1.0)
			down = _from + (1.0 - _from) * _clock * _clock
			if _clock >= 1.0:
				state = State.DOWN
				down = 1.0
		State.RISING:
			_clock = minf(_clock + dt / (rise_s * _from), 1.0)
			down = _from * (1.0 - smoothstep(0.0, 1.0, _clock))
			if _clock >= 1.0:
				state = State.UP
				down = 0.0


# His pose `down` of the way from the ready stance to the butterfly.
func pose(p: KeeperPose) -> void:
	if down <= 0.0:
		p.copy_from(_up)
		return
	if down >= 1.0:
		p.copy_from(_low)
		return
	_blend(p, _up, _low, down)


static func _blend(p: KeeperPose, up: KeeperPose, low: KeeperPose, t: float) -> void:
	blend_body(p, up, low, t)
	var knees: Array[Vector3] = _ready_knees_solved(up)
	for i: int in 2:
		blend_leg(p.legs[i], up.legs[i], knees[i], low.legs[i], t)


# Everything but the legs, `t` of the way from `up` to `low`.
static func blend_body(p: KeeperPose, up: KeeperPose, low: KeeperPose, t: float) -> void:
	p.pelvis = up.pelvis.lerp(low.pelvis, t)
	p.pelvis_rot = up.pelvis_rot.lerp(low.pelvis_rot, t)
	p.lumbar_rot = up.lumbar_rot.lerp(low.lumbar_rot, t)
	p.chest_rot = up.chest_rot.lerp(low.chest_rot, t)
	p.neck_rot = up.neck_rot.lerp(low.neck_rot, t)
	p.head_rot = up.head_rot.lerp(low.head_rot, t)
	p.glove_hand = up.glove_hand.lerp(low.glove_hand, t)
	p.glove_from_chest = up.glove_from_chest
	p.glove_fingers = up.glove_fingers.lerp(low.glove_fingers, t)
	p.glove_palm = up.glove_palm.lerp(low.glove_palm, t)
	p.glove_elbow_pole = up.glove_elbow_pole.lerp(low.glove_elbow_pole, t)
	p.blocker_elbow_pole = up.blocker_elbow_pole.lerp(low.blocker_elbow_pole, t)
	p.blade_center = up.blade_center.lerp(low.blade_center, t)
	p.blade_yaw = lerpf(up.blade_yaw, low.blade_yaw, t)
	p.stick_tilt = lerpf(up.stick_tilt, low.stick_tilt, t)
	p.blocker_face = up.blocker_face.lerp(low.blocker_face, t)


# A leg `t` of the way from standing on its skate (`up`, whose solve puts the
# knee at `up_knee`) to kneeling in the butterfly (`low`): the knee pinned the
# shortest way down, the skate kicked out ahead of it and off the ice, turning
# into the pad's toe.
static func blend_leg(leg: KeeperPose.Leg, up: KeeperPose.Leg, up_knee: Vector3,
		low: KeeperPose.Leg, t: float) -> void:
	leg.knee_pinned = true
	leg.knee = up_knee.lerp(low.knee, t)
	var kick: float = 1.0 - (1.0 - t) * (1.0 - t)
	leg.ankle = up.ankle.lerp(low.ankle, kick)
	leg.ankle.y += SKATES_OFF_M * sin(PI * sqrt(t))
	leg.thigh_front = up.thigh_front.lerp(low.thigh_front, t).normalized()
	leg.shin_front = up.shin_front.lerp(low.shin_front, t).normalized()
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = up.toe
	leg.flex = low.flex
	leg.along_shin = t


# Where the ready stance's solve puts the knee on `side` (0 the glove leg).
static func ready_knee(side: int) -> Vector3:
	var ready := KeeperPose.new()
	KeeperPoses.ready(ready)
	return _ready_knees_solved(ready)[side]


# Where the ready stance's solve puts the knees, solved once.
static func _ready_knees_solved(ready: KeeperPose) -> Array[Vector3]:
	if _ready_knees.is_empty():
		var skel := KeeperSkeleton.new()
		skel.pose(ready)
		for side: int in 2:
			_ready_knees.append(skel.xf[KeeperSkeleton.SHIN[side]].origin)
	return _ready_knees
