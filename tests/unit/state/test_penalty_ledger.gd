extends GutTest

# PenaltyLedger — calls, minors, the queue and the release on a goal.

const BOARDING: int = PenaltyRules.Foul.BOARDING
const MINOR: float = 24.0
const SIZE: int = 5
const MAX_SERVING: int = 2

var ledger: PenaltyLedger


func before_each() -> void:
	ledger = PenaltyLedger.new()


func _box(peer_id: int, team_id: int) -> void:
	ledger.call_foul(peer_id, team_id, BOARDING)
	ledger.assess(MINOR, MAX_SERVING)


# ── The call ─────────────────────────────────────────────────────────────────

func test_a_called_foul_is_pending_and_boxes_nobody() -> void:
	assert_true(ledger.call_foul(10, 0, BOARDING))
	assert_true(ledger.has_pending())
	assert_true(ledger.has_pending_against(0))
	assert_false(ledger.has_pending_against(1))
	assert_false(ledger.is_boxed(10))
	assert_eq(ledger.strength(0, SIZE), SIZE, "play goes on at full strength")


func test_a_man_already_called_is_not_called_again() -> void:
	ledger.call_foul(10, 0, BOARDING)
	assert_false(ledger.call_foul(10, 0, PenaltyRules.Foul.INTERFERENCE))
	assert_eq(ledger.entries.size(), 1)


func test_a_goal_by_the_fouled_team_washes_out_the_oldest_call() -> void:
	ledger.call_foul(10, 0, BOARDING)
	ledger.call_foul(11, 0, BOARDING)
	assert_eq(ledger.waive_one_against(0), 10)
	assert_eq(ledger.waive_one_against(1), -1)
	assert_eq(ledger.assess(MINOR, MAX_SERVING), [11] as Array[int])


# ── Serving ──────────────────────────────────────────────────────────────────

func test_an_assessed_minor_puts_the_team_a_man_short() -> void:
	ledger.call_foul(10, 0, BOARDING)
	assert_eq(ledger.assess(MINOR, MAX_SERVING), [10] as Array[int])
	assert_false(ledger.has_pending())
	assert_true(ledger.is_boxed(10))
	assert_eq(ledger.strength(0, SIZE), SIZE - 1)
	assert_eq(ledger.strength(1, SIZE), SIZE)
	assert_almost_eq(ledger.soonest_remaining(0), MINOR, 0.0001)
	assert_eq(ledger.soonest_remaining(1), -1.0)


func test_a_minor_runs_out_and_releases_its_man() -> void:
	_box(10, 0)
	assert_eq(ledger.tick(MINOR - 0.1, MAX_SERVING).size(), 0)
	assert_eq(ledger.tick(0.2, MAX_SERVING), [10] as Array[int])
	assert_false(ledger.is_boxed(10))
	assert_eq(ledger.strength(0, SIZE), SIZE)


func test_a_third_minor_waits_for_the_first_to_end() -> void:
	_box(10, 0)
	ledger.tick(10.0, MAX_SERVING)
	_box(11, 0)
	_box(12, 0)
	assert_eq(ledger.strength(0, SIZE), PenaltyRules.MIN_SKATERS, "never below three")
	assert_true(ledger.is_boxed(12), "he sits while he waits")
	assert_almost_eq(ledger.remaining_for(12), MINOR, 0.0001)
	ledger.tick(5.0, MAX_SERVING)
	assert_almost_eq(ledger.remaining_for(12), MINOR, 0.0001, "his clock has not started")
	assert_eq(ledger.tick(MINOR - 15.0 + 0.1, MAX_SERVING), [10] as Array[int])
	assert_eq(ledger.strength(0, SIZE), PenaltyRules.MIN_SKATERS, "the queued minor took its place")
	ledger.tick(1.0, MAX_SERVING)
	assert_almost_eq(ledger.remaining_for(12), MINOR - 1.0, 0.0001)


# ── A goal ───────────────────────────────────────────────────────────────────

func test_a_power_play_goal_ends_the_minor_nearest_its_end() -> void:
	_box(10, 0)
	ledger.tick(10.0, MAX_SERVING)
	_box(11, 0)
	assert_eq(ledger.release_for_goal(1, SIZE, MAX_SERVING), 10)
	assert_true(ledger.is_boxed(11))
	assert_eq(ledger.strength(0, SIZE), SIZE - 1)


func test_a_short_handed_goal_releases_nobody() -> void:
	_box(10, 0)
	assert_eq(ledger.release_for_goal(0, SIZE, MAX_SERVING), -1)
	assert_true(ledger.is_boxed(10))


func test_a_goal_at_even_strength_releases_nobody() -> void:
	_box(10, 0)
	_box(20, 1)
	assert_eq(ledger.strength(0, SIZE), ledger.strength(1, SIZE), "four on four")
	assert_eq(ledger.release_for_goal(1, SIZE, MAX_SERVING), -1)
	assert_eq(ledger.release_for_goal(0, SIZE, MAX_SERVING), -1)


func test_a_power_play_goal_starts_the_queued_minor() -> void:
	_box(10, 0)
	_box(11, 0)
	_box(12, 0)
	assert_ne(ledger.release_for_goal(1, SIZE, MAX_SERVING), -1)
	assert_eq(ledger.strength(0, SIZE), PenaltyRules.MIN_SKATERS)
	ledger.tick(1.0, MAX_SERVING)
	assert_almost_eq(ledger.remaining_for(12), MINOR - 1.0, 0.0001)


# ── Mirrors and rejoins ──────────────────────────────────────────────────────

func test_the_wire_round_trips_the_ledger() -> void:
	_box(10, 0)
	ledger.tick(3.25, MAX_SERVING)
	ledger.call_foul(20, 1, PenaltyRules.Foul.INTERFERENCE)
	var mirror := PenaltyLedger.new()
	mirror.from_wire(ledger.to_wire())
	assert_true(mirror.is_boxed(10))
	assert_almost_eq(mirror.remaining_for(10), MINOR - 3.25, 0.001)
	assert_true(mirror.has_pending_against(1))
	assert_eq(mirror.foul_of(20), PenaltyRules.Foul.INTERFERENCE)
	assert_eq(mirror.to_wire(), ledger.to_wire())


func test_a_mirror_runs_the_clock_down_but_releases_nobody() -> void:
	_box(10, 0)
	ledger.tick_mirror(MINOR + 5.0)
	assert_eq(ledger.remaining_for(10), 0.0)
	assert_true(ledger.is_boxed(10), "the host says who comes out")


func test_a_rejoining_player_takes_his_penalty_with_him() -> void:
	_box(10, 0)
	ledger.rebind(10, 77)
	assert_false(ledger.is_boxed(10))
	assert_true(ledger.is_boxed(77))
