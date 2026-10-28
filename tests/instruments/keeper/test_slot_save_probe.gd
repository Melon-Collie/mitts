extends GutTest

# Slot shots at the live keeper with each save played out (resolve_contact,
# his cover and sweep), against what the shot field records of them. Per cell
# (carrier settled or driving in at match pace, release cold or after the bot's
# wrister charge, spot, shot speed):
#   first sv%   — the shot field's verdict: any first contact is a save
#   played sv%  — a puck that goes in off him is a goal
#   FLAT        — the flat shots post to post: G clean goal, o in off him,
#                 s save, w wide
# and the goals in off him by the part the puck met first.
# test_trace_one_slot_goal follows one flat shot tick by tick to the gear it
# meets: the pads and blade boxes, and the contact's normal and rebound.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const SPEEDS: Array[float] = [20.0, 27.0, 33.0]
const SPOTS: Array[Vector2] = [Vector2(0.0, 5.0), Vector2(1.5, 5.0), Vector2(0.0, 7.0),
		Vector2(1.5, 7.0)]
const DRIVE_M_S: float = 7.0
const DRIVE_FROM_M: float = 14.0
const PART_NAMES: Array[String] = ["STICK", "PAD", "BLOCKER", "CHEST", "GLOVE", "MASK"]

var _s: RefCounted = null
var _h: RefCounted = null
var _ctrl: KeeperController = null
var _puck: Node = null
var _shooter: Skater = null
var _sw := SweptDiscOBB.Result.new()
var _ct := GoalieContactDetector.Contact.new()


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	add_child_autofree(goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_s = Stager.new(goalie, _puck, _ctrl, _shooter)
	_h = _s._h


func _stage(spot: Vector2, driving: bool) -> Vector3:
	if not driving:
		return _s.stage_set(Vector3(spot.x, 0.0, GOAL_Z + spot.y))
	_h.settle_ready(Vector3(spot.x, 0.0, GOAL_Z + DRIVE_FROM_M))
	return _h.drive_in(spot.x, DRIVE_FROM_M, spot.y, DRIVE_M_S)


# The release as the match makes it (the signal the keeper reads), then the
# rebound-tracking march from the same state.
func _fire(at: Vector3, aim: Vector3, loft: int, speed: float, charged: bool) -> int:
	if charged:
		_h.hold_windup_at(at, aim, loft, speed, Stager.CHARGE_TICKS)
	var vel: Vector3 = _h.shot_velocity_at(at, aim, loft, speed, 0.0)
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	_puck.global_position = Vector3(at.x, _puck.ice_height, at.z)
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	return _h.fire_tracking_rebound(at, aim, loft, speed, 0.0)


func test_slot_saves() -> void:
	var lines: PackedStringArray = []
	lines.append("carrier release  spot     speed | first sv%  played sv% | FLAT post to post"
			+ "          | clean | off him, by the part it met first")
	for driving: bool in [false, true]:
		for charged: bool in [true, false]:
			for spot: Vector2 in SPOTS:
				for speed: float in SPEEDS:
					lines.append(_cell(spot, speed, driving, charged))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _cell(spot: Vector2, speed: float, driving: bool, charged: bool) -> String:
	var on_net: int = 0
	var clean: int = 0
	var off_him: Dictionary = {}
	var off_total: int = 0
	var flat: String = ""
	for loft: int in Stager.LOFTS:
		for i: int in Stager.AIM_POINTS:
			var at: Vector3 = _stage(spot, driving)
			var aim := Vector3(Stager.aim_x(i), 0.0, GOAL_Z)
			var r: int = _fire(at, aim, loft, speed, charged)
			var touched: bool = _h.last_part >= 0
			var c: String = "w"
			if r == Harness.GOAL and not touched:
				c = "G"
				clean += 1
			elif touched and (r == Harness.GOAL or _h.rebound_goal):
				c = "o"
				off_total += 1
				var part: String = PART_NAMES[_h.last_part]
				off_him[part] = int(off_him.get(part, 0)) + 1
			elif touched:
				c = "s"
			if loft == ShotMechanics.ELEVATION_FLAT:
				flat += c
			if c != "w":
				on_net += 1
	return "%-7s %-8s (%.1f,%.1f) %4.0f | %6.2f    %6.2f   | %s | %4d  | %d %s" % [
			"drive" if driving else "set", "charged" if charged else "cold",
			spot.x, spot.y, speed,
			1.0 - float(clean) / maxf(on_net, 1),
			1.0 - float(clean + off_total) / maxf(on_net, 1), flat, clean, off_total, str(off_him)]


# A flat shot that goes in off his right pad (aim 3) and one his blade stops
# (aim 12), 5 m out at 20 m/s against a settled carrier.
func test_trace_one_slot_goal() -> void:
	for idx: int in [3, 12]:
		var at: Vector3 = _stage(Vector2(0.0, 5.0), false)
		var aim := Vector3(Stager.aim_x(idx), 0.0, GOAL_Z)
		var vel: Vector3 = _h.shot_velocity_at(at, aim, ShotMechanics.ELEVATION_FLAT, 20.0, 0.0)
		_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
		_puck.clear_carrier()
		var pos := Vector3(at.x, _puck.ice_height, at.z)
		_puck.global_position = pos
		_puck.apply_release_velocity(vel)
		_puck.puck_released.emit()
		var lines: PackedStringArray = ["aim %d (x %.2f): keeper x %.2f z %.2f, mirrored %s" % [
				idx, aim.x, _ctrl.motor.x, _ctrl.motor.z, _ctrl._keeper.skeleton.mirrored]]
		for t: int in 40:
			_puck.global_position = pos
			_puck.linear_velocity = vel
			_ctrl._physics_process(Stager.DT)
			lines.append("t%2d puck z %.2f x %.2f | legs_read %s chosen %s low %d side %.0f hand %d covers %s ready %.3f impact %.3f | drop st %d down %.2f lowready %.2f | padG %s padB %s stick %s" % [
					t, pos.z, pos.x, _ctrl.read.legs_read(), _ctrl._chosen, _ctrl.save.low,
					_ctrl.save.low_side, _ctrl.save.hand, _ctrl.save.covers, _ctrl.save.ready_s,
					_ctrl.save.impact_s, _ctrl.motor.drop.state, _ctrl.motor.drop.down,
					_ctrl.motor.low_ready.share,
					_box(KeeperGear.Part.PAD_G), _box(KeeperGear.Part.PAD_B), _box(KeeperGear.Part.BLADE)])
			var nxt: Vector3 = pos + vel * Stager.DT
			if GoalieContactDetector.nearest([_ctrl.goalie], pos, nxt, GameRules.PUCK_COLLISION_RADIUS,
					_sw, _ct):
				var res := GoalieSaveRules.ContactResult.new()
				var fwd: Vector3 = -(_ctrl.goalie as Node3D).global_transform.basis.z
				GoalieSaveRules.resolve_contact(vel, GoalieSaveRules.SavePart.PAD, _ct.normal, res, fwd)
				lines.append("   CONTACT part %s at %s normal %s (%.0f deg off facing the shot) in %s out %s" % [
						(_ct.part as Node).name, _ct.point, _ct.normal,
						rad_to_deg(Vector2(_ct.normal.x, _ct.normal.z).angle_to(Vector2(-vel.x, -vel.z))),
						vel, res.velocity])
				break
			pos = nxt
			if pos.z < GOAL_Z:
				lines.append("   CROSSED the line at x %.2f y %.3f" % [pos.x, pos.y])
				break
		gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _box(part: int) -> String:
	var xf: Transform3D = (_ctrl.goalie as Node3D).global_transform \
			* KeeperGear.box(_ctrl._keeper.skeleton, part)
	var he: Vector3 = KeeperGear.half_extents(part)
	var lo: float = INF
	var x0: float = INF
	var x1: float = -INF
	var z0: float = INF
	var z1: float = -INF
	for c: int in 8:
		var corner := Vector3(he.x * (1 if c & 1 else -1), he.y * (1 if c & 2 else -1),
				he.z * (1 if c & 4 else -1))
		var w: Vector3 = xf * corner
		lo = minf(lo, w.y)
		x0 = minf(x0, w.x)
		x1 = maxf(x1, w.x)
		z0 = minf(z0, w.z)
		z1 = maxf(z1, w.z)
	return "x[%.2f,%.2f] z[%.2f,%.2f] bottom %.3f" % [x0, x1, z0, z1, lo]
