class_name KeeperSlide
extends RefCounted

# His butterfly slide along his line: from the butterfly, the push leg comes up
# and drives him off its skate while the lead pad stays flat on the ice, then
# folds back down to seal; he rides the pads, and the lead skate's edge stops
# him on his spot. Pure, stepped at the tick.
#
#   LOAD   the push leg rises out of the butterfly onto its skate, planted
#          on its edge beside him: the half butterfly's loaded leg
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

enum Phase { DOWN, LOAD, PUSH, GLIDE, STOP }

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
		_loaded_knee[i] = _skel.xf[KeeperSkeleton.SHIN[1 - i]].origin


# Slide toward `target` from the butterfly, pushing at up to `top` m/s; where
# he will come to rest.
func slide_to(target: float, top: float = INF) -> float:
	if phase != Phase.DOWN or absf(target - x) < 1e-4:
		return x
	_side = signf(target - x)
	var dist: float = absf(target - x)
	_peak = minf(minf(top, push_speed), _stoppable_peak(dist))
	_target = x + _side * minf(dist, glide_reach(_peak))
	phase = Phase.LOAD
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
# `top`, within reach.
func time_to(dist: float, top: float = INF) -> float:
	var v0: float = minf(minf(top, push_speed), _stoppable_peak(dist))
	var b: float = _brake()
	var left: float = maxf(dist - v0 * PUSH_S * 0.5, 0.0)
	# The speed the stop starts from: the glide on friction and the stop share
	# what the push left.
	var v1_sq: float = (v0 * v0 / (2.0 * friction) - left) / (1.0 / (2.0 * friction) - 1.0 / (2.0 * b))
	var v1: float = sqrt(clampf(v1_sq, 0.0, v0 * v0))
	return LOAD_S + PUSH_S + (v0 - v1) / friction + v1 / b


func step(dt: float) -> void:
	if phase != Phase.LOAD and phase != Phase.PUSH:
		_fold = minf(_fold + dt / FOLD_S, 1.0)
	match phase:
		Phase.DOWN:
			_stop = maxf(_stop - dt / SETTLE_S, 0.0)
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


func _lead() -> int:
	return 1 if _side > 0.0 else 0


func _push_leg() -> int:
	return 1 - _lead()


# His pose this tick, relative to where he is.
func pose(p: KeeperPose) -> void:
	match phase:
		Phase.LOAD:
			var up: float = smoothstep(0.0, 1.0, _clock)
			KeeperDrop.blend_body(p, _low, _loaded[_lead()], up)
			p.legs[_lead()].copy_from(_low.legs[_lead()])
			KeeperDrop.blend_leg(p.legs[_push_leg()], _loaded[_lead()].legs[_push_leg()],
					_loaded_knee[_lead()], _low.legs[_push_leg()], 1.0 - up)
		Phase.PUSH:
			_pushing_pose(p)
		_:
			var down: float = smoothstep(0.0, 1.0, _fold)
			if down >= 1.0:
				p.copy_from(_low)
			else:
				KeeperDrop.blend_body(p, _loaded[_lead()], _low, down)
				p.legs[_lead()].copy_from(_low.legs[_lead()])
				KeeperDrop.blend_leg(p.legs[_push_leg()], _released, _released_knee,
						_low.legs[_push_leg()], down)
			# Back against the stop, as far as the speed it stops from asks.
			var stop: float = _stop * clampf(_stop_from_speed / GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S,
					0.0, 1.0)
			p.lumbar_rot.z += _side * KeeperFootwork.STOP_LEAN_RAD * stop


# Driving off the planted skate: the loaded half butterfly, its skate held
# where it was set down.
func _pushing_pose(p: KeeperPose) -> void:
	p.copy_from(_loaded[_lead()])
	p.legs[_push_leg()].ankle.x = _plant - x
