extends GutTest

# Point shots through a live net-front stick, at the live keeper (issue #736).
# The tipper is a real Skater on a real SkaterController holding Q (pressed on
# the release, so it reads the puck as a player does), the contact is the host's
# own PuckController._check_interactions → Puck.apply_blade_deflect, and the tip
# reaches the keeper through puck_touched_loose, which restarts his read. The
# march around it is RealGoalieShotHarness._march's: keeper tick, frame step,
# posed-gear contact, goal-line verdict.
#
# The cursor is swept across in front of the tipper, who starts square to the
# shooter, so each row is one blade placement. test_the_aim_window reads whether
# a placement sends the tip somewhere predictable: how far the goal-line
# crossing moves per step of cursor, and how wide a strip of cursor is on net.
# test_tip_conversion counts, of the tips that reach the mouth, how many score.
#
# Per shot:  G goal  s save  P post  w wide  b off his body  - not touched
#            x touched twice (out of scope)
# Per row:   how far the body turned toward the cursor, the shaft's bearing off
#            the incoming line, the turn the tip gave the puck (+ toward the
#            forehand side), the pace it kept, and the crossing x and height at
#            the goal line (NET_HALF_WIDTH either side is the mouth).
#
# The tipper is in the keeper's world view, so he screens as he would in a game.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = Harness.DT
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const RADIUS: float = GameRules.PUCK_COLLISION_RADIUS
const MAX_STEPS: int = 300
const BLADE_SETTLE_TICKS: int = 60

# Cursor ahead of the tipper (toward the shooter) and across, in his frame.
const CURSOR_AHEAD_M: float = 0.9
const CURSOR_SPAN_M: float = 0.9
const CURSOR_STEP_M: float = 0.05
const AIM_SPEED: float = 28.0

# Spots are (x, metres out from the goal line); #736's four, plus the slot.
const SHOOTERS: Array[Vector2] = [Vector2(0.0, 18.0), Vector2(5.0, 16.0)]
const TIPPERS: Array[Vector2] = [Vector2(1.5, 4.0), Vector2(-1.5, 4.0), Vector2(1.0, 5.5),
		Vector2(0.0, 3.0)]
const SPEEDS: Array[float] = [24.0, 32.0]
const TIP_LEVELS: Array[int] = [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW,
		ShotMechanics.ELEVATION_MID, ShotMechanics.ELEVATION_HIGH]
const LEVEL_NAMES: Array[String] = ["FLAT", "LOW", "MID", "HIGH"]


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _h: RefCounted = null
var _ctrl: KeeperController = null
var _goalie: Node = null
var _puck: Puck = null
var _shooter: Skater = null
var _tc: SkaterController = null
var _pc: PuckController = null
var _sw := SweptDiscOBB.Result.new()
var _ct := GoalieContactDetector.Contact.new()
var _frame := PuckGeometryCollision.Result.new()
var _tick_res := PuckAuthorityRules.TickResult.new()

# The last shot's tip, if any.
var _tipped: bool = false
var _blocked: bool = false
var _tip_in := Vector3.ZERO
var _tip_out := Vector3.ZERO
var _cross := Vector3.INF
var _touches: int = 0


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	_shooter = SKATER_SCENE.instantiate() as Skater
	_ctrl = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)

	var tipper: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(tipper)
	tipper.set_physics_process(false)
	tipper.set_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_tc = SkaterController.new()
	add_child_autofree(_tc)
	_tc.setup(tipper, _puck, gs)
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({tipper: 0})
	_pc.set_skater_getter(func() -> Array: return [tipper])
	_pc.set_peer_id_resolver(func(_s: Skater) -> int: return 1)
	_ctrl.set_skater_getter(func() -> Array: return [_shooter, tipper])
	_puck.puck_touched_loose.connect(_on_touched)
	_puck.puck_body_blocked.connect(_on_blocked)


func _on_touched(_s: Skater) -> void:
	_tipped = true
	_touches += 1


func _on_blocked(_s: Skater) -> void:
	_blocked = true
	_touches += 1


func _world(spot: Vector2) -> Vector3:
	return Vector3(spot.x, 0.0, GOAL_Z + spot.y)


# The tipper on `spot`, square to the shooter, his blade drawn to the cursor
# `across` metres to his forehand side (negative: backhand) and held there.
func _place_tipper(spot: Vector2, shooter: Vector3, across: float) -> void:
	var at: Vector3 = _world(spot)
	var to_shooter := Vector2(shooter.x - at.x, shooter.z - at.z).normalized()
	_tc.teleport_to(Vector3(at.x, GameRules.FACEOFF_SPAWN_HEIGHT, at.z), to_shooter)
	var fwd := Vector3(to_shooter.x, 0.0, to_shooter.y)
	# Forehand side for this skater's handedness: the side the blade rests on.
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var side: float = -1.0 if _tc.skater.is_left_handed else 1.0
	var cursor: Vector3 = at + fwd * CURSOR_AHEAD_M + right * side * across
	for _i: int in BLADE_SETTLE_TICKS:
		_tick_tipper(cursor, false, ShotMechanics.ELEVATION_FLAT)
	_tc.skater.capture_prev_blade_contact()
	_puck.remove_skater_cooldown(_tc.skater)


func _tick_tipper(cursor: Vector3, deflect: bool, level: int) -> void:
	var input := InputState.new()
	input.stick_lift_held = deflect
	input.elevation_level = level
	input.mouse_world_pos = cursor
	input.delta = DT
	_tc._process_input(input, DT)
	_tc.skater._update_blade_lift(DT)


# One point shot aimed through the tipper's blade, Q pressed on the release.
# Returns the outcome character.
func _shoot(shooter: Vector3, speed: float, loft: int, level: int, cursor: Vector3) -> String:
	_tipped = false
	_blocked = false
	_touches = 0
	_cross = Vector3.INF
	var blade: Vector3 = _tc.skater.get_blade_contact_global()
	var vel: Vector3 = _h.shot_velocity_at(shooter, Vector3(blade.x, 0.0, blade.z), loft, speed, 0.0)
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	var pos := Vector3(shooter.x, _puck.ice_height, shooter.z)
	_puck.global_position = pos
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	var goal_dir: float = signf(GOAL_Z - shooter.z)
	for _step: int in MAX_STEPS:
		var prev: Vector3 = pos
		_tick_tipper(cursor, true, level)
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
		_tick_res.touched_post = false
		_tick_res.touched_net = false
		PuckAuthorityRules.step_frame_substep(pos, vel, DT, RADIUS,
				_puck.max_speed, _puck.ice_height, _puck.max_height, _frame, _tick_res)
		pos = _tick_res.position
		vel = _tick_res.velocity
		_pc._prev_puck_pos = prev
		_puck.global_position = pos
		_puck.linear_velocity = vel
		var touches_before: int = _touches
		_pc._check_interactions()
		_puck.drain_contact_events()
		if _touches != touches_before:
			if touches_before > 0:
				return "x"  # a second touch: out of this instrument's scope
			_tip_in = vel
			_tip_out = _puck.linear_velocity
			vel = _tip_out
		if GoalieContactDetector.nearest([_goalie], prev, pos, RADIUS, _sw, _ct):
			return "s"
		if (pos.z - GOAL_Z) * goal_dir >= 0.0:
			var seg: float = pos.z - prev.z
			var f: float = clampf((GOAL_Z - prev.z) / seg, 0.0, 1.0) if absf(seg) > 1e-6 else 1.0
			_cross = prev.lerp(pos, f)
			match _h._net_verdict(_cross.x, _cross.y):
				Harness.GOAL:
					return "G"
				Harness.POST:
					return "P"
			return "w"
	return "w"


func _signed_turn_deg(a: Vector3, b: Vector3, forehand: Vector3) -> float:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var turn: float = rad_to_deg(a2.angle_to(b2))
	# + toward the tipper's forehand side.
	var cross_sign: float = signf(a2.cross(Vector2(forehand.x, forehand.z)))
	return turn * (cross_sign if cross_sign != 0.0 else 1.0)


func _shaft_bearing_deg(incoming: Vector3) -> float:
	var axis: Vector3 = PuckReceptionRules.blade_axis(_tc.skater.get_blade_contact_global(),
			_tc.skater.top_hand.global_position, -_tc.skater.global_transform.basis.z)
	var a := Vector2(incoming.x, incoming.z).normalized()
	var deg: float = rad_to_deg(acos(clampf(absf(a.dot(Vector2(axis.x, axis.z))), 0.0, 1.0)))
	return deg


# One point shot through each net-front spot, the cursor swept across in 5 cm
# steps: where each placement sends the tip, and how wide a strip of cursor puts
# it on net at all.
func test_the_aim_window() -> void:
	var shooter: Vector3 = _world(SHOOTERS[0])
	var lines: PackedStringArray = []
	for tip_spot: Vector2 in TIPPERS:
		lines.append("")
		lines.append("shooter (%.0f,%.0f) -> tipper (%.1f,%.1f), FLAT tip, %.0f m/s flat shot" % [
				SHOOTERS[0].x, SHOOTERS[0].y, tip_spot.x, tip_spot.y, AIM_SPEED])
		lines.append("  cursor across | facing  shaft-off-line | turn   pace | cross x  y    | out")
		var on_net: int = 0
		var first: float = INF
		var last: float = -INF
		var slope_sum: float = 0.0
		var slope_n: int = 0
		var prev_x: float = INF
		var c: float = -CURSOR_SPAN_M
		while c <= CURSOR_SPAN_M + 0.001:
			var r: Array = _row(shooter, tip_spot, AIM_SPEED, ShotMechanics.ELEVATION_FLAT, c)
			lines.append(r[0])
			var cx: float = r[1]
			if absf(cx) <= GameRules.NET_HALF_WIDTH:
				on_net += 1
				first = minf(first, c)
				last = maxf(last, c)
			if cx != INF and prev_x != INF and absf(cx) < 3.0:
				slope_sum += absf(cx - prev_x)
				slope_n += 1
			prev_x = cx
			c += CURSOR_STEP_M
		lines.append("  -> on net from %d of the placements (%.0f cm of cursor, %+.2f..%+.2f);"
				% [on_net, on_net * CURSOR_STEP_M * 100.0, first, last]
				+ " near the net the crossing moves %.2f m per %.0f cm of cursor"
				% [slope_sum / maxf(slope_n, 1), CURSOR_STEP_M * 100.0])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


# Every shooter, spot, shot pace and tip level, the cursor swept finely: of the
# tips that reach the mouth, how many score against the live keeper.
func test_tip_conversion() -> void:
	var lines: PackedStringArray = ["shooter  tipper      tip   speed | tips  on net  goals  conv"]
	var by_level: Dictionary = {}
	var height_sum: Dictionary = {}
	var height_n: Dictionary = {}
	for shooter_spot: Vector2 in SHOOTERS:
		var shooter: Vector3 = _world(shooter_spot)
		for tip_spot: Vector2 in TIPPERS:
			for level: int in TIP_LEVELS:
				for speed: float in SPEEDS:
					var t := Vector3i.ZERO
					var c: float = -CURSOR_SPAN_M
					while c <= CURSOR_SPAN_M + 0.001:
						var r: Array = _row(shooter, tip_spot, speed, level, c)
						var out: String = r[2]
						if _tipped:
							t.x += 1
							if out == "G" or out == "s" or out == "P":
								t.y += 1
							if out == "G":
								t.z += 1
						if _cross != Vector3.INF and absf(_cross.x) <= GameRules.NET_HALF_WIDTH:
							height_sum[level] = height_sum.get(level, 0.0) + _cross.y
							height_n[level] = height_n.get(level, 0) + 1
						c += CURSOR_STEP_M
					var lv: String = LEVEL_NAMES[level]
					by_level[lv] = by_level.get(lv, Vector3i.ZERO) + t
					lines.append("(%2.0f,%2.0f)  (%+.1f,%.1f)  %-4s  %3.0f   | %4d  %5d  %5d  %3.0f%%" % [
							shooter_spot.x, shooter_spot.y, tip_spot.x, tip_spot.y, lv, speed,
							t.x, t.y, t.z, 100.0 * t.z / maxf(t.y, 1)])
	for level: int in TIP_LEVELS:
		var lv: String = LEVEL_NAMES[level]
		var t: Vector3i = by_level.get(lv, Vector3i.ZERO)
		lines.append("ALL %-4s tips %d, on net %d (%.0f%%), goals %d (%.0f%% of those on net),"
				% [lv, t.x, t.y, 100.0 * t.y / maxf(t.x, 1), t.z, 100.0 * t.z / maxf(t.y, 1)]
				+ " mean height at the line %.2f m" % [
				height_sum.get(level, 0.0) / maxf(height_n.get(level, 0), 1)])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


# [printed row, crossing x (INF if it never got there), outcome character]
func _row(shooter: Vector3, tip_spot: Vector2, speed: float, level: int, across: float) -> Array:
	_h.settle_ready(shooter)
	_place_tipper(tip_spot, shooter, across)
	var sk: Skater = _tc.skater
	var at: Vector3 = _world(tip_spot)
	var fwd := Vector3(shooter.x - at.x, 0.0, shooter.z - at.z).normalized()
	var side: float = -1.0 if sk.is_left_handed else 1.0
	var forehand := Vector3(-fwd.z, 0.0, fwd.x) * side
	var cursor: Vector3 = at + fwd * CURSOR_AHEAD_M + forehand * across
	var facing: Vector2 = sk.get_facing()
	var facing_off: float = rad_to_deg(absf(facing.angle_to(Vector2(fwd.x, fwd.z))))
	var blade: Vector3 = sk.get_blade_contact_global()
	var shaft: float = _shaft_bearing_deg(Vector3(blade.x - shooter.x, 0.0, blade.z - shooter.z))
	var out: String = _shoot(shooter, speed, ShotMechanics.ELEVATION_FLAT, level, cursor)
	if _blocked:
		out = "b"
	elif not _tipped and out != "x":
		out = "-"
	var turn_s: String = "   -  "
	var pace_s: String = "   - "
	if _tipped:
		turn_s = "%+5.1f" % _signed_turn_deg(_tip_in, _tip_out, forehand)
		pace_s = "%3.0f%%" % (100.0 * _tip_out.length() / maxf(_tip_in.length(), 0.001))
	var cross_s: String = "   -       "
	var cross_x: float = INF
	if _cross != Vector3.INF:
		cross_x = _cross.x
		cross_s = "%+5.2f  %4.2f" % [_cross.x, _cross.y]
	elif out == "s":
		cross_x = 0.0  # it met him on the way: on net
	var line: String = "  %+5.2f         | %5.1f   %5.1f          | %s %s | %s | %s" % [
			across, facing_off, shaft, turn_s, pace_s, cross_s, out]
	return [line, cross_x, out]
