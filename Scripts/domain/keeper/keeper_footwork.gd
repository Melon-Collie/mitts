class_name KeeperFootwork
extends RefCounted

# His skates while he moves along his line across the crease, and the stance
# they bend: the T-push, the shuffle and the edge stop that ends both. Pure,
# stepped at the tick.
#
# The kinematics are GoaliePushRules', at the move's own top speed: the trail
# skate's edge accelerates him, and the lead edge brakes him onto his spot.
#
# The T-push's push is the acceleration: the trail skate is planted for it and
# the body drives off it, the leg extending as he goes, which is why a push is
# about a leg's extension long (0.27 s to 3.8 m/s covers 0.52 m).
#   PUSH   the lead skate turns toward the travel, its pad part of the way
#          with it; the trail skate stays where it was set down until the leg
#          is out straight, the hips sinking a little to reach it
#   GLIDE  he rides the lead skate; the trail leg lifts and draws back in
# The shuffle stays square, both skates on the ice, in strokes laid over the
# ground: the trail skate's edge holds its place while the body passes
# SHUFFLE_PUSH_OUT_M over it, then it slides back in under him while the lead
# skate carries him on. He strokes (PUSH) until he stops.
#   STOP   the lead skate digs its edge (squaring back from a T-push), the
#          trail leg comes in under him, and he leans back against the
#          momentum, as far as the speed he stops from asks
#   SET    the ready stance, once the stop has settled out of his body
#
# Positions are along his own line in the stances' frame (x, + toward his
# blocker side), so a right-catcher's moves are read through
# KeeperSkeleton.world_side like his stances'.

enum Phase { SET, PUSH, GLIDE, STOP }
enum Move { T_PUSH, SHUFFLE }

# How far round toward the travel the T-push's lead skate turns at its fullest
# (from the ready stance's toe-out to along the travel), and how much of that
# turn his pad's face follows: a real T-push turns the lead pad off the shooter.
const LEAD_TURN: float = 1.0
const LEAD_PAD_FOLLOW: float = 0.5
# How long the lead skate takes to turn in, and the lean into the move to come
# on or go; the trail leg to draw back in once a push is over; and the stop to
# leave his body once he is on his spot.
const TURN_IN_S: float = 0.08
const RECOVER_S: float = 0.18
const SETTLE_S: float = 0.15
# A trail skate drawn back in lifts clear by up to this, the most once it has
# LIFT_FULL_AT_M to come; a skate barely out slides in on the ice.
const RECOVER_LIFT_M: float = 0.03
const LIFT_FULL_AT_M: float = 0.2
# The shuffle's stroke: the body travel per stroke, and how much of it the
# trail skate holds its place for.
const SHUFFLE_STROKE_M: float = 0.45
const SHUFFLE_PUSH_OUT_M: float = 0.14
# The lead skate's edge in the stop: out a little wider, rolled onto its inside
# edge; and the lean, into the move and back against the stop. The stop's are
# at full from a T-push's top speed and in proportion below it.
const STOP_LEAD_OUT_M: float = 0.05
const STOP_EDGE_RAD: float = deg_to_rad(12.0)
const PUSH_LEAN_RAD: float = deg_to_rad(5.0)
const SHUFFLE_LEAN_RAD: float = deg_to_rad(2.0)
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

var t_push_speed: float = GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S
var shuffle_speed: float = GameRules.DEFAULT_GOALIE_SHUFFLE_SPEED_M_S
var accel: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2

# Where he is along his line (m) and how fast he is going toward his spot
# (negative while a retarget still carries him the other way).
var x: float = 0.0
var speed: float = 0.0
var phase: int = Phase.SET
var move: int = Move.T_PUSH

var _target: float = 0.0
var _side: float = 1.0
# How far he has come since the move started (the shuffle's strokes are laid
# over it), and where the T-push's trail skate was set down, along his line.
var _travel: float = 0.0
var _plant: float = 0.0
# Where the trail skate was, relative to him, and how high, when its push
# ended, and how far it is back in since.
var _trail_from: float = 0.0
var _lift_from: float = 0.0
var _recover: float = 1.0
# How far the lead skate is turned in, how far the lean into the move is on,
# and how far into the stop he is (held once he is set, and let go over
# SETTLE_S) and how hard a stop it is.
var _turn: float = 0.0
var _drive: float = 0.0
var _stop: float = 0.0
var _stop_from_speed: float = 0.0


# T-push to `target` along his line.
func push_to(target: float) -> void:
	_go(target, Move.T_PUSH)


# Shuffle to `target` along his line.
func shuffle_to(target: float) -> void:
	_go(target, Move.SHUFFLE)


# From the set stance `kind` starts; a new spot the same way mid-move retargets
# the move under way, and one the other way pushes off the edge he is riding,
# the way he was going carried into it.
func _go(target: float, kind: int) -> void:
	_target = target
	if absf(target - x) < 1e-4:
		return
	var side: float = signf(target - x)
	if phase != Phase.SET and side == _side:
		return
	if phase != Phase.SET:
		speed = -speed
	move = kind
	_side = side
	_travel = 0.0
	_plant = x - _side * KeeperPoses.READY_SKATE_HALF_SPACING_M
	_trail_from = -_side * KeeperPoses.READY_SKATE_HALF_SPACING_M
	_lift_from = 0.0
	_recover = 1.0
	_turn = 0.0
	_stop = 0.0
	phase = Phase.PUSH


func top_speed() -> float:
	return t_push_speed if move == Move.T_PUSH else shuffle_speed


func step(dt: float) -> void:
	_drive = move_toward(_drive, 1.0 if phase == Phase.PUSH else 0.0, dt / TURN_IN_S)
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
	var was: float = speed
	match phase:
		Phase.PUSH:
			speed = minf(speed + accel * dt, top_speed())
			if move == Move.T_PUSH:
				_turn = minf(_turn + dt / TURN_IN_S, 1.0)
				if speed >= top_speed():
					_end_push()
					phase = Phase.GLIDE
		Phase.GLIDE:
			_recover = minf(_recover + dt / RECOVER_S, 1.0)
		Phase.STOP:
			# The lead edge digs as hard as it takes to stop on the spot, which
			# from the tick the stop starts is the edge's brake.
			speed = maxf(speed - speed * speed / (2.0 * maxf(left, 1e-6)) * dt, 0.0)
			_recover = minf(_recover + dt / RECOVER_S, 1.0)
			_stop = 1.0 - speed / maxf(_stop_from_speed, 1e-6)
	var travelled: float = 0.5 * (was + speed) * dt
	x += _side * travelled
	_travel += absf(travelled)
	if (_target - x) * _side <= 0.0 or (phase == Phase.STOP and speed <= 1e-4):
		x = _target
		speed = 0.0
		_stop = 1.0
		_turn = 0.0
		phase = Phase.SET


func _end_push() -> void:
	if phase == Phase.PUSH:
		_trail_from = _pushing_trail_x()
		_lift_from = _stroke_lift()
		_recover = 0.0


func _home() -> float:
	return -_side * KeeperPoses.READY_SKATE_HALF_SPACING_M


# The trail skate relative to him while he is pushing.
func _pushing_trail_x() -> float:
	if move == Move.SHUFFLE:
		var d: float = fposmod(_travel, SHUFFLE_STROKE_M)
		if d < SHUFFLE_PUSH_OUT_M:
			return _home() - _side * d
		return _home() - _side * SHUFFLE_PUSH_OUT_M * (1.0 - smoothstep(0.0, 1.0, _stroke_back()))
	# The T-push's: on its plant until the leg is out as far as it goes, then
	# dragged with him.
	return (_plant - x) if (_plant - x) * _side > _furthest_trail() * _side else _furthest_trail()


# How far back in a shuffle stroke's trail skate is, 0 to 1; 0 while it holds.
func _stroke_back() -> float:
	var d: float = fposmod(_travel, SHUFFLE_STROKE_M)
	return maxf(d - SHUFFLE_PUSH_OUT_M, 0.0) / (SHUFFLE_STROKE_M - SHUFFLE_PUSH_OUT_M)


func _stroke_lift() -> float:
	if move != Move.SHUFFLE or phase != Phase.PUSH:
		return 0.0
	return _lift(SHUFFLE_PUSH_OUT_M, _stroke_back())


# A trail skate's lift `back` (0 to 1) of the way in from `out` beside home.
static func _lift(out: float, back: float) -> float:
	return RECOVER_LIFT_M * clampf(out / LIFT_FULL_AT_M, 0.0, 1.0) * sin(PI * back)


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
	var stop: float = _stop * clampf(_stop_from_speed / t_push_speed, 0.0, 1.0)
	# The lead skate turns toward the travel and squares back in the stop.
	var turn: float = _turn * (1.0 - _stop)
	lead.toe = lead.toe.slerp(Vector3(s, 0.0, 0.0), LEAD_TURN * turn)
	var pad_turn: float = KeeperPoses.ready_toe(s).signed_angle_to(lead.toe, Vector3.UP) \
			* LEAD_PAD_FOLLOW
	lead.shin_front = lead.shin_front.rotated(Vector3.UP, pad_turn)
	lead.knee_pole = lead.knee_pole.rotated(Vector3.UP, pad_turn)
	# The stop's edge: the lead skate out a little and rolled onto its inside
	# edge, the knee driven in over it.
	lead.ankle.x += s * STOP_LEAD_OUT_M * stop
	lead.shin_front = lead.shin_front.rotated(Vector3.FORWARD, -s * STOP_EDGE_RAD * stop)
	# The trail skate: pushing, then drawn back in, lifted as it comes.
	var home: float = _home()
	var trail_x: float
	if phase == Phase.PUSH:
		trail_x = _pushing_trail_x()
		trail.ankle.y += _stroke_lift()
	else:
		var back: float = smoothstep(0.0, 1.0, _recover)
		trail_x = lerpf(_trail_from, home, back)
		trail.ankle.y += lerpf(_lift_from, 0.0, back) + _lift(absf(_trail_from - home), _recover)
	trail.ankle.x = trail_x
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
	# The lean: into the move, back against the stop.
	var lean: float = PUSH_LEAN_RAD if move == Move.T_PUSH else SHUFFLE_LEAN_RAD
	p.lumbar_rot.z += -s * lean * _drive + s * STOP_LEAN_RAD * stop
