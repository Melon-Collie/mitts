extends GutTest

# BufferedStateInterpolator.intake — how every client snapshot buffer admits a
# host-capture-stamped state. A host catch-up runs physics steps back to back
# inside one frame and labels snapshots with its millisecond wall clock, so two
# broadcasts can share a label; the later one is the later tick.


func _entry(ts: float, state: Variant) -> BufferedGoalieState:
	var e := BufferedGoalieState.new()
	e.timestamp = ts
	e.state = state
	return e


func test_an_empty_buffer_appends() -> void:
	assert_eq(BufferedStateInterpolator.intake([], 1.0, GoalieNetworkState.new()),
			BufferedStateInterpolator.Intake.APPEND)


func test_a_newer_stamp_appends() -> void:
	var buf: Array = [_entry(1.0, GoalieNetworkState.new())]
	assert_eq(BufferedStateInterpolator.intake(buf, 1.02, GoalieNetworkState.new()),
			BufferedStateInterpolator.Intake.APPEND)


func test_an_older_stamp_is_out_of_order() -> void:
	var first := GoalieNetworkState.new()
	var buf: Array = [_entry(1.0, first)]
	assert_eq(BufferedStateInterpolator.intake(buf, 0.98, GoalieNetworkState.new()),
			BufferedStateInterpolator.Intake.OUT_OF_ORDER)
	assert_same(buf[0].state, first, "an out-of-order state never lands")


func test_an_equal_stamp_takes_the_newest_place() -> void:
	var later := GoalieNetworkState.new()
	var buf: Array = [_entry(0.98, GoalieNetworkState.new()), _entry(1.0, GoalieNetworkState.new())]
	assert_eq(BufferedStateInterpolator.intake(buf, 1.0, later),
			BufferedStateInterpolator.Intake.REPLACED)
	assert_eq(buf.size(), 2, "no zero-length bracket")
	assert_same(buf[1].state, later, "the later tick's state is the one drawn")

