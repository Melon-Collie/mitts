extends GutTest

# The step sounds are the gait's own steps (Skater.skate_pushed, skate_touched):
# one push and one landing per leg per stride cycle, the legs alternating, none
# while the skater coasts — so a stride is heard exactly when it is seen. A
# start's pushes dig.

const DT: float = 1.0 / 120.0


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _events: Array[Array] = []
var _touches: Array[Array] = []
var _tick: int = 0


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
	_skater.skate_pushed.connect(func(left: bool, strength: float, dig: float) -> void:
		_events.append([left, strength, dig]))
	_touches = []
	_skater.skate_touched.connect(func(left: bool, lift: float) -> void:
		_touches.append([left, lift]))


# `arc` holds the stick 45° inside travel to the right: a driven turn, skated
# as crossovers.
func _skate(ticks: int, move: Vector2, arc: bool = false) -> int:
	var input := InputState.new()
	var wraps: int = 0
	var phase: float = _controller._skating.stride_phase
	for _i: int in ticks:
		var travel := Vector2(_skater.velocity.x, _skater.velocity.z)
		var ahead: Vector2 = travel.normalized() if travel.length() > 0.5 else Vector2(0.0, -1.0)
		input.move_vector = (ahead + Vector2(-ahead.y, ahead.x)).normalized() if arc else move
		input.mouse_world_pos = Vector3(_skater.global_position.x + ahead.x * 6.0, 0.0,
				_skater.global_position.z + ahead.y * 6.0)
		input.delta = DT
		_controller._process_input(input, DT)
		_skater.global_position += _skater.velocity * DT
		_skater._process(DT)
		_tick += 1
		var now: float = _controller._skating.stride_phase
		if now < phase - PI:
			wraps += 1
		phase = now
	return wraps


func test_each_leg_pushes_once_a_stride_and_the_legs_alternate() -> void:
	_skate(120, Vector2(0.0, -1.0))
	_events.clear()
	_touches.clear()
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
		assert_lt(e[2], e[1], "and pushes rather than digs")
	_assert_each_leg_lands_once_a_cycle(cycles, "stride")


func test_crossovers_land_each_skate_once_a_step() -> void:
	_skate(240, Vector2(0.0, -1.0))
	_skate(60, Vector2.ZERO, true)
	_events.clear()
	_touches.clear()
	var cycles: int = _skate(360, Vector2.ZERO, true)
	_assert_each_leg_lands_once_a_cycle(cycles, "crossovers")


func _assert_each_leg_lands_once_a_cycle(cycles: int, label: String) -> void:
	var lefts: int = 0
	var highest: float = 0.0
	for t: Array in _touches:
		if t[0]:
			lefts += 1
		highest = maxf(highest, t[1])
	gut.p("%s: %d cycles, %d landings (%d left), highest lift %.3f m"
			% [label, cycles, _touches.size(), lefts, highest])
	assert_almost_eq(lefts, cycles, 1, "%s: the left skate lands once a cycle" % label)
	assert_almost_eq(_touches.size() - lefts, cycles, 1, "%s: and the right" % label)


func test_a_coasting_skater_makes_no_push() -> void:
	_skate(240, Vector2(0.0, -1.0))
	_skate(60, Vector2.ZERO)
	_events.clear()
	_touches.clear()
	_skate(120, Vector2.ZERO)
	assert_eq(_events.size(), 0, "a glide is silent of pushes")
	assert_eq(_touches.size(), 0, "and of landings")


# A start's first push begins before the stroke has any strength: the dig, the
# acceleration it makes, is what it is heard by.
func test_the_first_push_of_a_start_is_heard_and_digs() -> void:
	_skate(30, Vector2(0.0, -1.0))
	assert_gt(_events.size(), 0, "a start pushes")
	var start: float = 0.0
	for e: Array in _events:
		start = maxf(start, maxf(e[1], e[2]))
		gut.p("start push: strength %.2f, dig %.2f" % [e[1], e[2]])
	assert_gt(_events[0][2], _events[0][1], "a start's first push is a dig")
	_skate(360, Vector2(0.0, -1.0))
	_events.clear()
	_skate(120, Vector2(0.0, -1.0))
	var cruise: float = 0.0
	for e: Array in _events:
		cruise = maxf(cruise, e[1])
	gut.p("push level: start %.2f, cruise %.2f" % [start, cruise])
	assert_gt(start, 0.05, "the start's first push is heard")
	assert_gt(cruise, 0.05, "the cruise pushes")


# A start steps quick and short, and its steps lengthen into the stride as the
# acceleration tapers off; a tempo keyed to speed alone draws it as one long
# push and then a cruise.
func test_a_start_chops_and_lengthens_into_the_stride() -> void:
	var times: Array[float] = []
	_skater.skate_pushed.connect(func(_l: bool, _s: float, _d: float) -> void:
		times.append(_tick * DT))
	_tick = 0
	_skate(480, Vector2(0.0, -1.0))
	var gaps: Array[String] = []
	for i: int in range(1, times.size()):
		gaps.append("%.2f" % (times[i] - times[i - 1]))
	gut.p("start: pushes at %s s; gaps %s" % [str(times), " ".join(gaps)])
	var early: int = 0
	for t: float in times:
		if t < 1.0:
			early += 1
	assert_gte(early, 4, "four or more pushes in the start's first second")
	assert_lt(times[2] - times[1], 0.35, "an early step is quick")
	assert_gt(times[times.size() - 1] - times[times.size() - 2], times[2] - times[1] + 0.2,
			"and the cruise's steps are longer")

