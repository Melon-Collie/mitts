extends GutTest

# SkaterAimingBehavior — owns wrister charge state and slapper charge timers.
# Tests operate directly on the RefCounted; no Skater node needed.

const VARIANCE_DEG: float = 35.0
const MAX_DISTANCE: float = 1.5

var ab: SkaterAimingBehavior

func before_each() -> void:
	ab = SkaterAimingBehavior.new()

func test_initial_state() -> void:
	assert_almost_eq(ab.charge_distance, 0.0, 0.001)
	assert_eq(ab.prev_mouse_screen_pos, Vector2.ZERO)
	assert_eq(ab.prev_blade_dir, Vector3.ZERO)
	assert_almost_eq(ab.slapper_charge_timer, 0.0, 0.001)
	assert_almost_eq(ab.one_timer_window_timer, 0.0, 0.001)

func test_tick_accumulates_charge() -> void:
	# 50 px drag in +X → 50 * 0.01 = 0.5 in scaled space
	ab.tick_wrister_charge(Vector2(50.0, 0.0), VARIANCE_DEG, MAX_DISTANCE)
	assert_almost_eq(ab.charge_distance, 0.5, 0.01)

func test_charge_capped_at_max() -> void:
	# 200 px drag → 2.0 scaled, capped to 1.5
	ab.tick_wrister_charge(Vector2(200.0, 0.0), VARIANCE_DEG, MAX_DISTANCE)
	assert_almost_eq(ab.charge_distance, MAX_DISTANCE, 0.001, "charge capped at max_wrister_charge_distance")

func test_tick_updates_prev_mouse_pos() -> void:
	ab.tick_wrister_charge(Vector2(30.0, 10.0), VARIANCE_DEG, MAX_DISTANCE)
	assert_eq(ab.prev_mouse_screen_pos, Vector2(30.0, 10.0))

func test_direction_reversal_resets_charge() -> void:
	# Establish charge in +X direction
	ab.tick_wrister_charge(Vector2(50.0, 0.0), VARIANCE_DEG, MAX_DISTANCE)
	var charge_after_first: float = ab.charge_distance
	assert_gt(charge_after_first, 0.0)
	# Short -X reversal (10 px = 0.1 units). ChargeTracking resets then adds the
	# delta distance, so the reversal distance must be < accumulated charge.
	ab.tick_wrister_charge(Vector2(40.0, 0.0), VARIANCE_DEG, MAX_DISTANCE)
	# Charge should be less than the accumulated amount (reset then re-accumulate from new pos)
	assert_lt(ab.charge_distance, charge_after_first, "direction reversal resets charge accumulator")

func test_reset_wrister_zeroes_charge_and_seeds_pos() -> void:
	ab.charge_distance = 1.2
	ab.prev_blade_dir = Vector3(1, 0, 0)
	ab.reset_wrister(Vector2(100.0, 50.0))
	assert_almost_eq(ab.charge_distance, 0.0, 0.001)
	assert_eq(ab.prev_blade_dir, Vector3.ZERO)
	assert_eq(ab.prev_mouse_screen_pos, Vector2(100.0, 50.0))

func test_tick_slapper_increments_timer() -> void:
	ab.tick_slapper(0.016)
	assert_almost_eq(ab.slapper_charge_timer, 0.016, 0.001)
	ab.tick_slapper(0.016)
	assert_almost_eq(ab.slapper_charge_timer, 0.032, 0.001)

func test_reset_slapper_zeroes_both_timers() -> void:
	ab.slapper_charge_timer = 0.5
	ab.one_timer_window_timer = 0.1
	ab.reset_slapper()
	assert_almost_eq(ab.slapper_charge_timer, 0.0, 0.001)
	assert_almost_eq(ab.one_timer_window_timer, 0.0, 0.001)

func test_tick_one_timer_window_decrements_when_positive() -> void:
	ab.one_timer_window_timer = 0.1
	ab.tick_one_timer_window(0.016)
	assert_almost_eq(ab.one_timer_window_timer, 0.084, 0.001)

func test_tick_one_timer_window_goes_negative_on_expiry() -> void:
	# Timer goes negative when delta overshoots — callers check <= 0 to detect expiry.
	ab.one_timer_window_timer = 0.01
	ab.tick_one_timer_window(0.016)
	assert_lt(ab.one_timer_window_timer, 0.0, "timer goes negative; caller detects expiry via <= 0")

func test_tick_one_timer_window_noop_when_zero() -> void:
	ab.one_timer_window_timer = 0.0
	ab.tick_one_timer_window(0.016)
	assert_almost_eq(ab.one_timer_window_timer, 0.0, 0.001, "noop when timer already zero")
