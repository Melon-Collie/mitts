extends GutTest

# StuckPuckWatchdog — a settled loose puck on the net frame or in the crease.

const DT: float = 1.0 / 120.0
const SLOW: float = 0.1
const CREASE_PUCK := Vector3(0.4, 0.0, GameRules.GOAL_LINE_Z - 0.3)
const ON_THE_LINE := Vector3(0.2, 0.0, GameRules.GOAL_LINE_Z + 0.03)
const ON_NET_LOW := Vector3(0.0, 0.2, GameRules.GOAL_LINE_Z + 0.6)
const ON_NET_HIGH := Vector3(0.0, 1.2, GameRules.GOAL_LINE_Z + 0.6)
const SLOT := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z - 6.0)

var _dog: StuckPuckWatchdog


func before_each() -> void:
	_dog = StuckPuckWatchdog.new()


# Ticks `seconds` of the same puck; returns the first non-NONE verdict.
func _hold(seconds: float, pos: Vector3, speed: float = SLOW,
		held: bool = false) -> StuckPuckWatchdog.Verdict:
	var airborne: bool = pos.y > GameRules.PUCK_AIRBORNE_HEIGHT_M
	for i: int in int(ceil(seconds / DT)):
		var v: StuckPuckWatchdog.Verdict = _dog.tick(DT, pos, speed, pos.y, airborne, held)
		if v != StuckPuckWatchdog.Verdict.NONE:
			return v
	return StuckPuckWatchdog.Verdict.NONE


func test_a_puck_dead_in_the_crease_is_frozen_after_the_grace() -> void:
	assert_eq(_hold(GameRules.CREASE_STUCK_GRACE_DURATION - 0.05, CREASE_PUCK),
			StuckPuckWatchdog.Verdict.NONE, "not before the grace")
	assert_eq(_hold(0.1, CREASE_PUCK), StuckPuckWatchdog.Verdict.FROZEN)


func test_a_puck_on_the_goal_line_not_yet_in_is_frozen_too() -> void:
	assert_eq(_hold(GameRules.CREASE_STUCK_GRACE_DURATION + 0.05, ON_THE_LINE),
			StuckPuckWatchdog.Verdict.FROZEN)


func test_a_puck_resting_on_the_goalie_above_the_ice_is_frozen() -> void:
	var on_pad := Vector3(CREASE_PUCK.x, 0.3, CREASE_PUCK.z)
	assert_eq(_hold(GameRules.CREASE_STUCK_GRACE_DURATION + 0.05, on_pad),
			StuckPuckWatchdog.Verdict.FROZEN)


func test_a_held_puck_never_freezes() -> void:
	assert_eq(_hold(5.0, CREASE_PUCK, SLOW, true), StuckPuckWatchdog.Verdict.NONE,
			"a covered or caught puck is the goalie's own stoppage")


func test_a_moving_puck_resets_the_clock() -> void:
	_hold(GameRules.CREASE_STUCK_GRACE_DURATION - 0.1, CREASE_PUCK)
	_hold(DT, CREASE_PUCK, GameRules.NET_STUCK_MAX_SPEED + 0.5)
	assert_eq(_hold(GameRules.CREASE_STUCK_GRACE_DURATION - 0.1, CREASE_PUCK),
			StuckPuckWatchdog.Verdict.NONE)


func test_leaving_the_crease_resets_the_clock() -> void:
	_hold(GameRules.CREASE_STUCK_GRACE_DURATION - 0.1, CREASE_PUCK)
	_hold(DT, SLOT)
	assert_eq(_hold(GameRules.CREASE_STUCK_GRACE_DURATION - 0.1, CREASE_PUCK),
			StuckPuckWatchdog.Verdict.NONE)


func test_a_settled_puck_outside_the_crease_is_left_alone() -> void:
	assert_eq(_hold(10.0, SLOT), StuckPuckWatchdog.Verdict.NONE)


func test_low_on_the_net_frame_drops_to_the_ice() -> void:
	assert_eq(_hold(GameRules.NET_STUCK_GRACE_DURATION + 0.05, ON_NET_LOW),
			StuckPuckWatchdog.Verdict.DROP_TO_ICE)


func test_high_on_the_net_frame_is_out_of_play() -> void:
	assert_eq(_hold(GameRules.NET_STUCK_GRACE_DURATION + 0.05, ON_NET_HIGH),
			StuckPuckWatchdog.Verdict.OUT_OF_PLAY)


func test_reset_clears_both_clocks() -> void:
	_hold(GameRules.CREASE_STUCK_GRACE_DURATION - 0.1, CREASE_PUCK)
	_dog.reset()
	assert_eq(_hold(GameRules.CREASE_STUCK_GRACE_DURATION - 0.1, CREASE_PUCK),
			StuckPuckWatchdog.Verdict.NONE)


# The whistle faces off at the nearest dot; from either crease that is the
# defending zone's end dot on the puck's side, never a neutral-zone dot.
func test_a_crease_freeze_faces_off_in_that_zone() -> void:
	for z_sign: float in [1.0, -1.0]:
		for x: float in [-1.0, 1.0]:
			var dot: Vector2 = GameRules.nearest_faceoff_dot(
					Vector2(x, z_sign * (GameRules.GOAL_LINE_Z - 0.5)))
			assert_eq(dot, Vector2(signf(x) * GameRules.END_ZONE_FACEOFF_DOT_X,
					z_sign * GameRules.ICING_FACEOFF_DOT_Z))
