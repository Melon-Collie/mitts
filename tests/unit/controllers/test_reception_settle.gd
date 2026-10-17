extends GutTest

# The reception settle: after a hard catch nothing leaves the blade until the
# settle's end stamp, and a press made meanwhile fires on the first input past
# it. Drives SkaterStateMachine with stub callbacks, as test_one_timer_retention
# does, plus the ReceptionSettle it gates on.

const TICK: float = 1.0 / 120.0
const STATE = SkaterStateMachine.State

var _sm: SkaterStateMachine
var _settle: ReceptionSettle
var _passes: int = 0
var _slapper_entries: int = 0


func before_each() -> void:
	_passes = 0
	_slapper_entries = 0
	_settle = ReceptionSettle.new()
	_sm = _make_sm(_settle)


func _make_sm(settle: ReceptionSettle) -> SkaterStateMachine:
	var sm := SkaterStateMachine.new()
	var cb := SkaterStateMachine.Callbacks.new()
	var noop: Callable = func() -> void: pass
	var noop_1: Callable = func(_a: Variant) -> void: pass
	var noop_2: Callable = func(_a: Variant, _b: Variant) -> void: pass
	cb.apply_blade_from_mouse = noop_2
	cb.apply_wrister_aim_blade = noop_2
	cb.wrister_swing_seed = func(_i: Variant, _o: Variant) -> Vector3: return Vector3.FORWARD
	cb.apply_slapper_blade_position = noop
	cb.apply_block_blade_position = noop
	cb.apply_wrister_follow_through = noop
	cb.apply_slapper_follow_through = noop
	cb.enter_shot_block = noop
	cb.enter_slapper_charge = func(_i: Variant) -> void: _slapper_entries += 1
	cb.transition_to_skating = noop
	cb.release_wrister = noop_1
	cb.fire_quick_pass = func(_i: Variant) -> void: _passes += 1
	cb.update_wrister_charge = noop_1
	cb.update_slapper_charge = noop_1
	cb.apply_slapper_velocity_drag = noop_1
	cb.apply_block_movement = noop_2
	cb.release_slapper = noop_1
	cb.enter_one_timer_retention = noop
	cb.release_retained_one_timer = func(_i: Variant) -> Dictionary: return {fired = false}
	sm.setup(cb, SkaterAimingBehavior.new(), settle)
	sm.set_state(STATE.SKATING_WITH_PUCK)
	return sm


# One carry tick at input stamp `stamp_s`, the way SkaterController feeds it.
func _tick(sm: SkaterStateMachine, settle: ReceptionSettle, stamp_s: float,
		input: InputState) -> void:
	settle.observe(stamp_s)
	sm.dispatch(null, input, TICK, true, false)


func _quick_pass() -> InputState:
	var i := InputState.new()
	i.quick_pass_pressed = true
	return i


func test_no_settle_fires_at_once() -> void:
	_settle.observe(10.0)
	assert_eq(_settle.arm(0.0), 0, "nothing to settle sends no end stamp")
	_tick(_sm, _settle, 10.0 + TICK, _quick_pass())
	assert_eq(_passes, 1)


func test_a_press_while_settling_waits_for_the_end() -> void:
	_settle.observe(10.0)
	_settle.arm(0.1)
	_tick(_sm, _settle, 10.0 + TICK, _quick_pass())
	assert_eq(_passes, 0, "nothing leaves the blade while the catch settles")
	var t: float = 10.0 + 2.0 * TICK
	while t < 10.1 - 0.0001:
		_tick(_sm, _settle, t, InputState.new())
		t += TICK
	assert_eq(_passes, 0, "held, not fired, through the whole settle")
	_tick(_sm, _settle, t, InputState.new())
	assert_eq(_passes, 1, "the held press fires on the first input past the end")
	_tick(_sm, _settle, t + TICK, InputState.new())
	assert_eq(_passes, 1, "and only once")


func test_a_slapper_press_while_settling_starts_the_wind_up_at_the_end() -> void:
	_settle.observe(5.0)
	_settle.arm(0.05)
	var press := InputState.new()
	press.slap_pressed = true
	press.slap_held = true
	_tick(_sm, _settle, 5.0 + TICK, press)
	assert_eq(_slapper_entries, 0)
	var held := InputState.new()
	held.slap_held = true
	_tick(_sm, _settle, 5.06, held)
	assert_eq(_slapper_entries, 1)


func test_the_hands_are_free_once_the_settle_ends() -> void:
	_settle.observe(1.0)
	_settle.arm(0.05)
	assert_true(_settle.is_locked())
	assert_almost_eq(_settle.remaining_s(), 0.05, 0.0001)
	_settle.observe(1.05)
	assert_false(_settle.is_locked(), "the end stamp is exclusive")
	assert_eq(_settle.remaining_s(), 0.0)


func test_host_and_client_release_on_the_same_input() -> void:
	# The host arms on its grant tick; the client adopts the end stamp from the
	# pickup event a trip later, and both run the same input stream.
	var host_settle := ReceptionSettle.new()
	var host_sm: SkaterStateMachine = _make_sm(host_settle)
	host_settle.observe(20.0)
	var until: int = host_settle.arm(0.15)
	var client_settle := ReceptionSettle.new()
	var client_sm: SkaterStateMachine = _make_sm(client_settle)
	client_settle.adopt(until)
	var stamps: Array[float] = []
	var t: float = 20.0 + TICK
	while t < 20.25:
		stamps.append(t)
		t += TICK
	var host_fired_at: float = -1.0
	var client_fired_at: float = -1.0
	for i: int in stamps.size():
		var press: InputState = _quick_pass() if i == 3 else InputState.new()
		var before: int = _passes
		_tick(host_sm, host_settle, stamps[i], press)
		if _passes != before and host_fired_at < 0.0:
			host_fired_at = stamps[i]
		before = _passes
		_tick(client_sm, client_settle, stamps[i], press)
		if _passes != before and client_fired_at < 0.0:
			client_fired_at = stamps[i]
	assert_gt(host_fired_at, 20.15 - TICK)
	assert_eq(client_fired_at, host_fired_at)


func test_losing_the_puck_drops_the_held_press() -> void:
	_settle.observe(3.0)
	_settle.arm(0.1)
	_tick(_sm, _settle, 3.0 + TICK, _quick_pass())
	_settle.clear()
	_tick(_sm, _settle, 3.2, InputState.new())
	assert_eq(_passes, 0)


func test_a_replay_restores_the_live_settle() -> void:
	var saved := ReceptionSettle.new()
	_settle.observe(7.0)
	_settle.arm(0.1)
	_tick(_sm, _settle, 7.0 + TICK, _quick_pass())
	saved.copy_from(_settle)
	# A replay walks the stamps past the end and fires the held press...
	_tick(_sm, _settle, 7.2, InputState.new())
	# ...and the live settle comes back untouched.
	_settle.copy_from(saved)
	assert_eq(_settle.until_units, saved.until_units)
	assert_true(_settle.held_quick_pass)
	assert_true(_settle.is_locked())
