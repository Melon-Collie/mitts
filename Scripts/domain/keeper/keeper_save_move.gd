class_name KeeperSaveMove
extends RefCounted

# A low save's body (KeeperSave picks it; KeeperMotor runs it): from whatever
# pose he is in when it cuts in — mid-push, mid-pivot, standing set, down —
# into the save's stance in the drop's time, held there while the shot is
# live, then gathered into the stance he rests in: the ready stance after a
# kick, the butterfly after anything down. Pure, stepped at the tick.
#
# Each leg goes the way a leg can. From its skate to its knee is the drop's
# way (KeeperDrop.blend_leg): the knee pinned the shortest way down and
# leading, the skate sliding out after it along the ice. A knee
# on the ice stays on it and slides along it; a skate on the ice slides on
# the ice. A drop is a fall, eased in and landing at speed; a kick and the
# gather are pushes, eased both ways.
#
# He carries the speed the save caught him at: on his feet his edges stop it
# as a standing stop does, down the pads' friction on the ice slides him on.
# Dropped on purpose while he glides (`edges` off), his edges stay out of it
# and the pads take it.

enum State { NONE, GOING, HELD, GATHERING }
# The low saves: the butterfly, the half butterfly (the pad on the puck's side
# down), the standing kick, the butterfly extension.
enum Low { NONE, BUTTERFLY, HALF, KICK, EXTENSION }

# Folding a pad back under him, or the kicking leg back to the stance: the
# butterfly push's load in reverse.
const GATHER_S: float = KeeperDrop.PUSH_LOAD_S
# A skate swept across the ice comes up off it in the middle of the sweep, by
# up to this, a tenth of how far it goes: dragged along it, the pad's rigid
# toe over the boot digs in.
const SWEEP_LIFT_M: float = 0.03

var drop_s: float = GoalieSkillProfile.hard().butterfly_drop_s
# The share of `drop_s` a fall into the save takes from the stance it cuts in
# from: less from the low ready (KeeperLowReady.fall_share). A kick is a push,
# in the drop's whole time.
var fall: float = 1.0
var pad_friction: float = 2.6
var edges: bool = true
var edge_decel: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2 * GameRules.GOALIE_EDGE_STOP_DECEL_RATIO

var state: int = State.NONE
var low: int = Low.NONE
var side: float = 1.0
# His place and the speed he carries, the stances' frame.
var x: float = 0.0
var z: float = 0.0
var velocity := Vector2.ZERO

var _clock: float = 0.0
var _from := KeeperPose.new()
var _to := KeeperPose.new()
var _now := KeeperPose.new()
var _knees: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _to_knees: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _skel := KeeperSkeleton.new()


# Cuts in from `from` (the pose he is in) at his place and speed.
func start(from: KeeperPose, p_low: int, p_side: float, at: Vector2, speed: Vector2) -> void:
	low = p_low
	side = p_side
	edges = true
	x = at.x
	z = at.y
	velocity = speed
	_set_from(from)
	match low:
		Low.BUTTERFLY:
			KeeperPoses.butterfly(_to)
		Low.HALF:
			KeeperPoses.half_butterfly(_to, side)
		Low.KICK:
			KeeperPoses.kick(_to, side)
		Low.EXTENSION:
			KeeperPoses.butterfly_extension(_to, side)
	_solve_to()
	state = State.GOING
	_clock = 0.0


# The shot is over: into the stance he rests in.
func release() -> void:
	if state == State.NONE or state == State.GATHERING:
		return
	pose(_now)
	_set_from(_now)
	if low == Low.KICK:
		KeeperPoses.ready(_to)
	else:
		KeeperPoses.butterfly(_to)
	_solve_to()
	state = State.GATHERING
	_clock = 0.0


# Whether he is in the save's stance, covering what it covers.
func is_set() -> bool:
	return state == State.HELD


func is_done() -> bool:
	return state == State.NONE


# Seconds until it lands in the save's stance; 0 once it has.
func left_s() -> float:
	if state != State.GOING:
		return 0.0
	return (1.0 - _clock) * drop_s * (fall if low != Low.KICK else 1.0)


# Down after it, or up after a kick.
func rests_down() -> bool:
	return low != Low.KICK


func step(dt: float) -> void:
	if state == State.NONE:
		return
	var down: bool = rests_down() and (state != State.GOING or _clock > 0.5)
	var brake: float = (pad_friction if down else (edge_decel if edges else 0.0)) * dt
	velocity = velocity.move_toward(Vector2.ZERO, brake)
	x += velocity.x * dt
	z += velocity.y * dt
	match state:
		State.GOING:
			_clock = minf(_clock + dt / (drop_s * (fall if low != Low.KICK else 1.0)), 1.0)
			if _clock >= 1.0:
				state = State.HELD
		State.GATHERING:
			_clock = minf(_clock + dt / GATHER_S, 1.0)
			if _clock >= 1.0 and velocity == Vector2.ZERO:
				state = State.NONE


func pose(p: KeeperPose) -> void:
	match state:
		State.GOING:
			var falls: bool = low != Low.KICK
			_blend(p, _clock * _clock if falls else smoothstep(0.0, 1.0, _clock))
		State.GATHERING:
			_blend(p, smoothstep(0.0, 1.0, _clock))
		_:
			p.copy_from(_to)


func _set_from(from: KeeperPose) -> void:
	_from.copy_from(from)
	_skel.pose(_from)
	for i: int in 2:
		_knees[i] = _skel.xf[KeeperSkeleton.SHIN[i]].origin


func _solve_to() -> void:
	_skel.pose(_to)
	for i: int in 2:
		_to_knees[i] = _skel.xf[KeeperSkeleton.SHIN[i]].origin


func _blend(p: KeeperPose, t: float) -> void:
	KeeperDrop.blend_body(p, _from, _to, t)
	p.blocker_reach = false
	for i: int in 2:
		var from: KeeperPose.Leg = _from.legs[i]
		var to: KeeperPose.Leg = _to.legs[i]
		var leg: KeeperPose.Leg = p.legs[i]
		var kneels: bool = from.foot_mode == KeeperPose.FootMode.FLAT \
				and to.foot_mode == KeeperPose.FootMode.ALONG_SHIN
		if to.knee_pinned and (not from.knee_pinned or kneels):
			# Off the skate onto the knee, from his feet or from a low stance on them.
			KeeperDrop.blend_leg(leg, from, _knees[i], to, t)
		elif to.knee_pinned:
			leg.copy_from(to)
			leg.knee = _knees[i].lerp(to.knee, t)
			leg.ankle = from.ankle.lerp(to.ankle, t)
			leg.thigh_front = from.thigh_front.lerp(to.thigh_front, t).normalized()
			leg.shin_front = from.shin_front.lerp(to.shin_front, t).normalized()
		elif from.knee_pinned:
			# Up out of a low stance (the low ready's) onto the skate.
			leg.copy_from(to)
			KeeperLowReady.sink_leg(leg, to, _to_knees[i], from, 1.0 - t, true)
			leg.knee_pinned = t < 1.0
		else:
			leg.copy_from(to)
			leg.ankle = from.ankle.lerp(to.ankle, t)
			leg.ankle.y += minf(SWEEP_LIFT_M, 0.1 * from.ankle.distance_to(to.ankle)) * sin(PI * t)
			leg.knee_pole = from.knee_pole.lerp(to.knee_pole, t).normalized()
			leg.shin_front = from.shin_front.lerp(to.shin_front, t).normalized()
			leg.toe = from.toe.lerp(to.toe, t).normalized()
