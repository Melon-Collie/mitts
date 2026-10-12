extends GutTest

# SkaterBoardPin: the victim's pin — refreshed by the host while the checker
# drives, worn down by its cap and the victim's work along the wall, then a
# window of immunity.

const DT: float = 1.0 / 120.0
const OUT := Vector2(1.0, 0.0)


func test_a_pin_lasts_only_while_the_checker_keeps_driving() -> void:
	var pin := SkaterBoardPin.new()
	pin.hold(0.5)
	assert_true(pin.is_pinned())
	for _i: int in ceili(BoardPinRules.PIN_GRIP_S / DT) + 1:
		pin.step(Vector3.ZERO, OUT, Vector2.ZERO, true, DT)
	assert_false(pin.is_pinned(), "the grip runs out a moment after he stops")


func test_a_held_pin_ends_at_its_cap_then_cannot_restart_at_once() -> void:
	var pin := SkaterBoardPin.new()
	var t: float = 0.0
	while t < BoardPinRules.PIN_MAX_S + 0.1:
		pin.hold(0.5)
		pin.step(Vector3.ZERO, OUT, Vector2.ZERO, true, DT)
		t += DT
	assert_false(pin.is_pinned(), "two seconds is the most any pin holds")
	pin.hold(0.5)
	assert_false(pin.is_pinned(), "and the checker cannot re-pin straight away")


func test_working_along_the_wall_gets_out_sooner() -> void:
	var still: float = _seconds_pinned(Vector2.ZERO)
	var working: float = _seconds_pinned(Vector2(0.0, 1.0))
	assert_lt(working, still)


func test_a_predicting_client_only_runs_the_grip_down() -> void:
	var pin := SkaterBoardPin.new()
	pin.adopt(0.1, 0.5)
	var v: Vector3 = pin.step(Vector3(0.0, 0.0, 3.0), OUT, Vector2.ZERO, false, DT)
	assert_lt(v.z, 3.0, "the slide still bleeds")
	assert_almost_eq(pin.timer, 0.1 - DT, 1e-6)


func _seconds_pinned(intent: Vector2) -> float:
	var pin := SkaterBoardPin.new()
	var t: float = 0.0
	pin.hold(0.5)
	while pin.is_pinned() and t < 5.0:
		pin.step(Vector3.ZERO, OUT, intent, true, DT)
		pin.hold(0.5)
		t += DT
	return t
