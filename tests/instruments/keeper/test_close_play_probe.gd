extends GutTest

# The live keeper against a carrier of theirs in tight, moving the puck: a
# dangle in place, a drag across his reach, a walk across the slot, a cut in
# toward the far post, a drive with a late pull. Per tick, against the puck
# where it is:
#   lag      — how far his angle from the net's centre is off the puck's, deg
#   covered  — the share of the mouth a straight shot from the puck now meets
#              his gear in (no reaction: the shape he presents), with the low
#              band (under 25 cm) apart
#   ideal    — the same, his pose set on the puck's angle line at his depth,
#              square to it: what is lost to where he is, not to his stance
# and for the drags, shots released at delays after the puck stops, saves
# played out, so a recovery shows as the save share coming back.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const DT: float = Stager.DT
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const GRID_M: float = 0.075
const LOW_BAND_M: float = 0.25
const HOLD_S: float = 0.6
const SHOT_M_S: float = 25.0
const DELAYS_S: Array[float] = [0.0, 0.1, 0.2, 0.35, 0.6]

var _s: RefCounted = null
var _h: RefCounted = null
var _ctrl: KeeperController = null
var _goalie: Goalie = null
var _puck: Puck = null
var _shooter: Skater = null
var _sw := SweptDiscOBB.Result.new()
var _ct := GoalieContactDetector.Contact.new()


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate() as Goalie
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_s = Stager.new(_goalie, _puck, _ctrl, _shooter)
	_h = _s._h


# A point `out` metres in front of the goal line, `x` across (the keeper's
# blocker side +, as the net sees it from the ice).
static func _ice(x: float, out: float) -> Vector3:
	return Vector3(x, 0.0, GOAL_Z + out)


# Each move: its length, and at `t` the carrier's body and the puck.
func _moves() -> Array:
	var tau: float = TAU
	return [
		["dangle 4 m", 2.0, func(t: float) -> Array:
			return [_ice(0.0, 4.0), _ice(0.25 + 0.55 * sin(tau * 1.6 * t), 4.0 - 0.3)]],
		["dangle 2.5 m", 2.0, func(t: float) -> Array:
			return [_ice(0.0, 2.5), _ice(0.25 + 0.55 * sin(tau * 1.6 * t), 2.5 - 0.3)]],
		["drag across 4 m", 1.2, func(t: float) -> Array:
			return [_ice(0.0, 4.0), _ice(lerpf(0.9, -0.9, clampf(t / 0.25, 0.0, 1.0)), 4.0 - 0.3)]],
		["drag across 2.5 m", 1.2, func(t: float) -> Array:
			return [_ice(0.0, 2.5), _ice(lerpf(0.9, -0.9, clampf(t / 0.25, 0.0, 1.0)), 2.5 - 0.3)]],
		["walk across 5 m", 1.6, func(t: float) -> Array:
			var bx: float = lerpf(-2.4, 2.4, t / 1.6)
			return [_ice(bx, 5.0), _ice(bx + 0.4, 4.7)]],
		["cut in to far post", 1.0, func(t: float) -> Array:
			var b: Vector3 = _ice(-2.0, 5.0).lerp(_ice(1.2, 1.6), t / 1.0)
			return [b, b + Vector3(0.4, 0.0, -0.3)]],
		["drive, pull at 3 m", 1.0, func(t: float) -> Array:
			var out: float = maxf(7.0 - 5.0 * t, 2.0)
			var px: float = 0.5 if out > 3.0 else lerpf(0.5, -0.8, clampf((3.0 - out) / 5.0 / 0.25, 0.0, 1.0))
			return [_ice(0.0, out), _ice(px, out - 0.3)]],
	]


func test_tracking() -> void:
	var lines: PackedStringArray = ["move                 | lag deg mean  max | covered mean  min  low | ideal mean  low"]
	for m: Array in _moves():
		lines.append(_track(m[0], m[1], m[2], false))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func test_trace_drag() -> void:
	var m: Array = _moves()[3]
	gut.p("\n" + _track(m[0], m[1], m[2], true))
	assert_true(true)


func _track(move_name: String, seconds: float, at: Callable, trace: bool) -> String:
	var lags: PackedFloat32Array = []
	var cov: PackedFloat32Array = []
	var low: PackedFloat32Array = []
	var ideal: PackedFloat32Array = []
	var ideal_low: PackedFloat32Array = []
	var rows: PackedStringArray = []
	_stage(at)
	var ticks: int = int(seconds / DT)
	var was: Vector3 = (at.call(0.0) as Array)[0]
	for i: int in ticks:
		var t: float = (i + 1) * DT
		var now: Array = at.call(t)
		_carry(now[0], (now[0] - was) / DT, now[1])
		was = now[0]
		var puck: Vector3 = now[1]
		var lag: float = _lag_deg(puck)
		var c: Vector2 = _covered(puck)
		var c_ideal: Vector2 = _covered_ideal(puck)
		lags.append(absf(lag))
		cov.append(c.x)
		low.append(c.y)
		ideal.append(c_ideal.x)
		ideal_low.append(c_ideal.y)
		if trace and i % 3 == 0:
			var me: Vector3 = _ctrl._net.affine_inverse() * _goalie.global_position
			var p: Vector3 = _ctrl._net.affine_inverse() * puck
			rows.append("t %.3f puck x %+.2f z %+.2f | him x %+.2f z %+.2f rest %d lowready %.2f | lag %+5.1f | cov %.2f low %.2f | ideal %.2f low %.2f" % [
					t, p.x, p.z, me.x, me.z, _ctrl.motor.rest, _ctrl.motor.low_ready.share,
					lag, c.x, c.y, c_ideal.x, c_ideal.y])
	var line: String = "%-20s | %6.1f %6.1f | %8.2f %5.2f %5.2f | %6.2f %5.2f" % [move_name, _mean(lags),
			_max(lags), _mean(cov), _min(cov), _mean(low), _mean(ideal), _mean(ideal_low)]
	if trace:
		return line + "\n" + "\n".join(rows)
	return line


# Settled on the move's opening: skated in to it, then held there.
func _stage(at: Callable) -> void:
	var first: Array = at.call(0.0)
	_s._settle_on(first[0])
	for _i: int in int(HOLD_S / DT):
		_carry(first[0], Vector3.ZERO, first[1])


func _carry(body: Vector3, velocity: Vector3, puck: Vector3) -> void:
	_shooter.global_position = body
	_shooter.velocity = velocity
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	if _puck.get_carrier() != _shooter:
		_puck.set_carrier(_shooter)
	_puck.global_position = Vector3(puck.x, _puck.ice_height, puck.z)
	_puck.linear_velocity = Vector3.ZERO
	_ctrl._physics_process(DT)


# His angle from the net's centre less the puck's, degrees.
func _lag_deg(puck: Vector3) -> float:
	var me: Vector3 = _ctrl._net.affine_inverse() * _goalie.global_position
	var p: Vector3 = _ctrl._net.affine_inverse() * puck
	return rad_to_deg(angle_difference(atan2(p.x, -p.z), atan2(me.x, -me.z)))


# The share of the mouth, and of its low band, a straight shot from `puck`
# meets him in.
func _covered(puck: Vector3) -> Vector2:
	var from := Vector3(puck.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, puck.z)
	var r: float = GameRules.PUCK_COLLISION_RADIUS
	var half_w: float = GameRules.NET_HALF_WIDTH - GameRules.NET_POST_RADIUS - r
	var top: float = GameRules.NET_HEIGHT - GameRules.NET_POST_RADIUS - r
	var hit: int = 0
	var all: int = 0
	var low_hit: int = 0
	var low_all: int = 0
	var x: float = -half_w
	while x <= half_w + 1e-6:
		var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
		while y <= top + 1e-6:
			var met: bool = GoalieContactDetector.nearest([_goalie], from, Vector3(x, y, GOAL_Z), r, _sw, _ct)
			all += 1
			hit += 1 if met else 0
			if y < LOW_BAND_M:
				low_all += 1
				low_hit += 1 if met else 0
			y += GRID_M
		x += GRID_M
	return Vector2(float(hit) / all, float(low_hit) / maxf(low_all, 1))


# `_covered` with his body as it is, set on the puck's angle line at his
# depth, square to the puck.
func _covered_ideal(puck: Vector3) -> Vector2:
	var real: Transform3D = _goalie.global_transform
	var me: Vector3 = _ctrl._net.affine_inverse() * real.origin
	var p: Vector3 = _ctrl._net.affine_inverse() * puck
	var depth: float = Vector2(me.x, me.z).length()
	var on: Vector2 = Vector2(p.x, p.z).normalized() * depth
	var yaw: float = KeeperPositioning.facing(on, Vector2(p.x, p.z))
	_goalie.global_transform = _ctrl._net * Transform3D(Basis(Vector3.UP, yaw), Vector3(on.x, 0.0, on.y))
	var c: Vector2 = _covered(puck)
	_goalie.global_transform = real
	return c


func _mean(a: PackedFloat32Array) -> float:
	var s: float = 0.0
	for v: float in a:
		s += v
	return s / maxf(a.size(), 1)


func _max(a: PackedFloat32Array) -> float:
	var m: float = -INF
	for v: float in a:
		m = maxf(m, v)
	return m


func _min(a: PackedFloat32Array) -> float:
	var m: float = INF
	for v: float in a:
		m = minf(m, v)
	return m


# Shots off the drags, released `DELAYS_S` after the puck stops on the far
# side, saves played out: the save share by delay, with a straight shot from
# the same spot off a settled carrier for scale.
func test_shots_after_a_drag() -> void:
	var lines: PackedStringArray = ["move                 | settled | after the drag stops, by delay s"]
	var head: String = "                     |         |"
	for d: float in DELAYS_S:
		head += " %5.2f" % d
	lines.append(head)
	for k: int in [2, 3]:
		var m: Array = _moves()[k]
		var at: Callable = m[2]
		var stop: float = 0.25
		var end: Array = at.call(stop)
		var row: String = "%-20s | %6.2f  |" % [m[0], _save_share(func() -> Vector3:
				_s._settle_on(end[0])
				for _i: int in int(HOLD_S / DT):
					_carry(end[0], Vector3.ZERO, end[1])
				return end[1])]
		for delay: float in DELAYS_S:
			row += " %5.2f" % _save_share(func() -> Vector3:
					_stage(at)
					var t: float = 0.0
					while t < stop + delay - 1e-6:
						t += DT
						var now: Array = at.call(t)
						_carry(now[0], Vector3.ZERO, now[1])
					return (at.call(t) as Array)[1])
		lines.append(row)
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


# The share of shots on net he keeps out, released cold from what `stage`
# leaves, over every lift and every third aim post to post.
func _save_share(stage: Callable) -> float:
	var shots: int = 0
	var goals: int = 0
	for loft: int in Stager.LOFTS:
		for i: int in range(1, Stager.AIM_POINTS, 3):
			var at: Vector3 = stage.call()
			var aim := Vector3(Stager.aim_x(i), 0.0, GOAL_Z)
			var vel: Vector3 = _h.shot_velocity_at(at, aim, loft, SHOT_M_S, 0.0)
			_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
			_puck.clear_carrier()
			_puck.global_position = Vector3(at.x, _puck.ice_height, at.z)
			_puck.apply_release_velocity(vel)
			_puck.puck_released.emit()
			var r: int = _h.fire_tracking_rebound(at, aim, loft, SHOT_M_S, 0.0)
			if _h.last_part < 0 and r != Harness.GOAL:
				continue
			shots += 1
			if r == Harness.GOAL or _h.rebound_goal:
				goals += 1
	return 1.0 - float(goals) / maxf(shots, 1)
