class_name KeeperSlide
extends RefCounted

# His butterfly slide along his line: the push leg drives him off its skate
# while the lead pad stays flat on the ice, then folds back down to seal; he
# rides the pads, and the lead skate's edge stops him on his spot. Pure,
# stepped at the tick. From the butterfly the push leg comes up to push; from
# his feet the lead leg goes down to the half butterfly and the push leg never
# leaves its skate.
#
#   DROP   from his feet: the lead knee falls to the ice as the butterfly's
#          drop does, the push leg loading on its skate where it stood, so the
#          push starts as the knee lands
#   LOAD   from the butterfly: the push leg's knee comes up off the ice and in, its skate
#          planted out wide on its inside edge (KeeperPoses.butterfly_push)
#   PUSH   the skate holds its place on the ice while the leg drives him off
#          it, from rest up to the push's speed
#   GLIDE  the push leg folds back down beside the lead pad, sealing the ice,
#          and the pads slide on under their friction
#   STOP   the lead skate, behind its pad, digs its inside edge, and he leans
#          back against it; both pads stay down
#   DOWN   the butterfly, on the spot, once the stop has settled out of him
#
# He pushes at the speed asked for, and starts the stop when the brake left
# would only just land him on the spot, so a slide is a push and a stop, not a
# coast. A spot too near for the push to be stopped in gets a softer push; one
# past where friction alone would stop the push is answered with that reach.
# Positions are along his line in the stances' frame (x, + toward his blocker
# side), as KeeperFootwork's.

enum Phase { DOWN, DROP, LOAD, PUSH, GLIDE, STOP }

# The push leg rising onto its skate (the old goalie's coil), driving, and
# folding back down; the stop leaving his body once he is at rest.
const LOAD_S: float = 0.12
const PUSH_S: float = 0.12
const FOLD_S: float = 0.15
const SETTLE_S: float = 0.15
# How much of his weight he gets through the lead skate's edge with both knees
# down, against the whole of it in a standing edge stop.
const EDGE_WEIGHT_SHARE: float = 0.3

# The hardest push's speed, and the pads' friction on the ice (the old goalie's
# slide_friction, about μ 0.27).
var push_speed: float = GoalieSkillProfile.hard().slide_push_speed_mps
# The lead knee's fall to the ice from his feet: the butterfly drop's.
var drop_s: float = GoalieSkillProfile.hard().butterfly_drop_s
var friction: float = 2.6
# What the lead skate's edge adds to the pads' friction in the stop: his share
# of a standing edge stop's brake.
var edge_brake: float = EDGE_WEIGHT_SHARE * GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2 \
		* GameRules.GOALIE_EDGE_STOP_DECEL_RATIO

var x: float = 0.0
var speed: float = 0.0
var phase: int = Phase.DOWN

var _side: float = 1.0
var _target: float = 0.0
# The speed this slide's push builds to, how far through its phase he is, how
# far the push leg is folded back down, and how far into the stop he is and
# how hard a one.
var _peak: float = 0.0
var _from_feet: bool = false
var _clock: float = 0.0
var _fold: float = 1.0
var _stop: float = 0.0
var _stop_from_speed: float = 0.0
# Where the push skate was planted, along his line; and the push leg as it was
# when its push ended, with the knee its solve put it at, to fold from.
var _plant: float = 0.0
var _released := KeeperPose.Leg.new()
var _released_knee := Vector3.ZERO

var _low := KeeperPose.new()
var _ready := KeeperPose.new()
# Loaded to push toward the glove side (index 0) or the blocker side (1), the
# lead pad down: from the butterfly, and from his feet.
var _loaded: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
var _loaded_knee: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _set: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
var _skel := KeeperSkeleton.new()


func _init() -> void:
	KeeperPoses.butterfly(_low)
	KeeperPoses.ready(_ready)
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		KeeperPoses.butterfly_push(_loaded[i], side)
		_skel.pose(_loaded[i])
		_loaded_knee[i] = _skel.xf[KeeperSkeleton.SHIN[1 - i]].origin
		# The half butterfly, its standing skate where the ready stance had it.
		KeeperPoses.half_butterfly(_set[i], side)
		_set[i].legs[1 - i].ankle = _ready.legs[1 - i].ankle
		_set[i].legs[1 - i].toe = _ready.legs[1 - i].toe


# Slide toward `target` from the butterfly, pushing at up to `top` m/s; where
# he will come to rest.
func slide_to(target: float, top: float = INF) -> float:
	return _start(target, top, false)


# Slide toward `target` from his feet, by the half butterfly; where he will
# come to rest. He ends in the butterfly.
func slide_from_feet(target: float, top: float = INF) -> float:
	return _start(target, top, true)


func _start(target: float, top: float, from_feet: bool) -> float:
	if phase != Phase.DOWN or absf(target - x) < 1e-4:
		return x
	_side = signf(target - x)
	var dist: float = absf(target - x)
	_peak = minf(minf(top, push_speed), _stoppable_peak(dist))
	_target = x + _side * minf(dist, glide_reach(_peak))
	_from_feet = from_feet
	phase = Phase.DROP if from_feet else Phase.LOAD
	_clock = 0.0
	_fold = 0.0
	_stop = 0.0
	return _target


func _brake() -> float:
	return friction + edge_brake


# The hardest push that can still be stopped `dist` along: its own travel plus
# the brake from it.
func _stoppable_peak(dist: float) -> float:
	var half_push: float = PUSH_S * 0.5
	var b: float = _brake()
	return b * (sqrt(half_push * half_push + 2.0 * dist / b) - half_push)


# How far a push at `peak` carries him with no stop, friction alone: further
# than that no stop is needed, and he cannot get there.
func glide_reach(peak: float) -> float:
	return peak * PUSH_S * 0.5 + peak * peak / (2.0 * friction)


# Seconds from the call until he is at rest `dist` along, pushing at up to
# `top`, within reach; from his feet, or from the butterfly.
func time_to(dist: float, top: float = INF, from_feet: bool = false) -> float:
	var v0: float = minf(minf(top, push_speed), _stoppable_peak(dist))
	var b: float = _brake()
	var left: float = maxf(dist - v0 * PUSH_S * 0.5, 0.0)
	# The speed the stop starts from: the glide on friction and the stop share
	# what the push left.
	var v1_sq: float = (v0 * v0 / (2.0 * friction) - left) / (1.0 / (2.0 * friction) - 1.0 / (2.0 * b))
	var v1: float = sqrt(clampf(v1_sq, 0.0, v0 * v0))
	return (drop_s if from_feet else LOAD_S) + PUSH_S + (v0 - v1) / friction + v1 / b


func step(dt: float) -> void:
	if phase == Phase.DOWN or phase == Phase.GLIDE or phase == Phase.STOP:
		_fold = minf(_fold + dt / FOLD_S, 1.0)
	match phase:
		Phase.DOWN:
			_stop = maxf(_stop - dt / SETTLE_S, 0.0)
		Phase.DROP, Phase.LOAD:
			_clock += dt / (drop_s if phase == Phase.DROP else LOAD_S)
			if _clock >= 1.0:
				phase = Phase.PUSH
				_clock = 0.0
				_plant = x + _launch().legs[_push_leg()].ankle.x
		Phase.PUSH:
			var was: float = speed
			_clock = minf(_clock + dt / PUSH_S, 1.0)
			speed = _peak * _clock
			x += _side * 0.5 * (was + speed) * dt
			if _clock >= 1.0:
				_release()
		Phase.GLIDE, Phase.STOP:
			var left: float = (_target - x) * _side
			# The stop starts the tick it would be too late to after this one's.
			if phase == Phase.GLIDE and speed >= sqrt(2.0 * _brake() * maxf(left - speed * dt, 0.0)):
				phase = Phase.STOP
				_stop_from_speed = speed
			var was: float = speed
			if phase == Phase.STOP:
				# The edge digs as hard as it takes to stop on the spot, which
				# from the tick the stop starts is its brake.
				speed = maxf(speed - speed * speed / (2.0 * maxf(left, 1e-6)) * dt, 0.0)
				_stop = 1.0 - speed / maxf(_stop_from_speed, 1e-6)
			else:
				speed = maxf(speed - friction * dt, 0.0)
			x += _side * 0.5 * (was + speed) * dt
			if (_target - x) * _side <= 1e-4 or speed <= 1e-4:
				x = _target
				speed = 0.0
				if _fold >= 1.0:
					phase = Phase.DOWN


func _release() -> void:
	phase = Phase.GLIDE
	var p := KeeperPose.new()
	_pushing_pose(p)
	_released.copy_from(p.legs[_push_leg()])
	_skel.pose(p)
	_released_knee = _skel.xf[KeeperSkeleton.SHIN[_push_leg()]].origin


# The pose he pushes from: the half butterfly from his feet, the loaded
# butterfly from the butterfly.
func _launch() -> KeeperPose:
	return _set[_lead()] if _from_feet else _loaded[_lead()]


func _lead() -> int:
	return 1 if _side > 0.0 else 0


func _push_leg() -> int:
	return 1 - _lead()


# His pose this tick, relative to where he is.
func pose(p: KeeperPose) -> void:
	match phase:
		Phase.DROP:
			# A fall, as the butterfly's drop: eased in, landing at speed.
			var down: float = _clock * _clock
			var launch: KeeperPose = _launch()
			KeeperDrop.blend_body(p, _ready, launch, down)
			KeeperDrop.blend_leg(p.legs[_lead()], _ready.legs[_lead()], KeeperDrop.ready_knee(_lead()),
					launch.legs[_lead()], down)
			var push: KeeperPose.Leg = p.legs[_push_leg()]
			push.copy_from(_ready.legs[_push_leg()])
			push.knee_pole = push.knee_pole.lerp(launch.legs[_push_leg()].knee_pole, down)
			push.shin_front = push.shin_front.lerp(launch.legs[_push_leg()].shin_front, down).normalized()
		Phase.LOAD:
			var up: float = smoothstep(0.0, 1.0, _clock)
			KeeperDrop.blend_body(p, _low, _loaded[_lead()], up)
			p.legs[_lead()].copy_from(_low.legs[_lead()])
			_swing(p.legs[_push_leg()], _loaded[_lead()].legs[_push_leg()],
					_loaded_knee[_lead()], _low.legs[_push_leg()], 1.0 - up)
		Phase.PUSH:
			_pushing_pose(p)
		_:
			var down: float = smoothstep(0.0, 1.0, _fold)
			if down >= 1.0:
				p.copy_from(_low)
			else:
				KeeperDrop.blend_body(p, _launch(), _low, down)
				p.legs[_lead()].copy_from(_low.legs[_lead()])
				# From his feet the leg comes down from standing, as the drop's do;
				# from the butterfly push it swings back round its knee.
				if _from_feet:
					KeeperDrop.blend_leg(p.legs[_push_leg()], _released, _released_knee,
							_low.legs[_push_leg()], down)
				else:
					_swing(p.legs[_push_leg()], _released, _released_knee, _low.legs[_push_leg()], down)
			# Back against the stop, as far as the speed it stops from asks.
			var stop: float = _stop * clampf(_stop_from_speed / GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S,
					0.0, 1.0)
			p.lumbar_rot.z += _side * KeeperFootwork.STOP_LEAN_RAD * stop


# Driving off the planted skate: the pose he pushes from, its skate held where
# it was set down.
func _pushing_pose(p: KeeperPose) -> void:
	p.copy_from(_launch())
	p.legs[_push_leg()].ankle.x = _plant - x


# The push leg `t` of the way from its skate (`up`, its knee at `up_knee`) down
# into the butterfly (`low`): the knee pinned the shortest way, and the lower
# leg swung round it, the skate lifting clear as it goes, so a skate that
# moves round the knee does not pass through the leg, and the pad's face and
# the skate turn with it.
static func _swing(leg: KeeperPose.Leg, up: KeeperPose.Leg, up_knee: Vector3,
		low: KeeperPose.Leg, t: float) -> void:
	leg.knee_pinned = true
	leg.knee = up_knee.lerp(low.knee, t)
	var from: Vector3 = up.ankle - up_knee
	var to: Vector3 = low.ankle - low.knee
	var heading: float = atan2(from.x, from.z)
	var turn: float = wrapf(atan2(to.x, to.z) - heading, -PI, PI)
	var y: float = lerpf(from.y, to.y, t) + KeeperDrop.SKATES_OFF_M * sin(PI * t)
	var flat: float = sqrt(maxf(KeeperAnatomy.SHIN_M * KeeperAnatomy.SHIN_M - y * y, 0.0))
	var along: float = heading + turn * t
	leg.ankle = leg.knee + Vector3(sin(along) * flat, y, cos(along) * flat)
	leg.thigh_front = up.thigh_front.lerp(low.thigh_front, t).normalized()
	leg.shin_front = up.shin_front.rotated(Vector3.UP, turn * t).lerp(low.shin_front, t).normalized()
	leg.foot_mode = KeeperPose.FootMode.FLAT
	leg.toe = up.toe.rotated(Vector3.UP, turn * t)
	leg.flex = low.flex
	leg.along_shin = t
