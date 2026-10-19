extends GutTest

# BottomHandIK — angle-based bottom-hand release.
#
# Within release_angle_max        → hand exactly on grip target (on the stick).
# release_angle_max → +band       → smoothstep blend toward the free hand's rest.
# Beyond release_angle_max + band → hand at rest (one-handed look).

const HAND_Y: float = 0.0
const SHOULDER_Y: float = 0.35
const SHOULDER_OFFSET: float = 0.22
const RELEASE_DEG: float = 67.0
const BAND_DEG: float = 15.0
const RELEASE_RAD: float = RELEASE_DEG * PI / 180.0
const BAND_RAD: float = BAND_DEG * PI / 180.0

func _cfg(backhand_angle_deg: float) -> BottomHandIK.Config:
	var cfg := BottomHandIK.Config.new()
	cfg.hand_y = HAND_Y
	cfg.backhand_angle = backhand_angle_deg * PI / 180.0
	cfg.release_angle_max = RELEASE_RAD
	cfg.release_angle_band = BAND_RAD
	return cfg

# The free hand's rest: below the shoulder and ahead of it, out on its own side.
func _rest(shoulder: Vector3) -> Vector3:
	return shoulder + Vector3(0.1 * signf(shoulder.x), -0.35, -0.2)

func _lefty_shoulder() -> Vector3:
	return Vector3(-SHOULDER_OFFSET, SHOULDER_Y, 0.0)

func _righty_shoulder() -> Vector3:
	return Vector3(SHOULDER_OFFSET, SHOULDER_Y, 0.0)

# ── Within angle range: hand on the stick ────────────────────────────────────

func test_forehand_hand_on_target() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x - 0.2, shoulder.z - 0.1)
	var hand: Vector3 = BottomHandIK.solve(_rest(shoulder), target, _cfg(0.0))
	assert_almost_eq(hand.x, target.x, 0.001, "forehand: hand X on target")
	assert_almost_eq(hand.z, target.y, 0.001, "forehand: hand Z on target")
	assert_almost_eq(hand.y, HAND_Y, 0.001, "forehand: hand Y at hand_y")

func test_moderate_backhand_hand_on_target() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 0.1, shoulder.z - 0.2)
	var hand: Vector3 = BottomHandIK.solve(_rest(shoulder), target, _cfg(45.0))
	assert_almost_eq(hand.x, target.x, 0.001, "45 deg backhand: hand X on target")
	assert_almost_eq(hand.z, target.y, 0.001, "45 deg backhand: hand Z on target")

func test_at_release_angle_hand_on_target() -> void:
	# Exactly at the release angle — smoothstep(x, x+b, x) = 0, so hand still on target.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 0.3, shoulder.z - 0.1)
	var hand: Vector3 = BottomHandIK.solve(_rest(shoulder), target, _cfg(RELEASE_DEG))
	assert_almost_eq(hand.x, target.x, 0.001, "at release angle: hand X on target")
	assert_almost_eq(hand.z, target.y, 0.001, "at release angle: hand Z on target")

# ── Beyond release + band: hand at its rest ──────────────────────────────────

func test_extreme_backhand_hand_at_rest() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 0.5, shoulder.z - 0.1)
	var hand: Vector3 = BottomHandIK.solve(_rest(shoulder), target, _cfg(RELEASE_DEG + BAND_DEG))
	assert_almost_eq(hand.distance_to(_rest(shoulder)), 0.0, 0.001,
			"extreme: hand at the free hand's rest, height included")

func test_well_past_release_hand_at_rest() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 1.0, shoulder.z)
	var hand: Vector3 = BottomHandIK.solve(_rest(shoulder), target, _cfg(120.0))
	assert_almost_eq(hand.distance_to(_rest(shoulder)), 0.0, 0.001, "120 deg: hand at rest")

# ── Transition band: partial blend ────────────────────────────────────────────

func test_transition_band_partially_blended() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 0.3, shoulder.z - 0.1)
	var mid_angle_deg: float = RELEASE_DEG + BAND_DEG * 0.5
	var hand: Vector3 = BottomHandIK.solve(_rest(shoulder), target, _cfg(mid_angle_deg))
	var rest: Vector3 = _rest(shoulder)
	var target_at_y := Vector3(target.x, HAND_Y, target.y)
	var to_rest: float = (hand - rest).length()
	var to_target: float = (hand - target_at_y).length()
	assert_gt(to_rest, 0.001, "partial blend — hand not fully at rest")
	assert_gt(to_target, 0.001, "partial blend — hand not fully on target")

# ── Forehand angle is negative — should always stay on target ─────────────────

func test_negative_angle_forehand_always_on_target() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x - 0.3, shoulder.z - 0.2)
	# Large negative angle = deep forehand; release_angle_max is positive so t=0.
	var hand: Vector3 = BottomHandIK.solve(_rest(shoulder), target, _cfg(-90.0))
	assert_almost_eq(hand.x, target.x, 0.001, "deep forehand: hand X on target")
	assert_almost_eq(hand.z, target.y, 0.001, "deep forehand: hand Z on target")

# ── Handedness mirror ─────────────────────────────────────────────────────────

func test_righty_mirrors_lefty_in_x() -> void:
	var lefty_shoulder: Vector3 = _lefty_shoulder()
	var righty_shoulder: Vector3 = _righty_shoulder()
	var lefty_target := Vector2(lefty_shoulder.x - 0.3, lefty_shoulder.z - 0.2)
	var righty_target := Vector2(-lefty_target.x, lefty_target.y)
	var lefty_hand: Vector3 = BottomHandIK.solve(_rest(lefty_shoulder), lefty_target, _cfg(30.0))
	var righty_hand: Vector3 = BottomHandIK.solve(_rest(righty_shoulder), righty_target, _cfg(30.0))
	assert_almost_eq(lefty_hand.x, -righty_hand.x, 0.001, "hand X mirrors")
	assert_almost_eq(lefty_hand.y, righty_hand.y, 0.001, "hand Y matches")
	assert_almost_eq(lefty_hand.z, righty_hand.z, 0.001, "hand Z matches")


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
