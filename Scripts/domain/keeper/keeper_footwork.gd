class_name KeeperFootwork
extends RefCounted

# His skates while he moves along his line across the crease, and the stance
# they bend: the T-push and the edge stop. Pure, stepped at the tick.
#
# The kinematics are GoaliePushRules': the trail skate's edge accelerates him
# up to top speed, he rides the lead skate, and the lead edge brakes him onto
# his spot. The push is the acceleration: the trail skate is planted for it and
# the body drives off it, the leg extending as he goes, which is why a push is
# about a leg's extension long (0.27 s to 3.8 m/s covers 0.52 m). Then:
#   PUSH   the lead skate turns toward the travel, its pad part of the way
#          with it; the trail skate stays where it was set down until the leg
#          is out straight, the hips sinking a little to reach it
#   GLIDE  he rides the lead skate; the trail leg lifts and draws back in
#   STOP   the lead skate squares back and digs its edge, the trail leg sets
#          down under him, and he leans back against the momentum
#   SET    the ready stance, once the stop has settled out of his body
#
# Positions are along his own line in the stances' frame (x, + toward his
# blocker side), so a right-catcher's moves are read through
# KeeperSkeleton.world_side like his stances'.

enum Phase { SET, PUSH, GLIDE, STOP }

# How far round toward the travel the lead skate turns at its fullest (from the
# ready stance's toe-out to along the travel), and how much of that turn his
# pad's face follows: a real T-push turns the lead pad off the shooter.
const LEAD_TURN: float = 1.0
const LEAD_PAD_FOLLOW: float = 0.5
# How long the lead skate takes to turn in at the start of a push, the trail
# leg to draw back in once the push is over, and the stop to leave his body
# once he is on his spot.
const TURN_IN_S: float = 0.08
const RECOVER_S: float = 0.18
const SETTLE_S: float = 0.15
const RECOVER_LIFT_M: float = 0.03
# The lead skate's edge in the stop: out a little wider, rolled onto its inside
# edge; and the lean, into the push and back against the stop.
const STOP_LEAD_OUT_M: float = 0.05
const STOP_EDGE_RAD: float = deg_to_rad(12.0)
const PUSH_LEAN_RAD: float = deg_to_rad(5.0)
const STOP_LEAN_RAD: float = deg_to_rad(6.0)
# The push leg stays a little short of straight, and the hips sink at most this
# far to keep its skate on its plant; past that the skate leaves the ice.
const TRAIL_REACH: float = 0.97
const MAX_PUSH_SINK_M: float = 0.06
# Where the push leg's knee and pad face aim as it drives (x out from his
# middle per metre forward), reached a third of the way into its extension.
const PUSH_KNEE_OUT: float = 0.2
const PUSH_KNEE_DRIVEN_AT: float = 0.33
const _TRAIL_REACH_M: float = TRAIL_REACH * (KeeperAnatomy.THIGH_M + KeeperAnatomy.SHIN_M)

var max_speed: float = GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S
var accel: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2

# Where he is along his line (m) and how fast he is going toward his spot
# (negative while a retarget still carries him the other way).
var x: float = 0.0
var speed: float = 0.0
var phase: int = Phase.SET

var _target: float = 0.0
var _side: float = 1.0
# Where the trail skate was set down for the push, along his line.
var _plant: float = 0.0
# Where it was, relative to him, when the push ended, and how far it is back in.
var _trail_from: float = 0.0
var _recover: float = 1.0
# How far the lead skate is turned in, and how far into the stop he is (held
# once he is set, and let go over SETTLE_S).
var _turn: float = 0.0
var _stop: float = 0.0
var _stop_from_speed: float = 0.0


# Push to `target` along his line. From the set stance it starts a T-push; a
# spot the other way mid-move pushes off the edge he is riding, the way he
# was going carried into it.
func push_to(target: float) -> void:
	_target = target
	if absf(target - x) < 1e-4:
		return
	var side: float = signf(target - x)
	if phase != Phase.SET and side == _side:
		return
	if phase != Phase.SET:
		speed = -speed
	_side = side
	_plant = x - _side * KeeperPoses.READY_SKATE_HALF_SPACING_M
	_trail_from = -_side * KeeperPoses.READY_SKATE_HALF_SPACING_M
	_recover = 1.0
	_turn = 0.0
	_stop = 0.0
	phase = Phase.PUSH


func step(dt: float) -> void:
	if phase == Phase.SET:
		_recover = minf(_recover + dt / RECOVER_S, 1.0)
		_stop = maxf(_stop - dt / SETTLE_S, 0.0)
		return
	var left: float = (_target - x) * _side
	# The stop starts the tick it would be too late to after this one's travel.
	var next_left: float = left - maxf(speed, 0.0) * dt
	if phase != Phase.STOP and speed > 0.0 \
			and speed >= GoaliePushRules.braking_speed_cap(next_left, accel):
		_end_push()
		phase = Phase.STOP
		_stop_from_speed = speed
	match phase:
		Phase.PUSH:
			speed = minf(speed + accel * dt, max_speed)
			_turn = minf(_turn + dt / TURN_IN_S, 1.0)
			x += _side * speed * dt
			if speed >= max_speed:
				_end_push()
				phase = Phase.GLIDE
		Phase.GLIDE:
			_recover = minf(_recover + dt / RECOVER_S, 1.0)
			x += _side * speed * dt
		Phase.STOP:
			# The lead edge digs as hard as it takes to stop on the spot, which
			# from the tick the stop starts is the edge's brake.
			var decel: float = speed * speed / (2.0 * maxf(left, 1e-6))
			var was: float = speed
			speed = maxf(speed - decel * dt, 0.0)
			x += _side * 0.5 * (was + speed) * dt
			_recover = minf(_recover + dt / RECOVER_S, 1.0)
			_stop = 1.0 - speed / maxf(_stop_from_speed, 1e-6)
	if (_target - x) * _side <= 0.0 or (phase == Phase.STOP and speed <= 1e-4):
		x = _target
		speed = 0.0
		_stop = 1.0
		_turn = 0.0
		phase = Phase.SET


func _end_push() -> void:
	if phase == Phase.PUSH:
		_trail_from = _trail_x()
		_recover = 0.0


# The trail skate relative to him while it is pushing: on its plant until the
# leg is out as far as it goes, then dragged with him.
func _trail_x() -> float:
	return (_plant - x) if (_plant - x) * _side > _furthest_trail() * _side else _furthest_trail()


# How far out the push leg reaches from hips sunk MAX_PUSH_SINK_M.
func _furthest_trail() -> float:
	var pelvis: Vector3 = KeeperPoses.READY_PELVIS
	var up: float = pelvis.y - MAX_PUSH_SINK_M - KeeperAnatomy.ANKLE_ON_SKATES_M
	var across: float = sqrt(maxf(_TRAIL_REACH_M * _TRAIL_REACH_M - up * up - pelvis.z * pelvis.z, 0.0))
	return -_side * (KeeperAnatomy.HIP_HALF_SPACING_M + across)


# His pose this tick, relative to where he is: the ready stance, bent by the
# move.
func pose(p: KeeperPose) -> void:
	KeeperPoses.ready(p)
	if phase == Phase.SET and _stop <= 0.0 and _recover >= 1.0:
		return
	var s: float = _side
	var lead: KeeperPose.Leg = p.legs[1 if s > 0.0 else 0]
	var trail: KeeperPose.Leg = p.legs[0 if s > 0.0 else 1]
	# The lead skate turns toward the travel and squares back in the stop.
	var turn: float = _turn * (1.0 - _stop)
	lead.toe = lead.toe.slerp(Vector3(s, 0.0, 0.0), LEAD_TURN * turn)
	var pad_turn: float = KeeperPoses.ready_toe(s).signed_angle_to(lead.toe, Vector3.UP) \
			* LEAD_PAD_FOLLOW
	lead.shin_front = lead.shin_front.rotated(Vector3.UP, pad_turn)
	lead.knee_pole = lead.knee_pole.rotated(Vector3.UP, pad_turn)
	# The stop's edge: the lead skate out a little and rolled onto its inside
	# edge, the knee driven in over it.
	lead.ankle.x += s * STOP_LEAD_OUT_M * _stop
	lead.shin_front = lead.shin_front.rotated(Vector3.FORWARD, -s * STOP_EDGE_RAD * _stop)
	# The trail skate: pushing, then drawn back in, lifted as it comes.
	var home: float = -s * KeeperPoses.READY_SKATE_HALF_SPACING_M
	var trail_x: float = _trail_x() if phase == Phase.PUSH \
			else lerpf(_trail_from, home, smoothstep(0.0, 1.0, _recover))
	trail.ankle.x = trail_x
	if phase != Phase.PUSH:
		trail.ankle.y += RECOVER_LIFT_M * sin(PI * _recover)
	# The hips sink with the push leg's extension, and never less than it needs
	# to reach its skate.
	var out: float = inverse_lerp(home, _furthest_trail(), trail_x)
	p.pelvis.y -= MAX_PUSH_SINK_M * smoothstep(0.0, 1.0, out)
	# The push leg's knee comes out of the stance's knee-in to drive over its
	# skate, or the pad's outer corner is driven into the ice.
	var drive := Vector3(-s * PUSH_KNEE_OUT, 0.0, -1.0)
	var driven: float = smoothstep(0.0, PUSH_KNEE_DRIVEN_AT, out)
	trail.knee_pole = trail.knee_pole.lerp(drive, driven)
	trail.shin_front = trail.shin_front.lerp(drive, driven)
	var across: float = trail_x + s * KeeperAnatomy.HIP_HALF_SPACING_M
	var up: float = sqrt(maxf(_TRAIL_REACH_M * _TRAIL_REACH_M - across * across - p.pelvis.z * p.pelvis.z, 0.0))
	p.pelvis.y = minf(p.pelvis.y, trail.ankle.y + up)
	# The lean: into the push, back against the stop.
	var push: float = 1.0 if phase == Phase.PUSH else 0.0
	p.lumbar_rot.z += -s * PUSH_LEAN_RAD * push * _turn + s * STOP_LEAN_RAD * _stop
