extends GutTest

# Circles the cursor round a skater — standing and skating, empty stick and
# carrying, close in and far out, both ways round — and prints, per run, how
# well the blade follows it and what the hips did: the longest the blade's
# target stalled while the cursor kept going, the widest it trailed the cursor,
# how many times the hips flipped between the forward and the backward line,
# and how far off the cursor a standing body ended up. Asserts nothing; it is
# the A/B for any change to the reach, the stick or the facing rules.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const AHEAD := Vector3(0.0, 0.0, -1.0)
const DEG_S: float = 180.0
const TURNS: float = 2.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null


func _rig(carry: bool) -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller.apply_attributes(PlayerAttributes.neutral())
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))
	if carry:
		_puck.set_carrier(_skater)
		_controller.on_puck_picked_up_network()


func _bearing(at: Vector3) -> float:
	var rel: Vector3 = at - _skater.global_position
	return atan2(rel.x, -rel.z)


# One run; returns [longest stall ticks, widest trail deg, hip flips, standing
# end off the cursor deg].
func _circle(speed: float, carry: bool, radius: float, sense: float) -> Array:
	_rig(carry)
	var settle: int = 60
	var ticks: int = settle + int(TURNS * 360.0 / DEG_S / DT)
	var stall: int = 0
	var longest: int = 0
	var widest: float = 0.0
	var flips: int = 0
	var backward: bool = false
	var prev_cursor: float = INF
	var prev_target: float = INF
	var cursor_dir := Vector3.ZERO
	for t: int in ticks:
		var a: float = deg_to_rad(maxf(float(t - settle), 0.0) * DT * DEG_S) * sense
		cursor_dir = AHEAD.rotated(Vector3.UP, -a)
		_skater.velocity = AHEAD * speed
		var input := InputState.new()
		input.delta = DT
		input.host_timestamp = float(t) * DT
		input.move_vector = Vector2(0.0, -1.0) if speed > 0.0 else Vector2.ZERO
		input.mouse_world_pos = _skater.global_position + cursor_dir * radius
		input.mouse_world_pos.y = 0.0
		_controller._process_input(input, DT)
		if t < settle:
			continue
		var cursor: float = _bearing(input.mouse_world_pos)
		var target: float = _bearing(_controller._ik.last_target_blade_world)
		widest = maxf(widest, rad_to_deg(absf(angle_difference(target, cursor))))
		if prev_cursor != INF:
			var step_c: float = absf(angle_difference(prev_cursor, cursor))
			var step_t: float = angle_difference(prev_target, target) * signf(
					angle_difference(prev_cursor, cursor))
			if step_t < 0.25 * step_c and absf(angle_difference(target, cursor)) > deg_to_rad(20.0):
				stall += 1
				longest = maxi(longest, stall)
			else:
				stall = 0
		prev_cursor = cursor
		prev_target = target
		if speed > 0.0:
			var off: float = rad_to_deg(absf(_skater.get_facing().angle_to(Vector2(AHEAD.x, AHEAD.z))))
			if not backward and off > 120.0:
				backward = true
				flips += 1
			elif backward and off < 60.0:
				backward = false
				flips += 1
	var end_off: float = rad_to_deg(absf(_skater.get_facing().angle_to(
			Vector2(cursor_dir.x, cursor_dir.z))))
	return [longest, widest, flips, end_off]


func test_print_the_cursor_circling() -> void:
	print("\n%-28s %8s %8s %6s %8s" % ["run", "stall", "trail°", "flips", "end off°"])
	for speed: float in [0.0, 6.0]:
		for carry: bool in [false, true]:
			for radius: float in [0.4, 0.8, 1.5, 4.0]:
				for sense: float in [1.0, -1.0]:
					var r: Array = _circle(speed, carry, radius, sense)
					var run: String = "%s %s r%.1f %s" % ["skate" if speed > 0.0 else "stand",
							"carry" if carry else "empty", radius, "cw" if sense > 0.0 else "ccw"]
					print("CIRCLE %-28s %8d %8.0f %6d %8.0f" % [run, r[0], r[1], r[2], r[3]])
	assert_true(true)
