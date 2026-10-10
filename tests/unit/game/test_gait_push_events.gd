extends GutTest

# The push sounds are the gait's own pushes (Skater.skate_pushed): one per leg
# per stride cycle, the legs alternating, none while the skater coasts — so a
# stride is heard exactly when it is seen.

const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _events: Array[Array] = []


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(40.0, 0.0, 40.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 15.0)
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
	_events = []
	_skater.skate_pushed.connect(func(left: bool, strength: float) -> void:
		_events.append([left, strength]))


func _skate(ticks: int, move: Vector2) -> int:
	var input := InputState.new()
	var wraps: int = 0
	var phase: float = _controller._skating.stride_phase
	for _i: int in ticks:
		input.move_vector = move
		input.mouse_world_pos = _skater.global_position + Vector3(0.0, -_skater.global_position.y, -6.0)
		input.delta = DT
		_controller._process_input(input, DT)
		_skater.global_position += _skater.velocity * DT
		_skater._process(DT)
		var now: float = _controller._skating.stride_phase
		if now < phase - PI:
			wraps += 1
		phase = now
	return wraps


func test_each_leg_pushes_once_a_stride_and_the_legs_alternate() -> void:
	_skate(120, Vector2(0.0, -1.0))
	_events.clear()
	var cycles: int = _skate(600, Vector2(0.0, -1.0))
	var lefts: int = 0
	var rights: int = 0
	var swaps: int = 0
	for i: int in _events.size():
		if _events[i][0]:
			lefts += 1
		else:
			rights += 1
		if i > 0 and _events[i][0] != _events[i - 1][0]:
			swaps += 1
	gut.p("5 s striding: %d stride cycles, %d left pushes, %d right, %d of %d alternate"
			% [cycles, lefts, rights, swaps, _events.size() - 1])
	assert_gt(cycles, 2, "the stride cycles")
	assert_almost_eq(lefts, cycles, 1, "the left skate pushes once a cycle")
	assert_almost_eq(rights, cycles, 1, "and the right")
	assert_eq(swaps, _events.size() - 1, "the legs alternate")
	for e: Array in _events:
		assert_gt(e[1], 0.3, "a stride at speed pushes audibly (strength %.2f)" % e[1])


func test_a_coasting_skater_makes_no_push() -> void:
	_skate(240, Vector2(0.0, -1.0))
	_skate(60, Vector2.ZERO)
	_events.clear()
	_skate(120, Vector2.ZERO)
	assert_eq(_events.size(), 0, "a glide is silent of pushes")


# A start's first push begins before the stroke has any strength; it is heard
# as soon as the stroke is strong enough, not skipped.
func test_the_first_push_of_a_start_is_heard() -> void:
	_skate(30, Vector2(0.0, -1.0))
	var start: float = 0.0
	for e: Array in _events:
		start = maxf(start, e[1])
	_skate(360, Vector2(0.0, -1.0))
	_events.clear()
	_skate(120, Vector2(0.0, -1.0))
	var cruise: float = 0.0
	for e: Array in _events:
		cruise = maxf(cruise, e[1])
	gut.p("push strength: start %.2f, cruise %.2f" % [start, cruise])
	assert_gt(start, 0.05, "the start's first push is heard")
	assert_gt(cruise, 0.05, "the cruise pushes")
