extends GutTest

# The settle lock (SkaterSettleGate on SkaterController): a hard catch leaves the
# carrier unable to act with the puck until the grant's deadline. Presses inside
# it queue, and the latest fires on the first unlocked input.

const State = SkaterStateMachine.State
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const T0: float = 10.0
const SETTLE_S: float = 0.2


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()
var _deadline_ms: int = 0


func before_each() -> void:
	var puck: Puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(puck)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 10.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_input = InputState.new()
	_input.host_timestamp = T0
	_tick(60)  # let the blade come to rest on its aim
	_deadline_ms = roundi((_input.host_timestamp + SETTLE_S) * 1000.0)
	_controller.on_puck_picked_up_network(_deadline_ms)


func _tick(count: int = 1, aim: Vector3 = Vector3(0.6, 0.0, -1.2)) -> void:
	for i: int in count:
		_input.delta = DT
		_input.host_timestamp += DT
		_input.mouse_world_pos = _skater.global_position + aim
		_controller._process_input(_input, DT)
		_skater._physics_process(DT)
		_input.shoot_pressed = false
		_input.slap_pressed = false
		_input.quick_pass_pressed = false
		_input.stick_lift_pressed = false


# Ticks until the next input would be the first one past the deadline, judged
# on the gate's own wire grid.
func _tick_to_deadline() -> void:
	while roundi((_input.host_timestamp + DT) * Constants.TIME_WIRE_SCALE) < _deadline_ms * 10:
		_tick()


func _state() -> int:
	return _controller._sm.get_state()


func test_presses_inside_the_settle_do_nothing() -> void:
	watch_signals(_controller)
	_input.shoot_pressed = true
	_tick()
	_input.slap_pressed = true
	_tick()
	_input.quick_pass_pressed = true
	_tick()
	_input.stick_lift_pressed = true
	_tick()
	assert_eq(_state(), State.SKATING_WITH_PUCK)
	assert_signal_not_emitted(_controller, "puck_release_requested")
	assert_signal_not_emitted(_controller, "nudge_requested")


func test_the_blade_holds_its_seat_while_settling() -> void:
	# Held in the skater's own frame: the body still turns to face the cursor and
	# the seat turns with it (a few cm of lag while the turn starts), but the
	# blade stops reaching for the cursor. Height is the carry's own hop. The seat
	# is the carry's, a tick in: the catch itself moves the blade beside the puck
	# and in to where both hands hold the stick. The lag grows with how far out
	# the blade sits (here ~1.1 m, through a 46° turn), and the turn also tightens
	# the two-handed reach along the seat, which brings it in another few cm;
	# chasing is ~0.8 m.
	_tick()
	var seat: Vector3 = _blade_in_body()
	_tick(19, Vector3(-1.2, 0.0, -0.4))
	assert_lt(_flat(_blade_in_body() - seat), 0.15,
			"the blade does not chase the cursor while settling")
	_tick_to_deadline()
	_tick(12, Vector3(-1.2, 0.0, -0.4))
	assert_gt(_flat(_blade_in_body() - seat), 0.2,
			"the blade follows the cursor once settled")


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _blade_in_body() -> Vector3:
	return _skater.global_transform.affine_inverse() * _skater.get_blade_contact_global()


func test_a_held_wrister_starts_as_the_settle_ends() -> void:
	_input.shoot_pressed = true
	_input.shoot_held = true
	_tick()
	_tick_to_deadline()
	assert_eq(_state(), State.SKATING_WITH_PUCK, "still settling on the last locked input")
	_tick()
	assert_eq(_state(), State.WRISTER_AIM, "the queued wrister starts on the first free input")


func test_a_tapped_pass_goes_as_the_settle_ends() -> void:
	watch_signals(_controller)
	_input.quick_pass_pressed = true
	_tick()
	_tick_to_deadline()
	assert_signal_not_emitted(_controller, "puck_release_requested")
	_tick()
	assert_signal_emitted(_controller, "puck_release_requested")
	assert_eq(_state(), State.FOLLOW_THROUGH)


func test_a_queued_nudge_fires_on_unlock() -> void:
	watch_signals(_controller)
	_input.stick_lift_pressed = true
	_tick()
	_tick_to_deadline()
	_tick()
	assert_signal_emitted(_controller, "nudge_requested")


func test_a_later_press_replaces_an_earlier_one() -> void:
	_input.shoot_pressed = true
	_tick()
	_input.slap_pressed = true
	_input.slap_held = true
	_tick()
	_tick_to_deadline()
	_tick()
	assert_eq(_state(), State.SLAPPER_CHARGE_WITH_PUCK)


func test_the_queued_press_leaves_the_input_as_it_came() -> void:
	_input.shoot_pressed = true
	_tick()
	_tick_to_deadline()
	_input.host_timestamp += DT
	_controller._process_input(_input, DT)
	assert_false(_input.shoot_pressed, "history and replay hold this object")


func test_losing_the_puck_drops_the_queue() -> void:
	_input.shoot_pressed = true
	_tick()
	_controller.on_puck_released_network()
	_controller.on_puck_picked_up_network(0)
	_tick()
	assert_eq(_state(), State.SKATING_WITH_PUCK, "a regrab does not fire the old press")


func test_a_clean_catch_acts_at_once() -> void:
	_controller.on_puck_released_network()
	_controller.on_puck_picked_up_network(0)
	_input.shoot_pressed = true
	_input.shoot_held = true
	_tick()
	assert_eq(_state(), State.WRISTER_AIM)


func test_a_one_timer_catch_is_not_locked() -> void:
	_controller.on_puck_released_network()
	_input.slap_pressed = true
	_input.slap_held = true
	_tick(30)
	assert_eq(_state(), State.SLAPPER_CHARGE_WITHOUT_PUCK)
	_controller.on_puck_picked_up_network(roundi((_input.host_timestamp + 0.3) * 1000.0))
	assert_eq(_state(), State.SLAPPER_CHARGE_WITH_PUCK, "caught straight into the charge")
	watch_signals(_controller)
	_input.slap_held = false
	_tick(int(_controller.one_timer_retention_time / DT) + 2)
	assert_true(get_signal_emit_count(_controller, "puck_release_requested") \
			+ get_signal_emit_count(_controller, "one_timer_release_requested") > 0,
			"the one-timer fires inside the settle")


func test_the_deadline_is_set_from_the_latest_input() -> void:
	var stamp: float = _controller._settle.last_stamp
	assert_eq(_controller.settle_deadline_ms(0.25), roundi((stamp + 0.25) * 1000.0),
			"no lag grace for a carrier on the host's own clock")


func test_the_blade_comes_home_as_the_settle_ends() -> void:
	_skater.trigger_reception_cushion(Vector3(-15.0, 0.0, 0.0), 0.8, 0.3)
	assert_almost_eq(_skater._reception_give_blend, 0.8, 0.0001, "the give is the catch's load")
	for i: int in int(0.28 / DT):
		_skater._physics_process(DT)
	assert_gt(_skater._reception_give_blend, 0.0, "still giving before the settle ends")
	for i: int in int(0.03 / DT):
		_skater._physics_process(DT)
	assert_eq(_skater._reception_give_blend, 0.0, "home as the settle ends")


func test_a_clean_catch_re_seats_at_the_fast_rate() -> void:
	_skater.trigger_reception_cushion(Vector3(-8.0, 0.0, 0.0), 0.2, 0.0)
	for i: int in int(0.2 / _skater.reception_give_decay / DT) + 2:
		_skater._physics_process(DT)
	assert_eq(_skater._reception_give_blend, 0.0)
