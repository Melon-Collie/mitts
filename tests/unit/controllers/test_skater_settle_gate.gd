extends GutTest

# SkaterSettleGate on its own: the deadline is judged on the input-stamp wire
# grid, so a client's predicted stamp and the host's decoded copy of it settle
# the same input.

const Press = SkaterSettleGate.Press


func test_client_and_host_stamps_agree_at_the_deadline() -> void:
	var gate := SkaterSettleGate.new()
	gate.arm(12345)
	var input := InputState.new()
	# Raw predicted stamps straddling the deadline by fractions of the wire grid.
	for i: int in range(-30, 31):
		var raw: float = 12.345 + i * 0.000013
		input.host_timestamp = raw
		var decoded: InputState = InputState.from_bytes(input.to_bytes())
		assert_eq(gate.is_settling(raw), gate.is_settling(decoded.host_timestamp),
				"stamp %.7f" % raw)


func test_disarmed_never_settles() -> void:
	var gate := SkaterSettleGate.new()
	assert_false(gate.is_settling(0.0))
	gate.arm(5000)
	gate.clear()
	assert_false(gate.is_settling(1.0))
	assert_eq(gate.time_left(1.0), 0.0)


func test_time_left_runs_out_at_the_deadline() -> void:
	var gate := SkaterSettleGate.new()
	gate.arm(2500)
	assert_almost_eq(gate.time_left(2.3), 0.2, 0.0001)
	assert_eq(gate.time_left(2.6), 0.0)


func test_latest_press_wins_and_take_empties() -> void:
	var gate := SkaterSettleGate.new()
	var input := InputState.new()
	input.shoot_pressed = true
	gate.note(input)
	input.shoot_pressed = false
	input.stick_lift_pressed = true
	gate.note(input)
	assert_eq(gate.take(), Press.NUDGE)
	assert_eq(gate.take(), Press.NONE)


func test_a_pressless_input_keeps_the_queue() -> void:
	var gate := SkaterSettleGate.new()
	var input := InputState.new()
	input.quick_pass_pressed = true
	gate.note(input)
	gate.note(InputState.new())
	assert_eq(gate.queued, Press.PASS)


func test_arming_a_new_catch_drops_an_old_press() -> void:
	var gate := SkaterSettleGate.new()
	var input := InputState.new()
	input.slap_pressed = true
	gate.note(input)
	gate.arm(100)
	assert_eq(gate.queued, Press.NONE)


func test_presses_before_the_carrier_could_know_are_not_queued() -> void:
	# The host grants at 2.0 for a client 0.1 s behind (its grace): the lock opens
	# at once, but presses only queue from the client's earliest notice.
	var gate := SkaterSettleGate.new()
	var input := InputState.new()
	input.host_timestamp = 2.0
	gate.read(input, false)
	var grace: float = 0.1
	gate.arm(gate.deadline_ms(0.3, grace))
	var notice: float = 2.0 + grace - 1.0 / float(Constants.STATE_RATE)
	input.shoot_pressed = true
	input.host_timestamp = notice - 0.01
	gate.read(input, true)
	assert_true(gate.settling, "locked from the grant")
	assert_eq(gate.queued, Press.NONE, "a puckless press on the carrier's own screen")
	input.host_timestamp = notice + 0.01
	gate.read(input, true)
	assert_eq(gate.queued, Press.WRISTER)


func test_the_deadline_is_the_grant_stamp_plus_grace_plus_settle() -> void:
	var gate := SkaterSettleGate.new()
	var input := InputState.new()
	input.host_timestamp = 4.0
	gate.read(input, false)
	assert_eq(gate.deadline_ms(0.0, 0.1), 0, "a clean catch has no deadline")
	assert_eq(gate.deadline_ms(0.25, 0.1), 4350)


func test_a_read_past_the_deadline_releases_the_queue_once() -> void:
	var gate := SkaterSettleGate.new()
	gate.arm(1000)
	var input := InputState.new()
	input.host_timestamp = 0.9
	input.slap_pressed = true
	gate.read(input, true)
	input.slap_pressed = false
	input.host_timestamp = 1.0
	gate.read(input, true)
	assert_false(gate.settling)
	assert_eq(gate.unqueued, Press.SLAP)
	input.host_timestamp = 1.01
	gate.read(input, true)
	assert_eq(gate.unqueued, Press.NONE)
