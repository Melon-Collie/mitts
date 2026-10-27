extends "res://tests/instruments/ai/test_interceptor_truth.gd"

# The interceptor against a carrier who sees him coming
# (docs/strip-interception-plan.md). Both sides now react: the interceptor no
# longer knows the carrier's path — every tick he re-aims at where the carrier's
# momentum is taking him, the earliest point of that line his stick reaches
# _set_s before the carrier — and the carrier skates the staging's path but
# swerves off it, away from a defender whose short-term heading puts his stick
# near the puck, then carries on. The carrier is a real body (movement, carry,
# arm) whose input is replaced every tick, with no decision of the bots' in it.
# The planned path is the carrier's dry run alone, as a planner reads it. Saves
# as test_interceptor_truth.gd does (MITTS_RACE_SAVE, <path>.planned).
# Reports only.

# The carrier's read of a defender: where his heading takes him this far ahead.
const DODGE_READ_S: float = 0.3
# Inside this of the puck, that spot is a stick coming: his blade's reach and a
# stride.
const DODGE_M: float = AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M + 1.5
# How hard he swerves: the away push against the pull of his path.
const DODGE_WEIGHT: float = 1.5
const WAYPOINT_M: float = 1.0
const PLAN_HORIZON_S: float = 3.0



func test_interceptor_truth() -> void:
	pass


func test_reacting_interceptor_truth() -> void:
	super.test_interceptor_truth()


func _add_carrier(duel: Object, pos: Vector3, vel: Vector3, path: Array[Vector3]) -> void:
	_add_reacting_carrier(duel, pos, vel, path)
	var dry: Object = Duel.new()
	_add_reacting_carrier(dry, pos, vel, path)
	dry.start(CARRIER)
	_planned_now.clear()
	for i: int in int(HORIZON_S / Duel.DT):
		dry.step()
		if (i + 1) % SAMPLE_TICKS == 0:
			_planned_now.append(dry.puck_pos)


func _add_reacting_carrier(duel: Object, pos: Vector3, vel: Vector3,
		path: Array[Vector3]) -> void:
	duel.add_skater(CARRIER, 0, pos, null, vel)
	var waypoints: Array[Vector3] = path.duplicate()
	if waypoints.is_empty():
		waypoints.append(pos)
	var next: Array[int] = [mini(1, waypoints.size() - 1)]
	duel._skater(CARRIER).input_override = func(s: Object) -> void: _carry(s, duel, waypoints,
			next)


# One tick of the carrier's input: toward his next waypoint at no more than
# TOP_PACE_M_S, swerving away from each defender whose heading brings his stick
# near the puck. `next` holds the index of the waypoint he is skating to.
func _carry(s: Object, duel: Object, waypoints: Array[Vector3], next: Array[int]) -> void:
	var input: InputState = s.input
	_clear(input)
	var target: Vector3 = waypoints[next[0]]
	var to := Vector2(target.x - s.pos.x, target.z - s.pos.z)
	if to.length() < WAYPOINT_M and next[0] < waypoints.size() - 1:
		next[0] += 1
		target = waypoints[next[0]]
		to = Vector2(target.x - s.pos.x, target.z - s.pos.z)
	var along: Vector2 = to.normalized() if to.length() > WAYPOINT_M else Vector2.ZERO
	var away := Vector2.ZERO
	for o: Object in duel.skaters:
		if o.team_id == s.team_id:
			continue
		var q := Vector2(o.pos.x + o.vel.x * DODGE_READ_S, o.pos.z + o.vel.z * DODGE_READ_S)
		var off := Vector2(duel.puck_pos.x, duel.puck_pos.z) - q
		if off.length() >= DODGE_M or off.length() < 0.001:
			continue
		var push: Vector2 = off.normalized()
		if along != Vector2.ZERO:
			# Off his line, to the side away from the man, so the path still leads on.
			var side := Vector2(-along.y, along.x)
			push = side * signf(side.dot(off)) if absf(side.dot(off)) > 0.001 else side
		away += push * (1.0 - off.length() / DODGE_M)
	var dir: Vector2 = along + away * DODGE_WEIGHT
	var speed: float = Vector2(s.vel.x, s.vel.z).length()
	if dir.length() < 0.05:
		input.brake = speed > 0.5
		input.mouse_world_pos = duel.puck_pos
		return
	dir = dir.normalized()
	input.move_vector = dir if speed < TOP_PACE_M_S or away != Vector2.ZERO else Vector2.ZERO
	input.mouse_world_pos = s.pos + Vector3(dir.x, 0.0, dir.y) * PLAY_M


# The interceptor no longer knows the path: the line he aims at is where the
# carrier's momentum takes him, read afresh every tick.
func _intercept(s: Object, duel: Object, caps: AISkaterCaps) -> void:
	var c: Object = duel._skater(CARRIER)
	var now: int = duel.ticks
	_schedule.resize(now + int(PLAN_HORIZON_S / Duel.DT))
	for j: int in range(now, _schedule.size()):
		var t: float = (j + 1 - now) * Duel.DT
		var p := GameRules.clamp_to_rink_inner(Vector2(c.pos.x + c.vel.x * t, c.pos.z + c.vel.z * t))
		_schedule[j] = Vector3(p.x, 0.0, p.y)
	super(s, duel, caps)


func _clear(input: InputState) -> void:
	input.shoot_pressed = false
	input.shoot_held = false
	input.slap_pressed = false
	input.slap_held = false
	input.hit_held = false
	input.stance_held = false
	input.stick_check_held = false
	input.stick_check_pressed = false
	input.stick_lift_held = false
	input.stick_lift_pressed = false
	input.quick_pass_pressed = false
	input.block_held = false
	input.bot_shuffle = false
	input.brake = false
	input.move_vector = Vector2.ZERO
