extends GutTest

# The timed check's phase machine and kick (CheckDriveRules). Every transition
# reads only the skater's own button and whether he may commit, so these pin the
# lifecycle a host and a predicting client must step identically.

const Phase = CheckDriveRules.Phase
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


func _run(phase: int, elapsed: float, ticks: int, held: bool,
		eligible: bool = true) -> Vector2:
	var state := Vector2(phase, elapsed)
	for i: int in ticks:
		state = CheckDriveRules.step(int(state.x), state.y, held, eligible, DT)
	return state


func _ticks(seconds: float) -> int:
	return ceili(seconds / DT) + 1


func test_a_press_drives_for_its_window_then_is_spent() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true)
	assert_eq(int(s.x), Phase.DRIVE)
	s = _run(int(s.x), s.y, _ticks(CheckDriveRules.DRIVE_S) - 3, true)
	assert_eq(int(s.x), Phase.DRIVE, "still inside the window")
	s = _run(int(s.x), s.y, 4, true)
	assert_eq(int(s.x), Phase.SPENT)


func test_a_tap_drives_its_whole_window() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true)
	s = _run(int(s.x), s.y, _ticks(CheckDriveRules.DRIVE_S) - 3, false)
	assert_eq(int(s.x), Phase.DRIVE)


func test_holding_never_drives_again() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true)
	s = _run(int(s.x), s.y, _ticks(CheckDriveRules.DRIVE_S + 5.0 * CheckDriveRules.REARM_S), true)
	assert_eq(int(s.x), Phase.SPENT, "a held button is the first drive held, not a second")
	s = _run(int(s.x), s.y, 1, false)
	assert_eq(int(s.x), Phase.IDLE, "and re-arms the tick it is let go")


func test_a_second_press_inside_the_rearm_does_not_drive() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true)
	s = _run(int(s.x), s.y, _ticks(CheckDriveRules.DRIVE_S), false)
	assert_eq(int(s.x), Phase.SPENT)
	s = _run(int(s.x), s.y, 2, true)
	assert_eq(int(s.x), Phase.SPENT)
	s = _run(int(s.x), s.y, _ticks(CheckDriveRules.REARM_S), false)
	assert_eq(int(s.x), Phase.IDLE)
	s = _run(int(s.x), s.y, 1, true)
	assert_eq(int(s.x), Phase.DRIVE)


func test_a_press_he_cannot_act_on_is_spent_not_saved() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true, false)
	assert_eq(int(s.x), Phase.SPENT)
	s = _run(int(s.x), s.y, 30, true, true)
	assert_eq(int(s.x), Phase.SPENT, "becoming able to, button still down, throws nothing")
	s = _run(int(s.x), s.y, 1, false, true)
	assert_eq(int(s.x), Phase.IDLE, "a brace costs no rearm once it is let go")


func test_losing_the_commit_ends_the_drive() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 3, true)
	s = _run(int(s.x), s.y, 1, true, false)
	assert_eq(int(s.x), Phase.SPENT)


func test_the_wire_round_trips_every_tick_of_every_phase() -> void:
	for phase: int in [Phase.IDLE, Phase.DRIVE, Phase.SPENT]:
		var span: float = CheckDriveRules.DRIVE_S if phase == Phase.DRIVE \
				else CheckDriveRules.REARM_S
		var elapsed: float = 0.0
		while elapsed <= span + 0.5 * DT:
			var packed: int = CheckDriveRules.pack(phase, elapsed)
			assert_between(packed, 0, 255)
			assert_eq(CheckDriveRules.unpack_phase(packed), phase)
			assert_almost_eq(CheckDriveRules.unpack_elapsed(packed), elapsed, 0.5 * DT + 1e-6)
			elapsed += DT


func test_an_unknown_phase_decodes_idle() -> void:
	assert_eq(CheckDriveRules.unpack_phase(0x03), Phase.IDLE)


func test_the_kick_is_the_strides_force_on_the_other_mans_mass() -> void:
	var equal: float = CheckDriveRules.kick_dv(10.0, 1.0, 1.0)
	assert_almost_eq(equal, 10.0 * CheckDriveRules.PUSH_S, 1e-6)
	assert_gt(CheckDriveRules.kick_dv(10.0, 1.3, 1.0), equal, "a heavier checker kicks harder")
	assert_lt(CheckDriveRules.kick_dv(10.0, 1.0, 1.3), equal, "a heavier man is moved less")


func test_a_held_shoulder_delivers_between_the_bump_and_the_drive() -> void:
	assert_gt(CheckDriveRules.HELD_SHARE, PressRules.PASSIVE_DRIVE_SHARE)
	assert_lt(CheckDriveRules.HELD_SHARE, 1.0)
