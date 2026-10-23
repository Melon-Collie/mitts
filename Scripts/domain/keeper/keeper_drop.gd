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
# The recovery is the rise toward somewhere, in the rise's time: the leg away
# from where he is going comes up first onto its skate where the stance has it
# (KeeperPoses.half_butterfly_loaded), then the lead leg comes up after it as
# the rise's do, the first skate holding its place. He stands where he got up,
# with the skate a push that way drives off already loaded on its edge; the
# push is the move that follows.
#
# Between the stances the knees go the shortest way, pinned from where the ready
# stance's solve puts them down to the ice, so the drop's first frame is the
# stance's own. The skates kick out ahead of them and come off the ice as they
# go, turning into the pads' toes: a knee that came down over a skate still
# where it stood would pitch the shin over it and drive the pad's rigid toe
# into the ice.

enum State { UP, DROPPING, DOWN, RISING, RECOVERING }

# How high the skates come off the ice at most, a quarter of the way down.
const SKATES_OFF_M: float = 0.06
# A push leg coming up out of the butterfly onto its skate, to slide off or
# recover on (the old goalie's coil).
const PUSH_LOAD_S: float = 0.12
# How high the recovery's first leg lifts its skate coming up to stand on it:
# higher than a drop's, since the skate comes up under a knee rising over it,
# and lower the boot's rigid toe catches the ice.
const FIRST_LEG_LIFT_M: float = 0.12

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

# The way the recovery goes (+1 his blocker side).
var _toward: float = 1.0

static var _ready_knees: Array[Vector3] = []
var _up := KeeperPose.new()
var _low := KeeperPose.new()
# Loaded to recover toward the glove side (index 0) or the blocker side (1),
# and the push knee's place in each.
var _loaded: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
var _loaded_knee: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func _init() -> void:
	KeeperPoses.ready(_up)
	KeeperPoses.butterfly(_low)
	var skel := KeeperSkeleton.new()
	for i: int in 2:
		KeeperPoses.half_butterfly_loaded(_loaded[i], -1.0 if i == 0 else 1.0)
		skel.pose(_loaded[i])
		_loaded_knee[i] = skel.xf[KeeperSkeleton.SHIN[1 - i]].origin


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


# Up toward `toward` (+1 his blocker side), from the butterfly.
func recover(toward: float) -> void:
	if state == State.DOWN:
		state = State.RECOVERING
		_toward = signf(toward) if toward != 0.0 else 1.0
		_clock = 0.0


# The share of the recovery the push leg takes to load.
func _load_share() -> float:
	return PUSH_LOAD_S / rise_s


# How far the lead leg is up in the recovery, 0 to 1 (0 while the first loads).
func _lead_up() -> float:
	return smoothstep(0.0, 1.0, maxf(_clock - _load_share(), 0.0) / (1.0 - _load_share()))


func _lead() -> int:
	return 1 if _toward > 0.0 else 0


func step(dt: float) -> void:
	match state:
		State.RECOVERING:
			_clock = minf(_clock + dt / rise_s, 1.0)
			down = 1.0 - _clock
			if _clock >= 1.0:
				state = State.UP
				down = 0.0
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


# His pose `down` of the way from the ready stance to the butterfly, or as far
# through the recovery as he is.
func pose(p: KeeperPose) -> void:
	if state == State.RECOVERING:
		_recovering(p)
		return
	if down <= 0.0:
		p.copy_from(_up)
		return
	if down >= 1.0:
		p.copy_from(_low)
		return
	_blend(p, _up, _low, down)


func _recovering(p: KeeperPose) -> void:
	var lead: int = _lead()
	var push: int = 1 - lead
	var loaded: KeeperPose = _loaded[lead]
	if _clock < _load_share():
		var up: float = smoothstep(0.0, 1.0, _clock / _load_share())
		blend_body(p, _low, loaded, up)
		p.legs[lead].copy_from(_low.legs[lead])
		# Up onto its skate as the rise's legs come, the drop's way reversed.
		blend_leg(p.legs[push], loaded.legs[push], _loaded_knee[lead], _low.legs[push], 1.0 - up,
				FIRST_LEG_LIFT_M)
		return
	var drive: float = _lead_up()
	blend_body(p, loaded, _up, drive)
	blend_leg(p.legs[lead], _up.legs[lead], ready_knee(lead), _low.legs[lead], 1.0 - drive)
	# The first leg up stands on its skate, held where it was set down, as the
	# hips rise over it.
	var leg: KeeperPose.Leg = p.legs[push]
	var from: KeeperPose.Leg = loaded.legs[push]
	var to: KeeperPose.Leg = _up.legs[push]
	leg.copy_from(from)
	leg.knee_pole = from.knee_pole.lerp(to.knee_pole, drive)
	leg.shin_front = from.shin_front.lerp(to.shin_front, drive).normalized()


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
# shortest way down, the skate kicked out ahead of it and off the ice by up to
# `lift`, turning into the pad's toe.
static func blend_leg(leg: KeeperPose.Leg, up: KeeperPose.Leg, up_knee: Vector3,
		low: KeeperPose.Leg, t: float, lift: float = SKATES_OFF_M) -> void:
	leg.knee_pinned = true
	leg.knee = up_knee.lerp(low.knee, t)
	var kick: float = 1.0 - (1.0 - t) * (1.0 - t)
	leg.ankle = up.ankle.lerp(low.ankle, kick)
	leg.ankle.y += lift * sin(PI * sqrt(t))
	leg.thigh_front = up.thigh_front.lerp(low.thigh_front, t).normalized()
	leg.shin_front = up.shin_front.lerp(low.shin_front, t).normalized()
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = up.toe
	leg.flex = low.flex
	leg.along_shin = t


# Where the ready stance's solve puts the knee on `side` (0 the glove leg).
static func ready_knee(side: int) -> Vector3:
	if _ready_knees.is_empty():
		var ready := KeeperPose.new()
		KeeperPoses.ready(ready)
		_ready_knees_solved(ready)
	return _ready_knees[side]


# Where the ready stance's solve puts the knees, solved once.
static func _ready_knees_solved(ready: KeeperPose) -> Array[Vector3]:
	if _ready_knees.is_empty():
		var skel := KeeperSkeleton.new()
		skel.pose(ready)
		for side: int in 2:
			_ready_knees.append(skel.xf[KeeperSkeleton.SHIN[side]].origin)
	return _ready_knees


# The push leg `t` of the way from its skate (`up`, its knee at `up_knee`) down
# into the butterfly (`low`): the knee pinned the shortest way, and the lower
# leg swung round it, the skate lifting clear as it goes, so a skate that
# moves round the knee does not pass through the leg, and the pad's face and
# the skate turn with it.
static func swing_leg(leg: KeeperPose.Leg, up: KeeperPose.Leg, up_knee: Vector3,
		low: KeeperPose.Leg, t: float) -> void:
	leg.knee_pinned = true
	leg.knee = up_knee.lerp(low.knee, t)
	var from: Vector3 = up.ankle - up_knee
	var to: Vector3 = low.ankle - low.knee
	var heading: float = atan2(from.x, from.z)
	var turn: float = wrapf(atan2(to.x, to.z) - heading, -PI, PI)
	var y: float = lerpf(from.y, to.y, t) + SKATES_OFF_M * sin(PI * t)
	var flat: float = sqrt(maxf(KeeperAnatomy.SHIN_M * KeeperAnatomy.SHIN_M - y * y, 0.0))
	var along: float = heading + turn * t
	leg.ankle = leg.knee + Vector3(sin(along) * flat, y, cos(along) * flat)
	leg.thigh_front = up.thigh_front.lerp(low.thigh_front, t).normalized()
	leg.shin_front = up.shin_front.rotated(Vector3.UP, turn * t).lerp(low.shin_front, t).normalized()
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = up.toe.rotated(Vector3.UP, turn * t)
	leg.flex = low.flex
	leg.along_shin = t
