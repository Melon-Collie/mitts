extends GutTest

# PenaltyShotAttempt — a penalty shot stepped tick by tick: nothing is judged
# until the shooter has the puck, he has to keep driving, and a match's shot is
# over the moment the puck stops going at the net. Team 0's shooter: -Z is in.

const TICK: float = 1.0 / 90.0
const ATTACK: float = -1.0
const GOAL_LINE: float = -GameRules.GOAL_LINE_Z
const LIVE := PenaltyShotRules.Outcome.LIVE
const GOAL := PenaltyShotRules.Outcome.GOAL
const MISS := PenaltyShotRules.Outcome.MISS

var _attempt: PenaltyShotAttempt
var _z: float = 0.0


func before_each() -> void:
	_attempt = PenaltyShotAttempt.new()
	_attempt.begin(ATTACK, GOAL_LINE, GameRules.NET_HALF_WIDTH)
	_z = 0.0


# The shooter carries at `speed` toward the net for `seconds`; the last outcome.
func _carry(seconds: float, speed: float) -> PenaltyShotRules.Outcome:
	var outcome: PenaltyShotRules.Outcome = LIVE
	var t: float = 0.0
	while t < seconds and outcome == LIVE:
		_z += ATTACK * speed * TICK
		outcome = _attempt.step(TICK, _z, true, Vector3(0.0, 0.05, _z - 0.5), ATTACK * speed)
		t += TICK
	return outcome


# The puck is off his blade at `puck_z`, moving `vel_z` along Z, for `seconds`.
func _in_flight(seconds: float, puck_z: float, vel_z: float,
		puck_x: float = 0.0) -> PenaltyShotRules.Outcome:
	var outcome: PenaltyShotRules.Outcome = LIVE
	var t: float = 0.0
	while t < seconds and outcome == LIVE:
		outcome = _attempt.step(TICK, _z, false, Vector3(puck_x, 0.05, puck_z), vel_z)
		t += TICK
	return outcome


# ── Before the pickup ────────────────────────────────────────────────────────

func test_nothing_is_judged_until_he_has_the_puck() -> void:
	for i: int in 300:
		assert_eq(_attempt.step(TICK, 0.0, false, Vector3(0.0, 0.05, -1.2), 0.0), LIVE)


func test_a_shooter_who_never_collects_it_runs_out_of_time() -> void:
	_attempt.max_wait_s = 1.0
	var outcome: PenaltyShotRules.Outcome = LIVE
	for i: int in 100:
		outcome = _attempt.step(TICK, 0.0, false, Vector3(0.0, 0.05, -1.2), 0.0)
	assert_eq(outcome, MISS)


# ── The rush ─────────────────────────────────────────────────────────────────

func test_a_shooter_driving_the_net_stays_live() -> void:
	assert_eq(_carry(2.0, 6.0), LIVE)


func test_a_shooter_who_stops_is_done() -> void:
	_carry(1.5, 6.0)
	assert_eq(_carry(2.0, 0.0), MISS)


func test_a_shooter_who_turns_back_is_done() -> void:
	_carry(1.5, 6.0)
	assert_eq(_carry(2.0, -3.0), MISS)


# ── The shot ─────────────────────────────────────────────────────────────────

func test_a_puck_across_the_line_inside_the_posts_is_a_goal() -> void:
	_carry(1.5, 6.0)
	assert_eq(_in_flight(0.1, GOAL_LINE - 0.5, -20.0), GOAL)


func test_a_puck_across_the_line_wide_is_a_miss() -> void:
	_carry(1.5, 6.0)
	assert_eq(_in_flight(0.1, GOAL_LINE - 0.5, -20.0, GameRules.NET_HALF_WIDTH + 1.0), MISS)


func test_the_drill_lets_a_saved_shot_play_on() -> void:
	_carry(1.5, 6.0)
	assert_eq(_in_flight(3.0, GOAL_LINE + 1.0, 4.0), LIVE,
			"kicked back out, and the drill waits for it")


func test_a_matchs_shot_is_over_once_it_is_kicked_back_out() -> void:
	_attempt.ends_when_shot_dies = true
	_carry(1.5, 6.0)
	assert_eq(_in_flight(1.0, GOAL_LINE + 1.0, 4.0), MISS)


func test_a_matchs_shot_still_going_at_the_net_is_live() -> void:
	_attempt.ends_when_shot_dies = true
	_carry(1.5, 6.0)
	assert_eq(_in_flight(0.5, GOAL_LINE + 6.0, -15.0), LIVE)


func test_a_shot_off_the_goalie_and_in_still_counts() -> void:
	_attempt.ends_when_shot_dies = true
	_carry(1.5, 6.0)
	_in_flight(0.3, GOAL_LINE + 1.0, -2.0)
	assert_eq(_in_flight(0.1, GOAL_LINE - 0.5, -2.0), GOAL, "trickling in is still going in")


func test_an_attempt_that_never_resolves_times_out() -> void:
	_attempt.max_live_s = 2.0
	_carry(1.0, 6.0)
	assert_eq(_in_flight(3.0, GOAL_LINE + 6.0, -1.0), MISS)


# ── The shot is dead ─────────────────────────────────────────────────────────

func test_a_shot_is_not_read_on_the_tick_it_leaves() -> void:
	assert_false(PenaltyShotRules.shot_is_dead(0.0, ATTACK, 0.0))


func test_a_shot_has_only_so_long() -> void:
	assert_true(PenaltyShotRules.shot_is_dead(-20.0, ATTACK, PenaltyShotRules.SHOT_MAX_FLIGHT_S))
