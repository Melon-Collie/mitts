extends GutTest

# The live keeper against a carrier of theirs driving straight at him and
# deking: the puck pulled forehand to backhand or back, twice, a shot faked and
# pulled, a walk wide round him, a stop. The carrier comes in at rush pace from
# well out, already skating, and starts the move `from` metres out. Per move,
# where the keeper is as the move starts (how far out, on his feet or down) and
# as it ends, and the save share on shots released cold at delays after it
# ends, every lift and every third aim post to post, saves played out; the
# same drive shot straight, without the move, for scale.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const DT: float = Stager.DT
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const SHOT_M_S: float = 25.0
const DRIVE_M_S: float = 7.5
const START_M: float = 14.0
const PULL_S: float = 0.25
const DELAYS_S: Array[float] = [0.0, 0.1, 0.2]
const FROMS_M: Array[float] = [6.0, 4.5]

var _s: RefCounted = null
var _h: RefCounted = null
var _ctrl: KeeperController = null
var _goalie: Goalie = null
var _puck: Puck = null
var _shooter: Skater = null


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


static func _ice(x: float, out: float) -> Vector3:
	return Vector3(x, 0.0, GOAL_Z + out)


# The carrier at `t` seconds after his move starts (negative before it): his
# body, the puck, and whether he holds it wound up to shoot. Before the move he
# drives straight in down the middle, the puck on his forehand.
static func _at(move: String, from: float, t: float) -> Array:
	var out: float = from - DRIVE_M_S * t
	var bx: float = 0.0
	var px: float = 0.35
	var winding: bool = false
	if t <= 0.0:
		return [_ice(bx, out), _ice(px, out - 0.3), false]
	var pull: float = smoothstep(0.0, PULL_S, t)
	match move:
		"straight":
			pass
		"fore to back":
			out = from - DRIVE_M_S * 0.85 * t
			px = lerpf(0.35, -0.9, pull)
			bx = -0.3 * pull
		"back to fore":
			px = lerpf(-0.35, 0.9, pull) if t > 0.0 else -0.35
			out = from - DRIVE_M_S * 0.85 * t
			bx = 0.3 * pull
		"double":
			out = from - DRIVE_M_S * 0.8 * t
			px = lerpf(0.35, -0.8, smoothstep(0.0, 0.2, t)) + 1.7 * smoothstep(0.2, 0.4, t)
			bx = -0.2 * smoothstep(0.0, 0.2, t) + 0.4 * smoothstep(0.2, 0.4, t)
		"fake, pull":
			out = from - DRIVE_M_S * 0.8 * t
			winding = t < 0.2
			px = lerpf(0.35, -0.9, smoothstep(0.2, 0.2 + PULL_S, t))
			bx = -0.3 * smoothstep(0.2, 0.2 + PULL_S, t)
		"walk wide":
			var cut: float = smoothstep(0.0, 0.6, t)
			out = from - (DRIVE_M_S * t - 0.5 * 6.0 * minf(t, 0.6) * minf(t, 0.6))
			bx = -2.2 * cut
			px = bx - 0.45 * cut + 0.35 * (1.0 - cut)
		"stop":
			var stops: float = DRIVE_M_S / GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2
			var tt: float = minf(t, stops)
			out = from - (DRIVE_M_S * tt - 0.5 * GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2 * tt * tt)
	return [_ice(bx, out), _ice(px, out - 0.3), winding]


static func _move_s(move: String) -> float:
	match move:
		"double":
			return 0.4
		"fake, pull":
			return 0.2 + PULL_S
		"walk wide":
			return 0.6
		"stop":
			return DRIVE_M_S / GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2
	return PULL_S


const MOVES: Array[String] = ["straight", "fore to back", "back to fore", "double", "fake, pull", "walk wide", "stop"]


func test_drive_deke() -> void:
	var which: String = OS.get_environment("DRIVE_DEKE_MOVES")
	var lines: PackedStringArray = ["move          from | at move: out  rest | at end: out rest |   saves by delay after the move"]
	var head: String = "                   |                   |                  |"
	for d: float in DELAYS_S:
		head += "  %4.2f" % d
	lines.append(head + " | mean")
	for move: String in MOVES:
		if which != "" and not which.split(",").has(move):
			continue
		for from: float in FROMS_M:
			var at_move: Vector2 = _run(move, from, 0.0)
			var at_end: Vector2 = _run(move, from, _move_s(move))
			var row: String = "%-13s %4.1f | %8.2f  %s | %7.2f  %s |" % [move, from, at_move.x,
					"down" if at_move.y > 0.5 else "feet", at_end.x, "down" if at_end.y > 0.5 else "feet"]
			var sum: float = 0.0
			for d: float in DELAYS_S:
				var share: float = _save_share(move, from, _move_s(move) + d)
				sum += share
				row += "  %4.2f" % share
			lines.append(row + " | %.2f" % (sum / DELAYS_S.size()))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


# Traces one move tick by tick: DRIVE_DEKE_TRACE="<move>@<from>".
func test_trace() -> void:
	var spec: String = OS.get_environment("DRIVE_DEKE_TRACE")
	if spec == "":
		assert_true(true)
		return
	var parts: PackedStringArray = spec.split("@")
	var move: String = parts[0]
	var from: float = float(parts[1])
	var rows: PackedStringArray = ["== %s from %.1f" % [move, from]]
	var t: float = -(START_M - from) / DRIVE_M_S
	_s._settle_on((_at(move, from, t) as Array)[0])
	var was: Vector3 = (_at(move, from, t - DT) as Array)[0]
	var i: int = 0
	while t < _move_s(move) + 0.35:
		t += DT
		var now: Array = _at(move, from, t)
		_carry(now, (now[0] - was) / DT)
		was = now[0]
		if OS.get_environment("DRIVE_DEKE_EVERY") != "" and t > -0.1 and t < 0.6:
			var sl: KeeperSlide = _ctrl.motor.slide
			rows.append("   t %+.3f mover %d slide phase %d rotating %s yaw %+.2f x %+.2f z %+.2f goal %+.2f,%+.2f facing %+.2f" % [
					t, _ctrl.motor._mover, sl.phase, str(sl._rotating), _ctrl.motor.yaw, _ctrl.motor.x, _ctrl.motor.z,
					_ctrl.motor.route.spot.x, _ctrl.motor.route.spot.y, _ctrl.motor.route.facing])
			rows.append("        read puck %s carrier %s motion %s" % [_ctrl.play.puck, _ctrl.play.carrier, _ctrl.play.motion])
		if i % 3 == 0 and t > -0.8:
			var me: Vector3 = _ctrl._net.affine_inverse() * _goalie.global_position
			var pn: Vector3 = _ctrl._net.affine_inverse() * (now[1] as Vector3)
			var b: KeeperPositioning = _ctrl.brain
			rows.append("t %+.2f puck %+.2f,%+.2f | him %+.2f,%+.2f (out %.2f) rest %d mover %d goal %+.2f,%+.2f r%d | kd%d low%d" % [
					t, pn.x, pn.z, me.x, me.z, Vector2(me.x, me.z).length(), _ctrl.motor.rest, _ctrl.motor._mover,
					_ctrl.motor.route.spot.x, _ctrl.motor.route.spot.y, _ctrl.motor.route.rest, int(b.kept_down),
					int(_ctrl.motor.low_ready.asked)])
		i += 1
	gut.p("\n" + "\n".join(rows))
	assert_true(true)


# Staged on the carrier START_M out, then skated in to `until` seconds into the
# move. His distance out from the net's centre then, and his rest (1 down).
func _run(move: String, from: float, until: float) -> Vector2:
	_stage(move, from)
	_skate(move, from, until)
	var me: Vector3 = _ctrl._net.affine_inverse() * _goalie.global_position
	return Vector2(Vector2(me.x, me.z).length(), 0.0 if _ctrl.motor.rest == KeeperRoute.Rest.FEET else 1.0)


func _stage(move: String, from: float) -> void:
	var t0: float = -(START_M - from) / DRIVE_M_S
	_s._settle_on((_at(move, from, t0) as Array)[0])
	var was: Vector3 = (_at(move, from, t0 - DT) as Array)[0]
	var t: float = t0
	while t < -1e-6:
		t += DT
		var now: Array = _at(move, from, minf(t, 0.0))
		_carry(now, (now[0] - was) / DT)
		was = now[0]


func _skate(move: String, from: float, until: float) -> Vector3:
	var t: float = 0.0
	var was: Vector3 = (_at(move, from, -DT) as Array)[0]
	var now: Array = _at(move, from, 0.0)
	while t < until - 1e-6:
		t += DT
		now = _at(move, from, t)
		_carry(now, (now[0] - was) / DT)
		was = now[0]
	return now[1]


func _carry(now: Array, velocity: Vector3) -> void:
	_shooter.global_position = now[0]
	_shooter.velocity = velocity
	_shooter.current_shot_state = SkaterStateMachine.State.WRISTER_AIM if now[2] \
			else SkaterStateMachine.State.SKATING_WITH_PUCK
	if _puck.get_carrier() != _shooter:
		_puck.set_carrier(_shooter)
	var puck: Vector3 = now[1]
	_puck.global_position = Vector3(puck.x, _puck.ice_height, puck.z)
	_puck.linear_velocity = Vector3.ZERO
	_ctrl._physics_process(DT)


func _save_share(move: String, from: float, until: float) -> float:
	var shots: int = 0
	var goals: int = 0
	for loft: int in Stager.LOFTS:
		for i: int in range(1, Stager.AIM_POINTS, 3):
			_stage(move, from)
			var at: Vector3 = _skate(move, from, until)
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
