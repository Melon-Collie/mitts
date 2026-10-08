extends GutTest

# CarveRules — the path-curvature trigger for the carve/crossover gait.
# Frame: Vector2(x, z); travelling "up-ice" is (0, −1). Sign convention
# pinned here: turning toward +X yields a POSITIVE turn rate.

const DT: float = 1.0 / 120.0
const MIN_SPEED: float = 2.5


func _dir(angle_from_forward: float, speed: float = 6.0) -> Vector2:
	# Forward = (0, −1); positive angle rotates toward +X.
	return Vector2(sin(angle_from_forward), -cos(angle_from_forward)) * speed


# ── turn_rate ─────────────────────────────────────────────────────────────────

func test_right_turn_is_positive() -> void:
	var rate: float = CarveRules.turn_rate(_dir(0.0), _dir(0.02), DT, MIN_SPEED)
	assert_almost_eq(rate, 0.02 / DT, 0.01, "0.02 rad over one tick toward +X")


func test_left_turn_is_negative() -> void:
	assert_lt(CarveRules.turn_rate(_dir(0.0), _dir(-0.02), DT, MIN_SPEED), 0.0)


func test_straight_travel_is_zero() -> void:
	assert_eq(CarveRules.turn_rate(_dir(0.0), _dir(0.0), DT, MIN_SPEED), 0.0)


func test_slow_samples_read_zero() -> void:
	# Velocity direction is noise at a near-standstill — either slow sample
	# kills the signal.
	assert_eq(CarveRules.turn_rate(_dir(0.0, 1.0), _dir(0.3, 6.0), DT, MIN_SPEED), 0.0)
	assert_eq(CarveRules.turn_rate(_dir(0.0, 6.0), _dir(0.3, 1.0), DT, MIN_SPEED), 0.0)


func test_zero_delta_guard() -> void:
	assert_eq(CarveRules.turn_rate(_dir(0.0), _dir(0.3), 0.0, MIN_SPEED), 0.0)
