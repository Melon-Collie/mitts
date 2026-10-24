extends GutTest

# BottomHandIK — the angle-based release, and where on the shaft the hand holds.
#
# Within release_angle_max        → on the stick (weight 0).
# release_angle_max → +band       → smoothstep toward the free hand's rest.
# Beyond release_angle_max + band → at rest (weight 1, one-handed look).

const RELEASE_DEG: float = 67.0
const BAND_DEG: float = 15.0


func _weight(backhand_angle_deg: float) -> float:
	var cfg := BottomHandIK.Config.new()
	cfg.backhand_angle = deg_to_rad(backhand_angle_deg)
	cfg.release_angle_max = deg_to_rad(RELEASE_DEG)
	cfg.release_angle_band = deg_to_rad(BAND_DEG)
	return BottomHandIK.release_weight(cfg)


# ── The release ───────────────────────────────────────────────────────────────

func test_inside_the_release_angle_the_hand_stays_on_the_stick() -> void:
	for deg: float in [-90.0, 0.0, 45.0, RELEASE_DEG]:
		assert_almost_eq(_weight(deg), 0.0, 1e-6, "%.0f deg: on the stick" % deg)


func test_past_the_band_the_hand_is_at_rest() -> void:
	for deg: float in [RELEASE_DEG + BAND_DEG, 120.0]:
		assert_almost_eq(_weight(deg), 1.0, 1e-6, "%.0f deg: at rest" % deg)


func test_inside_the_band_the_hand_is_part_way_off() -> void:
	var mid: float = _weight(RELEASE_DEG + BAND_DEG * 0.5)
	assert_gt(mid, 0.001, "mid band: off the stick some way")
	assert_lt(mid, 0.999, "mid band: not yet at rest")


func test_the_release_never_turns_back() -> void:
	var last: float = 0.0
	for i: int in 121:
		var w: float = _weight(float(i))
		assert_true(w >= last - 1e-6, "%d deg: monotone" % i)
		last = w


# ── Where on the shaft it can hold ────────────────────────────────────────────

# A shaft running straight down from a top hand level with the shoulder and 0.6 m
# out: the arm reaches 0.6 m of it and no further.
const _SHAFT_TOP := Vector3(0.0, 0.0, -0.6)
const _SHAFT_BLADE := Vector3(0.0, -1.2, -0.6)


func test_the_grip_slides_up_to_where_the_arm_reaches() -> void:
	var held: Vector2 = BottomHandIK.reachable_grip(Vector3.ZERO, _SHAFT_TOP, _SHAFT_BLADE,
			0.5, 0.75)
	assert_almost_eq(held.x, 0.375, 0.001, "0.45 m down the shaft is 0.75 m from the shoulder")
	assert_eq(held.y, 0.0, "and it still holds")


func test_the_grip_never_comes_up_into_the_top_glove() -> void:
	var held: Vector2 = BottomHandIK.reachable_grip(Vector3.ZERO, _SHAFT_TOP, _SHAFT_BLADE,
			0.0, 0.75, 0.14)
	assert_almost_eq(held.x * 1.2, 0.14, 0.001, "a grip wanted at the top hand stops a glove below it")
	assert_eq(held.y, 0.0, "which the arm reaches")


func test_an_arm_that_cannot_reach_past_the_top_glove_lets_go() -> void:
	var held: Vector2 = BottomHandIK.reachable_grip(Vector3.ZERO, _SHAFT_TOP, _SHAFT_BLADE,
			0.25, 0.61, 0.14)
	assert_almost_eq(held.x * 1.2, 0.14, 0.001, "the nearest it may hold is a glove down")
	assert_almost_eq(held.y, Vector2(0.6, 0.14).length() - 0.61, 0.001,
			"and it is that far past the arm's reach")
	var bare: Vector2 = BottomHandIK.reachable_grip(Vector3.ZERO, _SHAFT_TOP, _SHAFT_BLADE,
			0.25, 0.61)
	assert_eq(bare.y, 0.0, "without the glove's room it would hold on top of the other hand")


# ── The drawn grip eases into the limit ───────────────────────────────────────

const _BAND: float = 0.08


func _soft(grip: float, reach: float) -> float:
	return BottomHandIK.soft_reachable_grip(Vector3.ZERO, _SHAFT_TOP, _SHAFT_BLADE,
			grip, reach, 0.14, _BAND).x


func test_well_inside_reach_the_drawn_grip_is_the_preferred_one() -> void:
	assert_almost_eq(_soft(0.25, 1.2), 0.25, 1e-5)


func test_the_drawn_grip_never_reaches_past_the_arm() -> void:
	for k: int in 40:
		var reach: float = 0.62 + 0.01 * k
		var hard: float = BottomHandIK.reachable_grip(Vector3.ZERO, _SHAFT_TOP, _SHAFT_BLADE,
				0.5, reach, 0.14).x
		assert_lte(_soft(0.5, reach), hard + 1e-6, "reach %.2f" % reach)


# As the arm's reach closes on the preferred grip the hard limit turns a
# corner; the drawn grip's slope changes no faster through it than either side.
func test_the_drawn_grip_turns_no_corner_where_the_limit_begins() -> void:
	var step: float = 0.002
	var worst_turn: float = 0.0
	var prev_slope: float = NAN
	var reach: float = 0.75
	while reach < 0.95:
		var slope: float = (_soft(0.5, reach + step) - _soft(0.5, reach)) / step
		if not is_nan(prev_slope):
			worst_turn = maxf(worst_turn, absf(slope - prev_slope))
		prev_slope = slope
		reach += step
	# The hard grip reaches 0.5 at a reach of √0.72 ≈ 0.849 and goes flat: its
	# turn there is the whole of its slope just below.
	var hard_turn: float = absf((BottomHandIK.reachable_grip(Vector3.ZERO, _SHAFT_TOP,
			_SHAFT_BLADE, 0.5, 0.846, 0.14).x - BottomHandIK.reachable_grip(Vector3.ZERO,
			_SHAFT_TOP, _SHAFT_BLADE, 0.5, 0.844, 0.14).x) / step)
	assert_gt(hard_turn, 1.0, "the hard grip does turn a corner there")
	assert_lt(worst_turn, 0.25 * hard_turn, "the slope eases where the hard grip snaps")
