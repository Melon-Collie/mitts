extends GutTest

# GoalieScreenDepth.sight_cap: the furthest out along his challenge ray from
# which the peek still clears the bodies hiding the release.

const GOAL := Vector3(0, 0, 0)
const SHOOTER := Vector3(0, 0, 18)
const MAX_PEEK: float = 0.5


func _cfg() -> GoalieBehaviorRules.ScreenConfig:
	var c := GoalieBehaviorRules.ScreenConfig.new()
	c.eye_height = 1.79
	return c


func _cap(screener: Vector3, r_hi: float = 1.75) -> float:
	return GoalieScreenDepth.sight_cap(GOAL, SHOOTER, SHOOTER,
			PackedVector3Array([screener, SHOOTER]), _cfg(), MAX_PEEK, r_hi, 0.1)


func test_a_screener_on_top_of_him_backs_him_off_until_he_can_see_around() -> void:
	var cap: float = _cap(Vector3(0, 0, 2.0))
	assert_lt(cap, 1.75, "chest to chest at 1.75, the body fills the view")
	assert_gt(cap, 1.0, "and he gives up only the room he needs")
	# Closed loop: from the cap, the peek really clears it.
	var g := Vector3(0, 0, cap)
	var peek: float = GoalieBehaviorRules.screen_peek_offset(g, SHOOTER,
			PackedVector3Array([Vector3(0, 0, 2.0), SHOOTER]), _cfg(), MAX_PEEK)
	var eye: Vector3 = g + Vector3(peek, 0, 0)
	assert_eq(GoalieBehaviorRules.screen_occlusion_delay(SHOOTER, eye - SHOOTER, eye,
			PackedVector3Array([Vector3(0, 0, 2.0), SHOOTER]), _cfg()), 0.0)


func test_a_screener_he_can_already_see_around_changes_nothing() -> void:
	assert_true(is_inf(_cap(Vector3(0, 0, 3.0))), "tight to the screen is already right")
	assert_true(is_inf(_cap(Vector3(2.0, 0, 5.0))), "off the line is no screen at all")


func test_a_screen_he_cannot_see_around_from_anywhere_is_not_a_retreat() -> void:
	# Dead on at 7 m: no radius clears it, so backing in buys nothing — the
	# blocking drop answers a release he never saw.
	assert_true(is_inf(_cap(Vector3(0, 0, 7.0))))


func test_no_screeners_no_cap() -> void:
	assert_true(is_inf(GoalieScreenDepth.sight_cap(GOAL, SHOOTER, SHOOTER,
			PackedVector3Array(), _cfg(), MAX_PEEK, 1.75, 0.1)))
