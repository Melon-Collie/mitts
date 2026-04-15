extends GutTest

# BottomHandIK — reactive bottom-hand solver. Given a grip target somewhere
# along the stick shaft (computed by the caller from top_hand + blade), places
# the bottom hand at the anchor of the OPPOSITE shoulder from the top hand.
#
# Behaviours:
#   - Reachable target → hand lands exactly on target.
#   - Same-side target past reach ROM (toward the blade) → hand clamped short
#     along the aim line; never blends to rest.
#   - Cross-body target approaching / past angle ROM (toward top-hand side) →
#     hand smoothly releases to the bottom shoulder (one-handed backhand).

const HAND_Y: float = 0.0
const SHOULDER_OFFSET: float = 0.22

# Release band: 15° smoothstep before the cross-body angle max.
const RELEASE_BAND: float = deg_to_rad(15.0)

# Tight cross-body ROM, loose same-side ROM (matches the controller defaults).
const CROSS_ANGLE: float = deg_to_rad(60.0)
const SAME_ANGLE:  float = deg_to_rad(110.0)
const CROSS_REACH: float = 0.30
const SAME_REACH:  float = 0.60

func _cfg() -> Dictionary:
	return {
		"hand_y": HAND_Y,
		"rom_cross_body_angle_max": CROSS_ANGLE,
		"rom_same_side_angle_max": SAME_ANGLE,
		"rom_cross_body_reach_max": CROSS_REACH,
		"rom_same_side_reach_max": SAME_REACH,
		"release_angle_band": RELEASE_BAND,
	}

# Lefty: bottom shoulder on −X (blade side). side_sign = +1: positive angles
# measured via atan2(dx, −dz) * side_sign map to the cross-body (toward
# top-hand / +X) direction.
func _lefty_shoulder() -> Vector3:
	return Vector3(-SHOULDER_OFFSET, 0.0, 0.0)

func _righty_shoulder() -> Vector3:
	return Vector3(SHOULDER_OFFSET, 0.0, 0.0)

# ── Reachable targets land on target exactly ──────────────────────────────

func test_reachable_same_side_target_hand_on_target() -> void:
	# Target 0.3 m to the bottom-hand side (−X for lefty); same-side reach is
	# 0.60 so comfortably within ROM.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x - 0.3, shoulder.z)
	var hand: Vector3 = BottomHandIK.solve(shoulder, target, 1.0, _cfg())
	assert_almost_eq(hand.x, target.x, 0.001, "hand X on target (same-side)")
	assert_almost_eq(hand.z, target.y, 0.001, "hand Z on target (same-side)")

func test_reachable_cross_body_target_hand_on_target() -> void:
	# Small cross-body displacement (26.6° < 60° ROM, 0.22 m < 0.30 reach).
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 0.1, shoulder.z - 0.2)
	var hand: Vector3 = BottomHandIK.solve(shoulder, target, 1.0, _cfg())
	assert_almost_eq(hand.x, target.x, 0.001, "hand X on target (cross-body)")
	assert_almost_eq(hand.z, target.y, 0.001, "hand Z on target (cross-body)")

# ── Same-side past ROM clamps, never releases ─────────────────────────────

func test_same_side_past_rom_hand_clamped_not_released() -> void:
	# Target far to the blade side. Should clamp to same-side reach and stay
	# engaged — same-side never triggers the release-to-rest blend.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x - 5.0, shoulder.z - 0.1)
	var hand: Vector3 = BottomHandIK.solve(shoulder, target, 1.0, _cfg())

	var disp := Vector2(hand.x - shoulder.x, hand.z - shoulder.z)
	assert_almost_eq(
			disp.length(), SAME_REACH, 0.001,
			"same-side hand clamped to rom_same_side_reach_max")
	assert_gt(
			disp.length(), 0.1,
			"same-side hand has not collapsed to rest (release should NOT fire)")

# ── Cross-body past angle ROM releases fully to rest ──────────────────────

func test_cross_body_past_angle_rom_releases_to_rest() -> void:
	# Target well past the 60° cross-body angle ROM. Release smoothstep = 1,
	# hand pulls fully back to shoulder XZ (one-handed backhand pose).
	var shoulder: Vector3 = _lefty_shoulder()
	# Construct a target at ≈80° cross-body, any reasonable distance.
	var angle: float = deg_to_rad(80.0)
	var dist: float = 0.4
	var disp := Vector2(sin(angle) * dist, -cos(angle) * dist)
	var target: Vector2 = Vector2(shoulder.x, shoulder.z) + disp
	var hand: Vector3 = BottomHandIK.solve(shoulder, target, 1.0, _cfg())
	assert_almost_eq(hand.x, shoulder.x, 0.001, "released hand at shoulder X")
	assert_almost_eq(hand.z, shoulder.z, 0.001, "released hand at shoulder Z")

func test_cross_body_release_band_partially_blended() -> void:
	# Angle exactly mid-band (between 45° and 60°) should partially blend.
	# Hand should be between the ideal clamped position and the shoulder rest.
	var shoulder: Vector3 = _lefty_shoulder()
	var angle: float = deg_to_rad(55.0)  # inside ROM but inside release band
	var dist: float = 0.2                # inside cross-body reach ROM
	var disp := Vector2(sin(angle) * dist, -cos(angle) * dist)
	var target: Vector2 = Vector2(shoulder.x, shoulder.z) + disp
	var hand: Vector3 = BottomHandIK.solve(shoulder, target, 1.0, _cfg())

	var to_hand := Vector2(hand.x - shoulder.x, hand.z - shoulder.z)
	# Partially released → hand sits between target and shoulder.
	assert_gt(to_hand.length(), 0.0, "partial release — hand not at shoulder")
	assert_lt(to_hand.length(), dist, "partial release — hand moved toward shoulder")

# ── Asymmetric reach ──────────────────────────────────────────────────────

func test_same_side_reach_exceeds_cross_body_reach() -> void:
	# Two targets at ±30° from forward with the same over-reach distance.
	# Cross-body should clamp to 0.30, same-side to 0.60.
	var shoulder: Vector3 = _lefty_shoulder()
	var dist: float = 5.0

	var cross_angle: float = deg_to_rad(30.0)
	var cross_disp := Vector2(sin(cross_angle) * dist, -cos(cross_angle) * dist)
	var cross_target: Vector2 = Vector2(shoulder.x, shoulder.z) + cross_disp
	var cross_hand: Vector3 = BottomHandIK.solve(shoulder, cross_target, 1.0, _cfg())
	var cross_reach: float = Vector2(
			cross_hand.x - shoulder.x, cross_hand.z - shoulder.z).length()

	var same_angle: float = deg_to_rad(-30.0)
	var same_disp := Vector2(sin(same_angle) * dist, -cos(same_angle) * dist)
	var same_target: Vector2 = Vector2(shoulder.x, shoulder.z) + same_disp
	var same_hand: Vector3 = BottomHandIK.solve(shoulder, same_target, 1.0, _cfg())
	var same_reach: float = Vector2(
			same_hand.x - shoulder.x, same_hand.z - shoulder.z).length()

	assert_almost_eq(cross_reach, CROSS_REACH, 0.001, "cross-body clamped to tight reach")
	assert_almost_eq(same_reach, SAME_REACH, 0.001, "same-side clamped to loose reach")
	assert_gt(same_reach, cross_reach + 0.1, "same-side reach > cross-body reach")

# ── Hand Y locked ─────────────────────────────────────────────────────────

func test_hand_y_locked() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	for target: Vector2 in [
			Vector2(shoulder.x, shoulder.z),                   # at shoulder
			Vector2(shoulder.x - 0.3, shoulder.z - 0.1),       # same-side reachable
			Vector2(shoulder.x + 0.1, shoulder.z - 0.2),       # cross-body reachable
			Vector2(shoulder.x + 2.0, shoulder.z - 0.3),       # cross-body past ROM
			Vector2(shoulder.x - 5.0, shoulder.z - 0.1),       # same-side past ROM
		]:
		var hand: Vector3 = BottomHandIK.solve(shoulder, target, 1.0, _cfg())
		assert_almost_eq(
				hand.y, HAND_Y, 0.0001,
				"hand Y locked at cfg.hand_y for target %s" % target)

# ── Handedness mirror ─────────────────────────────────────────────────────

func test_righty_mirrors_lefty_in_x() -> void:
	# Righty: bottom shoulder on +X, side_sign = −1. Mirror target in X;
	# expect a mirrored hand position.
	var lefty_shoulder: Vector3 = _lefty_shoulder()
	var righty_shoulder: Vector3 = _righty_shoulder()
	var lefty_target := Vector2(lefty_shoulder.x - 0.3, lefty_shoulder.z - 0.2)
	var righty_target := Vector2(-lefty_target.x, lefty_target.y)

	var lefty_hand: Vector3 = BottomHandIK.solve(lefty_shoulder, lefty_target, 1.0, _cfg())
	var righty_hand: Vector3 = BottomHandIK.solve(righty_shoulder, righty_target, -1.0, _cfg())

	assert_almost_eq(lefty_hand.x, -righty_hand.x, 0.001, "hand X mirrors")
	assert_almost_eq(lefty_hand.y, righty_hand.y, 0.001, "hand Y matches")
	assert_almost_eq(lefty_hand.z, righty_hand.z, 0.001, "hand Z matches")

# ── Degenerate: target at shoulder ────────────────────────────────────────

func test_target_at_shoulder_returns_shoulder() -> void:
	# No meaningful aim direction when target coincides with shoulder; hand
	# rests at shoulder XZ with hand_y.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x, shoulder.z)
	var hand: Vector3 = BottomHandIK.solve(shoulder, target, 1.0, _cfg())
	assert_almost_eq(hand.x, shoulder.x, 0.0001, "degenerate hand X at shoulder")
	assert_almost_eq(hand.z, shoulder.z, 0.0001, "degenerate hand Z at shoulder")
	assert_almost_eq(hand.y, HAND_Y, 0.0001, "degenerate hand Y at cfg.hand_y")
