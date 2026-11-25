extends GutTest

# The live keeper against a carrier of theirs coming in at an angle up close
# and cutting across the top of the crease past him, or skating near straight
# across in front of him off the bottom of the circle. Per move, the carrier's
# body runs a quadratic curve from its start through its bend to its end at a
# skating pace, the puck carried ahead of the body along its way. Per tick, as
# the close-play probe measures it (`covered`: the share of the mouth a shot
# from the puck now can reach that a straight shot meets his gear in), and
# where his brain sends him: his zone, planted on the post, kept down, raced
# to it. The save share is shots released cold at points along the way, saves
# played out.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const Probe := preload("res://tests/instruments/keeper/test_close_play_probe.gd")

const DT: float = Stager.DT
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const HOLD_S: float = 0.6
const SHOT_M_S: float = 25.0
const PUCK_AHEAD_M: float = 0.45
const SHOT_EVERY_S: float = 0.1
# Shots go on after the move ends, the carrier held where it left him.
const HOLD_AFTER_S: float = 0.4
const LEGS: String = "legs"

var _s: RefCounted = null
var _h: RefCounted = null
var _p: Probe = null
var _ctrl: KeeperController = null
var _goalie: Goalie = null
var _puck: Puck = null
var _shooter: Skater = null
# ANGLE_CUT_WINDING: the carrier holds a wrister wound up the whole way, as a
# human can, skating with the shot loaded.
var _winding: bool = OS.get_environment("ANGLE_CUT_WINDING") != ""


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
	_p = Probe.new()
	_p._goalie = _goalie
	_p._ctrl = _ctrl


static func _ice(x: float, out: float) -> Vector3:
	return Vector3(x, 0.0, GOAL_Z + out)


# Each move: its name, its length in seconds, the body's start, bend and end
# as (x, out).
func _moves() -> Array:
	return [
		["hash, curl across 2.6", 0.9, Vector2(-3.6, 4.6), Vector2(-1.6, 2.4), Vector2(1.6, 2.6)],
		["dot-ish, curl across 2.2", 0.9, Vector2(-4.2, 3.6), Vector2(-1.8, 2.0), Vector2(1.4, 2.3)],
		["low, curl across 2.0", 0.8, Vector2(-3.8, 2.4), Vector2(-1.8, 1.8), Vector2(1.2, 2.0)],
		["slot angle, curl across 3", 1.0, Vector2(-3.0, 6.0), Vector2(-1.2, 3.0), Vector2(1.8, 2.8)],
		["angle at post, curl across", 0.9, Vector2(-3.6, 3.6), Vector2(-1.6, 1.4), Vector2(1.2, 2.0)],
		# Off the bottom of the faceoff circle, near straight across in front of
		# him, out of the corner: from the circle's low inside edge to the far
		# post's side.
		_lateral("circle, across 2.6 at 7", Vector2(-5.5, 2.6), Vector2(2.5, 2.2), 7.0),
		_lateral("circle, across 2.0 at 7", Vector2(-5.5, 2.0), Vector2(2.5, 1.8), 7.0),
		_lateral("circle, across 3.0 at 6", Vector2(-5.0, 3.0), Vector2(3.0, 2.6), 6.0),
		_lateral("circle, across 2.2 at 8", Vector2(-4.5, 2.2), Vector2(2.5, 2.0), 8.0),
		# Driven down at the near post from wide, then curled back up and out
		# above it, and held there: the post he sealed for the drive is no
		# longer where the shot comes from.
		["at the post, curl back out", 1.2, Vector2(-3.0, 3.0), Vector2(-1.0, -0.3), Vector2(-2.4, 2.2)],
		# Two straight legs: down the goal line at the post from the corner side,
		# to just outside it, and back up and out to above the dots' angle.
		["at the post, pull up and out", 1.0, Vector2(-4.0, 1.0), Vector2(-1.4, 0.35), Vector2(-2.4, 2.0), LEGS],
	]


# A straight move from `from` to `to` at `speed`.
static func _lateral(move_name: String, from: Vector2, to: Vector2, speed: float) -> Array:
	return [move_name, from.distance_to(to) / speed, from, (from + to) * 0.5, to]


# Before the move (t < 0) the carrier skates in along the curve's opening line
# at its opening speed, so he arrives at it already moving. A move marked LEGS
# is two straight legs at one pace, through its bend rather than toward it.
func _body_at(m: Array, t: float) -> Vector3:
	var a: Vector2 = m[2]
	var b: Vector2 = m[3]
	var c: Vector2 = m[4]
	if m.size() > 5 and m[5] == LEGS:
		var pace: float = (a.distance_to(b) + b.distance_to(c)) / float(m[1])
		var went: float = clampf(t * pace, -INF, a.distance_to(b) + b.distance_to(c))
		var q1: Vector2 = a + (b - a).normalized() * went if went <= a.distance_to(b) \
				else b + (c - b).normalized() * (went - a.distance_to(b))
		return _ice(q1.x, q1.y)
	if t < 0.0:
		var q0: Vector2 = a + (b - a) * 2.0 / float(m[1]) * t
		return _ice(q0.x, q0.y)
	var u: float = clampf(t / float(m[1]), 0.0, 1.0)
	var q: Vector2 = a.lerp(b, u).lerp(b.lerp(c, u), u)
	return _ice(q.x, q.y)


# The puck carried ahead of the body along its way; held where the way left it
# once the move is over.
func _puck_at(m: Array, t: float) -> Vector3:
	var body: Vector3 = _body_at(m, t)
	var along: float = minf(t, float(m[1]) - DT)
	var way: Vector3 = _body_at(m, along + DT) - _body_at(m, along)
	return body + way.normalized() * PUCK_AHEAD_M


func test_trace() -> void:
	var which: String = OS.get_environment("ANGLE_CUT_MOVE")
	var lines: PackedStringArray = []
	var moves: Array = _moves()
	for k: int in moves.size():
		if which != "" and not which.split(",").has(str(k)):
			continue
		lines.append(_track(moves[k]))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _track(m: Array) -> String:
	var rows: PackedStringArray = ["== %s" % m[0]]
	_stage(m)
	var ticks: int = int((float(m[1]) + HOLD_AFTER_S + 0.2) / DT)
	var was: Vector3 = _body_at(m, 0.0)
	var worst: float = 1.0
	for i: int in ticks:
		var t: float = (i + 1) * DT
		var body: Vector3 = _body_at(m, t)
		var puck: Vector3 = _puck_at(m, t)
		_carry(body, (body - was) / DT, puck)
		was = body
		var c: Vector2 = _p._covered(puck)
		worst = minf(worst, c.x)
		if OS.get_environment("ANGLE_CUT_EVERY") != "":
			var sl: KeeperSlide = _ctrl.motor.slide
			rows.append("   t %.3f mover %d slide phase %d rotating %s yaw %+.2f turning_to %+.2f at %+.2f,%+.2f goal %+.2f,%+.2f facing %+.2f" % [
					t, _ctrl.motor._mover, sl.phase, str(sl._rotating), _ctrl.motor.yaw, sl.turning_to(), _ctrl.motor.x,
					_ctrl.motor.z, _ctrl.motor.route.spot.x, _ctrl.motor.route.spot.y, _ctrl.motor.route.facing])
		if i % 3 == 0:
			var me: Vector3 = _ctrl._net.affine_inverse() * _goalie.global_position
			var pn: Vector3 = _ctrl._net.affine_inverse() * puck
			var pos: KeeperPositioning = _ctrl.brain
			rows.append("t %.2f puck %+.2f,%+.2f | him %+.2f,%+.2f rest %d mover %d goal %+.2f,%+.2f r%d | z%d pl%d kd%d post %+.0f | cov %.2f low %.2f" % [
					t, pn.x, pn.z, me.x, me.z, _ctrl.motor.rest, _ctrl.motor._mover,
					_ctrl.motor.route.spot.x, _ctrl.motor.route.spot.y, _ctrl.motor.route.rest,
					pos.zone, int(pos.planted), int(pos.kept_down), pos.post_side, c.x, c.y])
	rows.append("worst cov %.2f" % worst)
	return "\n".join(rows)


# Settled on the carrier where he starts skating in from, then skated in to the
# move's opening.
func _stage(m: Array) -> void:
	var ticks: int = int(HOLD_S / DT)
	_s._settle_on(_body_at(m, -ticks * DT))
	var was: Vector3 = _body_at(m, -(ticks + 1) * DT)
	for i: int in ticks:
		var t: float = (i - ticks) * DT
		var body: Vector3 = _body_at(m, t)
		_carry(body, (body - was) / DT, _puck_at(m, t))
		was = body


func _carry(body: Vector3, velocity: Vector3, puck: Vector3) -> void:
	_shooter.global_position = body
	_shooter.velocity = velocity
	_shooter.current_shot_state = SkaterStateMachine.State.WRISTER_AIM if _winding \
			else SkaterStateMachine.State.SKATING_WITH_PUCK
	if _puck.get_carrier() != _shooter:
		_puck.set_carrier(_shooter)
	_puck.global_position = Vector3(puck.x, _puck.ice_height, puck.z)
	_puck.linear_velocity = Vector3.ZERO
	_ctrl._physics_process(DT)


# Shots released cold at points along each move: the save share at each.
func test_saves_along_the_way() -> void:
	var which: String = OS.get_environment("ANGLE_CUT_MOVE")
	var lines: PackedStringArray = ["move                       | save share released every 0.1 s from 0.1 s"]
	var moves: Array = _moves()
	for k: int in moves.size():
		if which != "" and not which.split(",").has(str(k)):
			continue
		var m: Array = moves[k]
		var row: String = "%-26s |" % m[0]
		var t: float = 0.1
		var sum: float = 0.0
		var n: int = 0
		while t <= float(m[1]) + HOLD_AFTER_S + 1e-6:
			var share: float = _save_share(m, t)
			row += " %.2f" % share
			sum += share
			n += 1
			t += SHOT_EVERY_S
		lines.append(row + " | mean %.3f" % (sum / maxf(n, 1)))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _save_share(m: Array, until: float) -> float:
	var shots: int = 0
	var goals: int = 0
	for loft: int in Stager.LOFTS:
		for i: int in range(1, Stager.AIM_POINTS, 3):
			_stage(m)
			var t: float = 0.0
			var was: Vector3 = _body_at(m, 0.0)
			while t < until - 1e-6:
				t += DT
				var body: Vector3 = _body_at(m, t)
				_carry(body, (body - was) / DT, _puck_at(m, t))
				was = body
			var at: Vector3 = _puck_at(m, t)
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
