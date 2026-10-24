class_name KeeperLowReady
extends RefCounted

# The low ready laid over his stance on his feet (KeeperPoses.low_ready), as
# how far he has sunk into it: 0 his skating stance, 1 the low A. Pure, stepped
# at the tick by KeeperMotor.
#
# Asked (`asked`), he sinks over SINK_S while set on his feet or skating with
# the play no faster than he shuffles; any other move, he rises out of it as
# it starts, over RISE_S, as quick as he sat into it. A drop or a low save
# from it is the shorter fall (`fall_share`), and goes from the pose he is in
# (`cut`).

const SINK_S: float = 0.15
const RISE_S: float = 0.15
# On the way, the pads' faces tipped up by as much again at the most, or the
# inside edge by the skate digs in as the shin lays over.
const PAD_TIP_ON_THE_WAY: float = 0.6

var asked: bool = false
# How far he has sunk, 0 to 1: the low ready's share of his pose.
var share: float = 0.0

# How far he has sunk along the way, eased into `share`.
var _sunk: float = 0.0
var _low := KeeperPose.new()
var _skel := KeeperSkeleton.new()
static var _butterfly_knee_y: float = -1.0


func _init() -> void:
	KeeperPoses.low_ready(_low)


# One tick on his feet: sinking while `settled` (set, or skating with the play)
# and asked, rising out of it otherwise.
func step(dt: float, settled: bool) -> void:
	if settled and asked:
		_sunk = minf(_sunk + dt / SINK_S, 1.0)
	else:
		_sunk = maxf(_sunk - dt / RISE_S, 0.0)
	share = smoothstep(0.0, 1.0, _sunk)


# A drop or a save cut in from where he is: its pose has it from here.
func cut() -> void:
	share = 0.0
	_sunk = 0.0


# The share of a drop's time the fall from where he has sunk takes.
func fall_share() -> float:
	return fall_share_at(share)


# A fall from rest goes as the root of its height, the knees' down to where the
# butterfly lands them.
static func fall_share_at(sunk: float) -> float:
	if _butterfly_knee_y < 0.0:
		var butterfly := KeeperPose.new()
		KeeperPoses.butterfly(butterfly)
		_butterfly_knee_y = butterfly.legs[0].knee.y
	var up: float = KeeperDrop.ready_knee(0).y
	var at: float = lerpf(up, KeeperPoses.LOW_READY_KNEE.y, sunk)
	return sqrt(maxf(at - _butterfly_knee_y, 0.0) / (up - _butterfly_knee_y))


# `p` sunk `share` of the way into the low ready; `standing_ready` when `p` is
# the ready stance itself, whose knees are solved once. The skates go out
# first and the knees follow them down, as a widening A drives them.
func lay_over(p: KeeperPose, standing_ready: bool) -> void:
	if share <= 0.0:
		return
	if not standing_ready:
		_skel.pose(p)
	KeeperDrop.blend_body(p, p, _low, share)
	for i: int in 2:
		var leg: KeeperPose.Leg = p.legs[i]
		var knee: Vector3 = leg.knee
		if not leg.knee_pinned:
			knee = KeeperDrop.ready_knee(i) if standing_ready else _skel.xf[KeeperSkeleton.SHIN[i]].origin
		sink_leg(leg, leg, knee, _low.legs[i], share)


# A leg `s` of the way from standing on its skate (`up`, its knee at `up_knee`)
# down into a low stance's (`low`, its knee pinned): the skate out first and
# the knee after it, the pad's face tipped up on the way; up out of it the
# same way reversed, the knee first, so a sink turned back halfway runs on
# unbroken. `rising` is a push up out of it onto the skate (a kick from the
# low ready): the knee comes up sooner still, and the skate in later, or the
# pad's inside edge digs as the A narrows under a knee still down. `leg` may
# be `up`.
static func sink_leg(leg: KeeperPose.Leg, up: KeeperPose.Leg, up_knee: Vector3, low: KeeperPose.Leg,
		s: float, rising: bool = false) -> void:
	var skate: float = sqrt(s)
	var knee: float = s * s
	if rising:
		skate = pow(s, 1.0 / 3.0)
		knee = pow(s, 2.5)
	leg.knee_pinned = true
	leg.knee = up_knee.lerp(low.knee, knee)
	leg.ankle = up.ankle.lerp(low.ankle, skate)
	leg.thigh_front = up.thigh_front.lerp(low.thigh_front, s).normalized()
	leg.shin_front = (up.shin_front.lerp(low.shin_front, skate)
			+ Vector3(0.0, PAD_TIP_ON_THE_WAY * sin(PI * skate), 0.0)).normalized()
	leg.toe = up.toe.lerp(low.toe, s).normalized()
	leg.flex = lerpf(up.flex, low.flex, s)
	leg.along_shin = lerpf(up.along_shin, low.along_shin, s)
