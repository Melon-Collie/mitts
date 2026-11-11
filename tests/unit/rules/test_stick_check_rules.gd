extends GutTest

# The stick lift's phase machine (StickCheckRules.step). Every transition reads
# only the skater's own inputs, so these pin the whole lifecycle a host and a
# predicting client must step identically.

const Phase = StickCheckRules.Phase
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


# Steps the machine `ticks` times with the button `held` (and pressed on the
# first tick if `press`), returning the final (phase, elapsed).
func _run(phase: int, elapsed: float, ticks: int, held: bool, press: bool = false,
		can_start: bool = true) -> Vector2:
	var state := Vector2(phase, elapsed)
	for i: int in ticks:
		state = StickCheckRules.step(int(state.x), state.y, press and i == 0, held,
				can_start, false, DT)
	return state


func _ticks(seconds: float) -> int:
	return ceili(seconds / DT) + 1


func test_a_press_raises_the_blade_then_hooks() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true, true)
	assert_eq(int(s.x), Phase.RISE)
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.RISE_S), true)
	assert_eq(int(s.x), Phase.HOOK)


func test_letting_go_drops_the_blade_fast_then_rearms() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true, true)
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.RISE_S), true)
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.HOOK_MIN_S), false)
	assert_eq(int(s.x), Phase.DROP, "a release after the minimum hook drops the blade")
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.DROP_S), false)
	assert_eq(int(s.x), Phase.REARM)
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.REARM_S), false)
	assert_eq(int(s.x), Phase.IDLE)


func test_a_tap_still_gets_the_minimum_hook() -> void:
	# Pressed and released inside one tick: the rise and the minimum hook run
	# anyway, so the shortest tap can land a lift.
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, false, true)
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.RISE_S), false)
	assert_eq(int(s.x), Phase.HOOK)
	s = _run(int(s.x), s.y, 1, false)
	assert_eq(int(s.x), Phase.HOOK, "the hook is held open to HOOK_MIN_S")


func test_holding_past_the_hook_becomes_a_tie() -> void:
	var s: Vector2 = _run(Phase.IDLE, 0.0, 1, true, true)
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.RISE_S), true)
	s = _run(int(s.x), s.y, _ticks(StickCheckRules.HOOK_MAX_S), true)
	assert_eq(int(s.x), Phase.TIE, "held past the hook, the stick stays out as a tie")
	s = _run(int(s.x), s.y, 1, false)
	assert_eq(int(s.x), Phase.DROP, "letting go of a tie drops the blade")


func test_a_tie_reaches_for_as_long_as_it_is_held() -> void:
	var s: Vector2 = _run(Phase.TIE, 0.0, _ticks(5.0), true)
	assert_eq(int(s.x), Phase.TIE, "a tie has no time limit; only the button ends it")


func test_a_press_is_ignored_until_rearmed() -> void:
	var s: Vector2 = StickCheckRules.step(Phase.REARM, 0.0, true, true, true, false, DT)
	assert_eq(int(s.x), Phase.REARM)
	s = StickCheckRules.step(Phase.IDLE, 0.0, true, true, false, false, DT)
	assert_eq(int(s.x), Phase.IDLE, "no lift starts while the stick is taken")


func test_an_interruption_ends_any_phase() -> void:
	for phase: int in Phase.values():
		var s: Vector2 = StickCheckRules.step(phase, 0.03, false, true, true, true, DT)
		assert_eq(int(s.x), Phase.IDLE, "phase %d" % phase)


func test_only_the_lifting_phases_take_the_stick_off_the_puck() -> void:
	var busy: Array[int] = []
	var raised: Array[int] = []
	for phase: int in Phase.values():
		if StickCheckRules.is_stick_busy(phase):
			busy.append(phase)
		if StickCheckRules.is_blade_raised(phase):
			raised.append(phase)
	assert_eq(busy, [Phase.RISE, Phase.HOOK, Phase.TIE] as Array[int],
			"the drop plays the puck: it is the take")
	assert_eq(raised, [Phase.RISE, Phase.HOOK, Phase.TIE] as Array[int])


func test_a_tied_stick_is_held_up_at_the_lift_height_whatever_its_phase() -> void:
	for phase: int in Phase.values():
		assert_true(StickCheckRules.blade_held_up(false, phase, true), "phase %d" % phase)
		assert_true(StickCheckRules.uses_lift_height(phase, true), "phase %d" % phase)
	assert_false(StickCheckRules.blade_held_up(false, Phase.IDLE, false))
	assert_false(StickCheckRules.uses_lift_height(Phase.REARM, false))


func test_every_phase_fits_the_wire() -> void:
	# The u8 packs whole ticks in five bits; a timed phase that ran longer would
	# reconcile to the wrong point in it. The tie has no timed edge, so its count
	# saturating is harmless.
	for seconds: float in [StickCheckRules.RISE_S, StickCheckRules.HOOK_MAX_S,
			StickCheckRules.DROP_S, StickCheckRules.REARM_S]:
		assert_lte(roundi(seconds * 120.0), 31, "%.2f s" % seconds)
	for phase: int in Phase.values():
		var b: int = StickCheckRules.pack(phase, 0.1)
		assert_eq(StickCheckRules.unpack_phase(b), phase)
		assert_almost_eq(StickCheckRules.unpack_elapsed(b), 0.1, 0.5 / 120.0)
	var long_tie: int = StickCheckRules.pack(Phase.TIE, 3.0)
	assert_eq(StickCheckRules.unpack_phase(long_tie), Phase.TIE)


func test_stick_gap_is_plan_view_segment_to_segment() -> void:
	var up := Vector3(0.0, 1.0, 0.0)
	# Crossing in plan view touches, whatever the heights.
	assert_eq(StickCheckRules.stick_gap(Vector3(-1, 0, 0) + up, Vector3(1, 0, 0),
			Vector3(0, 0, -1), Vector3(0, 0, 1) + up), 0.0)
	# Parallel sticks half a metre apart.
	assert_almost_eq(StickCheckRules.stick_gap(Vector3(0, 1, 0), Vector3(1, 0, 0),
			Vector3(0, 0, 0.5), Vector3(1, 0, 0.5)), 0.5, 1e-6)
	# End to end along one line.
	assert_almost_eq(StickCheckRules.stick_gap(Vector3(0, 0, 0), Vector3(1, 0, 0),
			Vector3(1.3, 0, 0), Vector3(2, 0, 0)), 0.3, 1e-6)
	# A blade tip beside the middle of a shaft.
	assert_almost_eq(StickCheckRules.stick_gap(Vector3(0, 0, 2), Vector3(0, 0, 0.2),
			Vector3(-1, 0, 0), Vector3(1, 0, 0)), 0.2, 1e-6)


func test_hook_quality_grades_by_distance_to_the_shaft() -> void:
	assert_eq(StickCheckRules.hook_quality(0.0, 0.45), 1.0)
	assert_eq(StickCheckRules.hook_quality(0.45, 0.45), 0.0)
	assert_almost_eq(StickCheckRules.hook_quality(0.225, 0.45), 0.5, 1e-6)
	assert_eq(StickCheckRules.hook_quality(0.9, 0.45), 0.0, "clamped past the rim")


func test_a_clean_hook_holds_the_stick_up_longer() -> void:
	assert_eq(StickCheckRules.forced_lift_seconds(0.0), StickCheckRules.FORCED_LIFT_MIN_S)
	assert_eq(StickCheckRules.forced_lift_seconds(1.0), StickCheckRules.FORCED_LIFT_MAX_S)
	# The lifter's whole sequence fits inside even the shortest forced lift, so
	# a landed hook always leaves a window to take the puck.
	assert_lt(StickCheckRules.HOOK_MAX_S + StickCheckRules.DROP_S,
			StickCheckRules.FORCED_LIFT_MIN_S)
