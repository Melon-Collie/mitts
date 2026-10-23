class_name KeeperFootwork
extends RefCounted

# His skates while he moves, and the stance they bend: across his line by the
# T-push or the shuffle, in and out by C-cuts, each ended by an edge stop onto
# the spot. Pure, stepped at the tick.
#
# The kinematics are GoaliePushRules', at the move's own top speed: a skate's
# edge accelerates him, and edges brake him onto his spot.
#
# The T-push's push is the acceleration: the trail skate is planted for it and
# the body drives off it, the leg extending as he goes, which is why a push is
# about a leg's extension long (0.27 s to 3.8 m/s covers 0.52 m).
#   PUSH   the lead skate turns toward the travel, its pad part of the way
#          with it; the trail skate stays where it was set down until the leg
#          is out straight, the hips sinking a little to reach it
#   GLIDE  he rides the lead skate; the trail leg lifts and draws back in
# The shuffle and the C-cuts are strokes laid over the ground, and he strokes
# (PUSH) until he stops. In each, a skate's edge holds its place while the body
# passes over it, then the skate comes back in under him:
#   shuffle  square, both skates on the ice; the trail skate pushes and slides
#            back in while the lead one carries him
#   C-cut    the skates take turns: one carves a C, out to the side and away
#            from the travel as it holds, its heel turned out (its toe in going
#            back, out going forward), then back in under him, lifted; the
#            other carries him straight
#   STOP   edges dig (a lateral move's lead skate, squaring back from a T-push;
#          both skates in a C-cut), the pushing leg comes in under him, and he
#          leans back against the momentum, as far as the speed he stops from
#          asks
#   SET    the ready stance, once the stop has settled out of his body
#
# Places are in the stances' frame: x across his line (+ toward his blocker
# side), z his depth (+ back toward his net). A right-catcher's moves are read
# through KeeperSkeleton.world_side like his stances'. The shuffle goes along
# his line and the C-cuts in depth; the T-push goes straight to its spot, square
# to the shooter, on a diagonal up to DIAGONAL_MAX_RAD off his line. A move goes
# on along the line it set out on: a spot off it is taken where it falls on it,
# the rest once he is set.

enum Phase { SET, PUSH, GLIDE, STOP }
enum Move { T_PUSH, SHUFFLE, C_CUT }

# How far round toward the travel the T-push's lead skate turns at its fullest
# (from the ready stance's toe-out to along the travel), and how much of that
# turn his pad's face follows: a real T-push turns the lead pad off the shooter.
const LEAD_TURN: float = 1.0
const LEAD_PAD_FOLLOW: float = 0.5
# How far off his line a T-push goes, forward or back; a spot further off is
# pushed to where it falls on his line.
const DIAGONAL_MAX_RAD: float = deg_to_rad(45.0)
# How long the lead skate takes to turn in, and the lean into the move to come
# on or go; a pushing leg to come back in once its push is over; and the stop
# to leave his body once he is on his spot.
const TURN_IN_S: float = 0.08
const RECOVER_S: float = 0.18
const SETTLE_S: float = 0.15
# A skate coming back in lifts clear by up to this, the most once it has
# LIFT_FULL_AT_M to come; a skate barely out slides in on the ice.
const RECOVER_LIFT_M: float = 0.03
const LIFT_FULL_AT_M: float = 0.2
# The shuffle's stroke: the body travel per stroke, and how much of it the
# trail skate holds its place for.
const SHUFFLE_STROKE_M: float = 0.45
const SHUFFLE_PUSH_OUT_M: float = 0.14
# A C-cut's stroke: the body travel per stroke, and the part of it the cutting
# skate carves for; how far it holds its place along the travel; how wide the
# C swings out; and how far its heel turns out at the C's widest. Going back,
# the skate carves out in front of him. Going forward it can hold barely
# behind the stance before the shin pitches the pad's rigid toe into the ice,
# so the forward C is driven out to the side instead.
const C_CUT_STROKE_M: float = 0.5
const C_CUT_CARVE_M: float = 0.25
const C_CUT_HOLD_BACK_M: float = 0.25
const C_CUT_HOLD_FORWARD_M: float = 0.04
const C_CUT_OUT_BACK_M: float = 0.12
const C_CUT_OUT_FORWARD_M: float = 0.18
const C_CUT_HEEL_OUT_RAD: float = deg_to_rad(35.0)
# How far under the stop's brake his speed must have fallen before a spot
# moved on ahead of him is pushed for again, rather than eased into.
const RESUME_SHARE: float = 0.9
# The edges in the stop: a lateral move's lead skate out a little wider, rolled
# onto its inside edge; and the lean, into the move and back against the stop.
# The stop's are at full from a T-push's top speed and in proportion below it.
const STOP_LEAD_OUT_M: float = 0.05
const STOP_EDGE_RAD: float = deg_to_rad(12.0)
const PUSH_LEAN_RAD: float = deg_to_rad(5.0)
const SHUFFLE_LEAN_RAD: float = deg_to_rad(2.0)
const C_CUT_LEAN_RAD: float = deg_to_rad(3.0)
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
var c_cut_speed: float = GameRules.DEFAULT_GOALIE_DEPTH_SPEED_M_S
var accel: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2

# Where he is (m) and how fast he is going toward his spot (negative while a
# retarget still carries him the other way).
var x: float = 0.0
var z: float = 0.0
var speed: float = 0.0
var phase: int = Phase.SET
var move: int = Move.T_PUSH

# His spot, and the line he is going along: where it starts, its way, how far
# along it he is and his spot is; and the way he is going along the move's own
# axis (across his line, or in depth for a C-cut). Places held as floats, as
# x and z are, so he lands on a spot exactly.
var _target_x: float = 0.0
var _target_z: float = 0.0
var _start_x: float = 0.0
var _start_z: float = 0.0
var _dir := Vector2.RIGHT
var _along: float = 0.0
var _to: float = 0.0
var _side: float = 1.0
# How far he has come since the move started (the strokes are laid over it),
# and how far along his line the T-push's trail skate holds its plant.
var _travel: float = 0.0
var _plant_reach: float = 0.0
# How far along his line the push under way started.
var _push_from: float = 0.0
# The leg pushing, and where its skate was against its place in the stance,
# and how far its heel was turned out, when its push ended; and how far back
# in it is since.
var _leg: int = 0
var _from := Vector3.ZERO
var _heel_from: float = 0.0
var _recover: float = 1.0
# How far the lead skate is turned in, how far the lean into the move is on,
# and how far into the stop he is (held once he is set, and let go over
# SETTLE_S) and how hard a stop it is.
var _turn: float = 0.0
var _turn_from: float = 0.0
var _drive: float = 0.0
var _stop: float = 0.0
var _stop_from_speed: float = 0.0


# T-push to `spot`.
func push_to(spot: Vector2) -> void:
	_go(spot.x, spot.y, Move.T_PUSH)


# Shuffle to `target` across his line.
func shuffle_to(target: float) -> void:
	_go(target, z, Move.SHUFFLE)


# C-cut to depth `target`.
func c_cut_to(target: float) -> void:
	_go(x, target, Move.C_CUT)


# From the set stance `kind` starts; a new spot ahead mid-move retargets the
# move under way (pushed for again from a stop, once the push leg is back under
# him, if it is far enough on to want it), and one behind him pushes off the
# edge he is riding, the way he was going carried into it. The stop's lean
# eases out of a move started under it rather than dropping.
func _go(to_x: float, to_z: float, kind: int) -> void:
	if phase != Phase.SET:
		if _depth(kind) != _depth(move):
			return
		_to = (to_x - _start_x) * _dir.x + (to_z - _start_z) * _dir.y
		if _dir.x != 0.0:
			_target_x = _start_x + _dir.x * _to
		if _dir.y != 0.0:
			_target_z = _start_z + _dir.y * _to
		if _to >= _along or absf(_to - _along) < 1e-4:
			return
		speed = -speed
		_begin(-_dir, kind)
		return
	if kind == Move.T_PUSH and absf(to_z - z) > absf(to_x - x) * tan(DIAGONAL_MAX_RAD):
		to_z = z
	var way := Vector2(to_x - x, to_z - z)
	if way.length() < 1e-4:
		return
	_target_x = to_x
	_target_z = to_z
	_begin(way.normalized(), kind)


func _begin(dir: Vector2, kind: int) -> void:
	move = kind
	_start_x = x
	_start_z = z
	_dir = dir
	_along = 0.0
	_to = (_target_x - x) * dir.x + (_target_z - z) * dir.y
	_side = signf(dir.y if _depth(kind) else dir.x)
	_plant_reach = _trail_reach(dir)
	_push_from = 0.0
	_travel = 0.0
	_from = Vector3.ZERO
	_heel_from = 0.0
	_recover = 1.0
	_turn = 0.0
	phase = Phase.PUSH


# How far `spot` lies off the line the move under way (or the last) runs along.
func off_line(spot: Vector2) -> float:
	return absf((spot.x - _start_x) * _dir.y - (spot.y - _start_z) * _dir.x)


static func _depth(kind: int) -> bool:
	return kind == Move.C_CUT


# Set on his spot with the move settled out of him: in the ready stance.
func is_settled() -> bool:
	return phase == Phase.SET and _stop <= 0.0 and _recover >= 1.0 and _turn <= 0.0


# Set on his spot with the push leg back under him: the next footwork can start
# while the stop settles.
func is_recovered() -> bool:
	return phase == Phase.SET and _recover >= 1.0


func top_speed() -> float:
	match move:
		Move.SHUFFLE:
			return shuffle_speed
		Move.C_CUT:
			return c_cut_speed
	return t_push_speed


func step(dt: float) -> void:
	_drive = move_toward(_drive, 1.0 if phase == Phase.PUSH else 0.0, dt / TURN_IN_S)
	if phase == Phase.SET:
		_recover = minf(_recover + dt / RECOVER_S, 1.0)
		_stop = maxf(_stop - dt / SETTLE_S, 0.0)
		_turn = maxf(_turn - dt / TURN_IN_S, 0.0)
		return
	var left: float = _to - _along
	# The stop starts the tick it would be too late to after this one's travel.
	var next_left: float = left - maxf(speed, 0.0) * dt
	if phase == Phase.STOP and _recover >= 1.0 \
			and speed < RESUME_SHARE * GoaliePushRules.braking_speed_cap(next_left, accel):
		phase = Phase.PUSH
		_push_from = _along
		# A fresh stroke, its skate starting from under him.
		var stroke: float = _stroke_m()
		if stroke > 0.0:
			_travel = ceilf(_travel / stroke) * stroke
	if phase != Phase.STOP and speed > 0.0 \
			and speed >= GoaliePushRules.braking_speed_cap(next_left, accel):
		_end_push()
		phase = Phase.STOP
		_stop_from_speed = speed
	var was: float = speed
	match phase:
		Phase.PUSH:
			_stop = maxf(_stop - dt / SETTLE_S, 0.0)
			speed = minf(speed + accel * dt, top_speed())
			if move == Move.T_PUSH:
				_turn = minf(_turn + dt / TURN_IN_S, 1.0)
				if speed >= top_speed():
					_end_push()
					phase = Phase.GLIDE
		Phase.GLIDE:
			_stop = maxf(_stop - dt / SETTLE_S, 0.0)
			_recover = minf(_recover + dt / RECOVER_S, 1.0)
		Phase.STOP:
			# The edges dig as hard as it takes to stop on the spot, which from
			# the tick the stop starts is their brake.
			speed = maxf(speed - speed * speed / (2.0 * maxf(left, 1e-6)) * dt, 0.0)
			_recover = minf(_recover + dt / RECOVER_S, 1.0)
			# Into his body no faster than the lead skate turns in, however
			# short the stop (one cut short by a spot pulled back is over in a
			# few ticks), and out of it no faster than it settles, where the
			# last move's was still settling.
			_stop = clampf(1.0 - speed / maxf(_stop_from_speed, 1e-6), _stop - dt / SETTLE_S,
					_stop + dt / TURN_IN_S)
	var travelled: float = 0.5 * (was + speed) * dt
	_along += travelled
	_travel += absf(travelled)
	if _to - _along <= 0.0 or (phase == Phase.STOP and speed <= 1e-4):
		x = _target_x
		z = _target_z
		_along = _to
		speed = 0.0
		phase = Phase.SET
		return
	x = _start_x + _dir.x * _along
	z = _start_z + _dir.y * _along


func _end_push() -> void:
	if phase == Phase.PUSH:
		_leg = _pushing_leg()
		_from = _pushing_skate()
		_heel_from = _pushing_heel()
		_turn_from = _turn
		_recover = 0.0


# The body travel a stroke takes: the shuffle's and the C-cut's; the T-push is
# one push.
func _stroke_m() -> float:
	match move:
		Move.SHUFFLE:
			return SHUFFLE_STROKE_M
		Move.C_CUT:
			return C_CUT_STROKE_M
	return 0.0


# The leg pushing: a lateral move's trail leg, a C-cut's leg taking its turn.
func _pushing_leg() -> int:
	if move == Move.C_CUT:
		return int(_travel / C_CUT_STROKE_M) % 2
	return 0 if _side > 0.0 else 1


# The pushing skate against its place in the stance, lifted as it comes back.
func _pushing_skate() -> Vector3:
	match move:
		Move.SHUFFLE:
			var d: float = fposmod(_travel, SHUFFLE_STROKE_M)
			var out := Vector3(-_side * SHUFFLE_PUSH_OUT_M, 0.0, 0.0)
			if d < SHUFFLE_PUSH_OUT_M:
				return out * d / SHUFFLE_PUSH_OUT_M
			return _coming_in(out, _stroke_back(d, SHUFFLE_PUSH_OUT_M, SHUFFLE_STROKE_M))
		Move.C_CUT:
			var d: float = fposmod(_travel, C_CUT_STROKE_M)
			var sx: float = _leg_x(_pushing_leg())
			var back: bool = _side > 0.0
			var hold: float = C_CUT_HOLD_BACK_M if back else C_CUT_HOLD_FORWARD_M
			var c := Vector3(sx * (C_CUT_OUT_BACK_M if back else C_CUT_OUT_FORWARD_M), 0.0, -_side * hold)
			if d < C_CUT_CARVE_M:
				var u: float = d / C_CUT_CARVE_M
				return Vector3(c.x * sin(0.5 * PI * u), 0.0, -_side * minf(d, hold))
			return _coming_in(c, _stroke_back(d, C_CUT_CARVE_M, C_CUT_STROKE_M))
	# The T-push's: on its plant until the leg is out as far as it goes, then
	# dragged with him.
	var behind: Vector2 = -_dir * minf(_along - _push_from, _plant_reach)
	return Vector3(behind.x, 0.0, behind.y)


# How far a skate's heel is turned out from the stance while it pushes: a
# C-cut's, at the C's widest.
func _pushing_heel() -> float:
	if move != Move.C_CUT:
		return 0.0
	var d: float = fposmod(_travel, C_CUT_STROKE_M)
	if d < C_CUT_CARVE_M:
		return C_CUT_HEEL_OUT_RAD * sin(PI * 0.5 * d / C_CUT_CARVE_M)
	return C_CUT_HEEL_OUT_RAD * (1.0 - smoothstep(0.0, 1.0, _stroke_back(d, C_CUT_CARVE_M, C_CUT_STROKE_M)))


# How far back in a stroke's skate is, 0 to 1, `d` into a stroke `stroke` long
# whose skate holds for `hold`; 0 while it holds.
static func _stroke_back(d: float, hold: float, stroke: float) -> float:
	return maxf(d - hold, 0.0) / (stroke - hold)


# A skate `back` (0 to 1) of the way in from `out` against its place, lifted.
static func _coming_in(out: Vector3, back: float) -> Vector3:
	var at: Vector3 = out * (1.0 - smoothstep(0.0, 1.0, back))
	at.y = RECOVER_LIFT_M * clampf(out.length() / LIFT_FULL_AT_M, 0.0, 1.0) * sin(PI * back)
	return at


# How far he goes along `dir` over a T-push's trail skate, set down where it
# stands in the ready stance, before the leg driving off it is out as far as it
# reaches from hips sunk MAX_PUSH_SINK_M.
static func _trail_reach(dir: Vector2) -> float:
	var s: float = -1.0 if dir.x < 0.0 else 1.0
	var pelvis: Vector3 = KeeperPoses.READY_PELVIS
	var up: float = pelvis.y - MAX_PUSH_SINK_M - KeeperAnatomy.ANKLE_ON_SKATES_M
	var reach_sq: float = _TRAIL_REACH_M * _TRAIL_REACH_M - up * up
	# The skate from the hip over it, on the ice.
	var skate := Vector2(-s * (KeeperPoses.READY_SKATE_HALF_SPACING_M - KeeperAnatomy.HIP_HALF_SPACING_M),
			-pelvis.z)
	var ahead: float = skate.dot(dir)
	return ahead + sqrt(maxf(ahead * ahead - skate.length_squared() + reach_sq, 0.0))


static func _leg_x(leg: int) -> float:
	return -1.0 if leg == 0 else 1.0


# His pose this tick, relative to where he is: the ready stance, bent by the
# move.
func pose(p: KeeperPose) -> void:
	KeeperPoses.ready(p)
	if is_settled():
		return
	var stop: float = _stop * clampf(_stop_from_speed / t_push_speed, 0.0, 1.0)
	if _depth(move):
		_bend_for_depth(p, stop)
	else:
		_bend_for_lateral(p, stop)
	# The pushing leg: pushing, then coming back in.
	var leg: int = _pushing_leg() if phase == Phase.PUSH else _leg
	var pushing: KeeperPose.Leg = p.legs[leg]
	var sx: float = _leg_x(leg)
	var skate: Vector3
	var heel: float
	var back: float = 0.0
	if phase == Phase.PUSH:
		skate = _pushing_skate()
		heel = _pushing_heel()
	else:
		back = smoothstep(0.0, 1.0, _recover)
		skate = _from.lerp(Vector3.ZERO, back)
		# A skate already lifted when its push ended comes down from there; the
		# lift a skate starting in from the ice takes is never added on top.
		skate.y = maxf(_from.y * (1.0 - back), RECOVER_LIFT_M
				* clampf(Vector2(_from.x, _from.z).length() / LIFT_FULL_AT_M, 0.0, 1.0) * sin(PI * _recover))
		heel = _heel_from * (1.0 - back)
	pushing.ankle += skate
	if heel != 0.0:
		var toe_out: float = KeeperPoses.READY_TOE_OUT_RAD - _side * heel
		pushing.toe = Vector3(sx * sin(toe_out), 0.0, -cos(toe_out))
	# The T-push's hips sink with its leg's drive out to the side; every move's
	# sink as far as the leg needs to reach its skate.
	var out: float = clampf(skate.x * sx / _trail_reach(Vector2.RIGHT), 0.0, 1.0)
	if move == Move.T_PUSH:
		out = clampf(-(skate.x * _dir.x + skate.z * _dir.y) / _plant_reach, 0.0, 1.0)
		p.pelvis.y -= MAX_PUSH_SINK_M * smoothstep(0.0, 1.0, out)
	# The leg's knee comes out of the stance's knee-in to drive over its skate,
	# or the pad's outer corner is driven into the ice.
	var drive := Vector3(sx * PUSH_KNEE_OUT, 0.0, -1.0)
	if move == Move.T_PUSH and _dir.y < 0.0:
		# Going forward on a diagonal, the push leg reaches out behind him: it
		# drives square to the diagonal, its skate turned with it, or the shin
		# pitches the pad's face into the ice. Out in front, the face tips up.
		var turned: float = _turn if phase == Phase.PUSH else _turn_from * (1.0 - back)
		var square_to: float = atan2(-_dir.y * _side, _dir.x * _side) * turned
		drive = drive.rotated(Vector3.UP, square_to)
		pushing.toe = pushing.toe.rotated(Vector3.UP, square_to)
	var driven: float = smoothstep(0.0, PUSH_KNEE_DRIVEN_AT, out)
	pushing.knee_pole = pushing.knee_pole.lerp(drive, driven)
	pushing.shin_front = pushing.shin_front.lerp(drive, driven)
	var across: float = pushing.ankle.x - sx * KeeperAnatomy.HIP_HALF_SPACING_M
	var ahead: float = pushing.ankle.z - p.pelvis.z
	var up: float = sqrt(maxf(_TRAIL_REACH_M * _TRAIL_REACH_M - across * across - ahead * ahead, 0.0))
	p.pelvis.y = minf(p.pelvis.y, pushing.ankle.y + up)


# Across his line: the lead skate turned toward the travel and squared back in
# the stop, its edge dug; the lean into the move and back against the stop.
func _bend_for_lateral(p: KeeperPose, stop: float) -> void:
	var s: float = _side
	var way := Vector3(_dir.x, 0.0, _dir.y)
	var lead: KeeperPose.Leg = p.legs[1 if s > 0.0 else 0]
	var turn: float = _turn * (1.0 - _stop)
	lead.toe = lead.toe.slerp(way, LEAD_TURN * turn)
	var pad_turn: float = KeeperPoses.ready_toe(s).signed_angle_to(lead.toe, Vector3.UP) \
			* LEAD_PAD_FOLLOW
	lead.shin_front = lead.shin_front.rotated(Vector3.UP, pad_turn)
	lead.knee_pole = lead.knee_pole.rotated(Vector3.UP, pad_turn)
	var dug: float = _edges_dug(stop)
	lead.ankle.x += s * STOP_LEAD_OUT_M * dug
	lead.shin_front = lead.shin_front.rotated(Vector3.FORWARD, -s * STOP_EDGE_RAD * dug)
	var lean: float = PUSH_LEAN_RAD if move == Move.T_PUSH else SHUFFLE_LEAN_RAD
	p.lumbar_rot.z -= _dir.x * (lean * _drive - STOP_LEAN_RAD * stop)
	# The stop's lean back against a diagonal stays across his line: leaned
	# back as well, his blocker shoulder lifts off the stick.
	p.lumbar_rot.x += _dir.y * lean * _drive


# How far the stop's edges are still dug: as far as the stop is, until the
# next move's push drives them out. Its lean eases out with the stop alone.
func _edges_dug(stop: float) -> float:
	return stop * (1.0 - _drive) if phase == Phase.PUSH else stop


# In and out: both skates' edges dug in the stop, a little wider; the lean
# toward the travel as he drives and back against it as he stops.
func _bend_for_depth(p: KeeperPose, stop: float) -> void:
	var dug: float = _edges_dug(stop)
	for leg: int in 2:
		var sx: float = _leg_x(leg)
		p.legs[leg].ankle.x += sx * 0.5 * STOP_LEAD_OUT_M * dug
		p.legs[leg].shin_front = p.legs[leg].shin_front.rotated(Vector3.FORWARD,
				-sx * STOP_EDGE_RAD * dug)
	p.lumbar_rot.x += _side * (C_CUT_LEAN_RAD * _drive - STOP_LEAN_RAD * stop)
