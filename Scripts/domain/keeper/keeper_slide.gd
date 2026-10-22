class_name KeeperSlide
extends RefCounted

# His butterfly slide along his line: from the butterfly, the push leg comes up
# and drives him off its skate while the lead pad stays flat on the ice, then
# it folds back down and he rides the pads to rest on his spot. Pure, stepped
# at the tick.
#
#   LOAD   the push leg rises out of the butterfly onto its skate, planted
#          on its edge beside him: the half butterfly's loaded leg
#   PUSH   the skate holds its place on the ice while the leg drives him off
#          it, from rest up to the push's speed
#   GLIDE  the leg folds back down into the butterfly, and the pads slide on
#          under friction until he is at rest
#   DOWN   the butterfly, on the spot
#
# Once pushed he cannot steer: friction is all that stops him. So the push is
# sized to the spot, and he comes to rest on it; past the hardest push's reach
# he comes to rest at that reach. Positions are along his line in the stances'
# frame (x, + toward his blocker side), as KeeperFootwork's.

enum Phase { DOWN, LOAD, PUSH, GLIDE }

# The push leg rising onto its skate (the old goalie's coil), driving, and
# folding back down.
const LOAD_S: float = 0.12
const PUSH_S: float = 0.12
const FOLD_S: float = 0.15

# The hardest push's speed, and the pads' friction on the ice (the old goalie's
# slide_friction, about μ 0.27).
var push_speed: float = GoalieSkillProfile.hard().slide_push_speed_mps
var friction: float = 2.6

var x: float = 0.0
var speed: float = 0.0
var phase: int = Phase.DOWN

var _side: float = 1.0
var _target: float = 0.0
# The speed this slide's push builds to, and how far through its phase he is.
var _peak: float = 0.0
var _clock: float = 0.0
# Where the push skate was planted, along his line; and the push leg as it was
# when its push ended, with the knee its solve put it at, to fold from.
var _plant: float = 0.0
var _released := KeeperPose.Leg.new()
var _released_knee := Vector3.ZERO

var _low := KeeperPose.new()
var _loaded: Array[KeeperPose] = [KeeperPose.new(), KeeperPose.new()]
var _loaded_knee: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _skel := KeeperSkeleton.new()


func _init() -> void:
	KeeperPoses.butterfly(_low)
	# Loaded toward the glove side (index 0) or the blocker side (1): the lead
	# pad down, the push leg up.
	for i: int in 2:
		KeeperPoses.half_butterfly(_loaded[i], -1.0 if i == 0 else 1.0)
		_skel.pose(_loaded[i])
		var push_leg: int = 1 - i
		_loaded_knee[i] = _skel.xf[KeeperSkeleton.SHIN[push_leg]].origin


# Slide toward `target` from the butterfly; where he will come to rest.
func slide_to(target: float) -> float:
	if phase != Phase.DOWN or absf(target - x) < 1e-4:
		return x
	_side = signf(target - x)
	var dist: float = minf(absf(target - x), reach(push_speed, friction))
	_target = x + _side * dist
	_peak = peak_for(dist, friction)
	phase = Phase.LOAD
	_clock = 0.0
	return _target


# How far the hardest push carries him, at rest.
static func reach(top_speed: float, mu_g: float) -> float:
	return top_speed * PUSH_S * 0.5 + top_speed * top_speed / (2.0 * mu_g)


# The push speed that brings him to rest `dist` along: the push's own travel
# plus friction's stop from it.
static func peak_for(dist: float, mu_g: float) -> float:
	var half_push: float = PUSH_S * 0.5
	return mu_g * (sqrt(half_push * half_push + 2.0 * dist / mu_g) - half_push)


# Seconds from the call until he is at rest `dist` along, within reach.
static func time_to(dist: float, mu_g: float) -> float:
	return LOAD_S + PUSH_S + peak_for(dist, mu_g) / mu_g


func step(dt: float) -> void:
	match phase:
		Phase.LOAD:
			_clock += dt / LOAD_S
			if _clock >= 1.0:
				phase = Phase.PUSH
				_clock = 0.0
				_plant = x + _loaded[_lead()].legs[_push_leg()].ankle.x
		Phase.PUSH:
			var was: float = speed
			_clock = minf(_clock + dt / PUSH_S, 1.0)
			speed = _peak * _clock
			x += _side * 0.5 * (was + speed) * dt
			if _clock >= 1.0:
				_release()
		Phase.GLIDE:
			_clock = minf(_clock + dt / FOLD_S, 1.0)
			# Friction to rest on the spot: from the push sized to it, the pads'
			# own friction.
			var left: float = (_target - x) * _side
			var was: float = speed
			speed = maxf(speed - speed * speed / (2.0 * maxf(left, 1e-6)) * dt, 0.0)
			x += _side * 0.5 * (was + speed) * dt
			if (_target - x) * _side <= 1e-4 or speed <= 1e-4:
				x = _target
				speed = 0.0
				if _clock >= 1.0:
					phase = Phase.DOWN


func _release() -> void:
	phase = Phase.GLIDE
	_clock = 0.0
	var p := KeeperPose.new()
	_pushing_pose(p)
	_released.copy_from(p.legs[_push_leg()])
	_skel.pose(p)
	_released_knee = _skel.xf[KeeperSkeleton.SHIN[_push_leg()]].origin


func _lead() -> int:
	return 1 if _side > 0.0 else 0


func _push_leg() -> int:
	return 1 - _lead()


# His pose this tick, relative to where he is.
func pose(p: KeeperPose) -> void:
	match phase:
		Phase.DOWN:
			p.copy_from(_low)
		Phase.LOAD:
			var up: float = smoothstep(0.0, 1.0, _clock)
			KeeperDrop.blend_body(p, _low, _loaded[_lead()], up)
			p.legs[_lead()].copy_from(_low.legs[_lead()])
			KeeperDrop.blend_leg(p.legs[_push_leg()], _loaded[_lead()].legs[_push_leg()],
					_loaded_knee[_lead()], _low.legs[_push_leg()], 1.0 - up)
		Phase.PUSH:
			_pushing_pose(p)
		Phase.GLIDE:
			var down: float = smoothstep(0.0, 1.0, _clock)
			KeeperDrop.blend_body(p, _loaded[_lead()], _low, down)
			p.legs[_lead()].copy_from(_low.legs[_lead()])
			KeeperDrop.blend_leg(p.legs[_push_leg()], _released, _released_knee,
					_low.legs[_push_leg()], down)


# Driving off the planted skate: the loaded half butterfly, its skate held
# where it was set down.
func _pushing_pose(p: KeeperPose) -> void:
	p.copy_from(_loaded[_lead()])
	p.legs[_push_leg()].ankle.x = _plant - x
