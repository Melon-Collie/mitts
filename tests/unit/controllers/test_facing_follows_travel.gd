extends GutTest

# A skating human faces their travel rather than the cursor
# (FacingRules), driven through the live controller.
# Facing starts toward −Z; the skater is held at a set velocity each tick so the
# speed under test is the speed the rule reads.

const DT: float = 1.0 / 120.0
const AHEAD := Vector3(0.0, 0.0, -1.0)
const LEFT := Vector3(-1.0, 0.0, 0.0)
const BEHIND := Vector3(0.0, 0.0, 1.0)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))


# Runs `ticks` ticks skating along `travel` at `speed` with the cursor 6 m out
# along `cursor`, holding the velocity so friction doesn't bleed it.
func _skate(travel: Vector3, speed: float, cursor: Vector3, ticks: int,
		move: Vector2 = Vector2.ZERO, stance: bool = false) -> void:
	for _i: int in ticks:
		_skater.velocity = travel * speed
		var input := InputState.new()
		input.move_vector = move
		input.stance_held = stance
		input.mouse_world_pos = _skater.global_position + cursor * 6.0
		input.mouse_world_pos.y = 0.0
		input.delta = DT
		_controller._process_input(input, DT)


func _facing_off(dir: Vector3) -> float:
	return rad_to_deg(absf(_skater.get_facing().angle_to(Vector2(dir.x, dir.z))))


func test_skating_with_the_puck_out_wide_faces_the_travel() -> void:
	_skate(AHEAD, 6.0, LEFT, 120, Vector2(0.0, -1.0))
	assert_lt(_facing_off(AHEAD), 5.0, "hips stay on the line while the cursor sits at 9")


func test_a_coast_keeps_its_line() -> void:
	_skate(AHEAD, 6.0, LEFT, 60, Vector2(0.0, -1.0))
	_skate(AHEAD, 1.3, LEFT, 120)
	assert_lt(_facing_off(AHEAD), 20.0, "a slow coast still faces where it glides")


func test_standing_squares_to_the_cursor() -> void:
	_skate(AHEAD, 0.0, LEFT, 120)
	assert_lt(_facing_off(LEFT), 5.0)


func test_a_cursor_behind_the_travel_turns_the_skater_round() -> void:
	_skate(AHEAD, 6.0, AHEAD, 30, Vector2(0.0, -1.0))
	_skate(AHEAD, 6.0, BEHIND, 120)
	assert_lt(_facing_off(BEHIND), 20.0,
			"looking straight back while skating forward turns to skate backward, not freeze")


func test_a_cursor_flicked_ahead_turns_a_backward_skater_forward() -> void:
	_controller._pose.facing = Vector2(BEHIND.x, BEHIND.z)
	_skater.set_facing(Vector2(BEHIND.x, BEHIND.z))
	_skate(AHEAD, 6.0, BEHIND, 30)
	_skate(AHEAD, 6.0, AHEAD, 120)
	assert_lt(_facing_off(AHEAD), 20.0,
			"a cursor flicked to where a backward skater is going turns them round, not freeze")


func test_a_backward_skater_turns_forward_on_the_cursors_side() -> void:
	# Leaning a touch right of straight back, with the cursor flicked ahead-left:
	# the body comes round through the left, the way the player is looking.
	var lean := Vector2(BEHIND.x, BEHIND.z).rotated(deg_to_rad(-5.0))
	_controller._pose.facing = lean
	_skater.set_facing(lean)
	var ahead_left := AHEAD.rotated(Vector3.UP, deg_to_rad(10.0))
	var widest_right: float = -INF
	var widest_left: float = INF
	for _i: int in 120:
		_skate(AHEAD, 6.0, ahead_left, 1)
		widest_right = maxf(widest_right, _skater.get_facing().x)
		widest_left = minf(widest_left, _skater.get_facing().x)
	assert_lt(_facing_off(AHEAD), 20.0)
	assert_lt(widest_left, -0.9, "the body swept through the left")
	assert_lt(widest_right, 0.2, "and never round the right")


func test_a_slow_backward_skater_turns_forward_on_a_flick() -> void:
	_controller._pose.facing = Vector2(BEHIND.x, BEHIND.z)
	_skater.set_facing(Vector2(BEHIND.x, BEHIND.z))
	_skate(AHEAD, 1.0, BEHIND, 30)
	_skate(AHEAD, 1.0, AHEAD, 120)
	assert_lt(_facing_off(AHEAD), 20.0, "below the engage band the body still comes round")


func test_a_stop_turns_round_to_a_cursor_behind() -> void:
	_skate(AHEAD, 6.0, AHEAD, 30, Vector2(0.0, -1.0))
	for _i: int in 60:
		_skater.velocity = AHEAD * 4.0
		var input := InputState.new()
		input.brake = true
		input.mouse_world_pos = _skater.global_position + BEHIND * 6.0
		input.mouse_world_pos.y = 0.0
		input.delta = DT
		_controller._process_input(input, DT)
	assert_lt(_facing_off(BEHIND), 20.0, "stopping and looking back turns the body to go back")


func test_a_cursor_behind_a_standing_skater_still_freezes_facing() -> void:
	_skate(AHEAD, 0.0, AHEAD, 30)
	_skate(AHEAD, 0.0, BEHIND, 120)
	assert_lt(_facing_off(AHEAD), 5.0, "the unreachable-wedge freeze still holds at rest")


func test_the_stance_squares_only_when_slow() -> void:
	_skate(AHEAD, 1.5, LEFT, 120, Vector2.ZERO, true)
	assert_lt(_facing_off(LEFT), 10.0, "slow in the stance squares to the cursor")
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))
	_skate(AHEAD, 6.0, LEFT, 120, Vector2(0.0, -1.0), true)
	assert_lt(_facing_off(AHEAD), 5.0, "at speed the stance just crouches")
