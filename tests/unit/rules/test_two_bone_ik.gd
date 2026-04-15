extends GutTest

# TwoBoneIK — analytical 2-bone IK for arm rendering. Given shoulder, hand,
# bone lengths, and a pole hint, places the elbow such that both bones are
# the right length and the elbow bends in the pole direction.

const UPPER: float = 0.33
const FOREARM: float = 0.37
const TOTAL: float = UPPER + FOREARM  # 0.70 — matches rom_backhand_reach_max

# ── Straight arm ──────────────────────────────────────────────────────────

func test_fully_extended_arm_places_elbow_on_axis() -> void:
	# Hand at max reach: arm is a straight line, elbow sits at upper_len
	# along the shoulder→hand direction.
	var shoulder := Vector3.ZERO
	var hand := Vector3(TOTAL, 0.0, 0.0)
	var elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3.DOWN)
	assert_almost_eq(elbow.x, UPPER, 0.001, "elbow at upper_len along axis")
	assert_almost_eq(elbow.y, 0.0, 0.001, "no perpendicular offset when fully extended")
	assert_almost_eq(elbow.z, 0.0, 0.001)

# ── Bent arm ──────────────────────────────────────────────────────────────

func test_bent_arm_elbow_offset_in_pole_direction() -> void:
	# Hand closer than max reach along +X. Pole hint is -Y (down), so the
	# elbow should sit below the SH line.
	var shoulder := Vector3.ZERO
	var d: float = 0.5  # between |U−F| = 0.04 and U+F = 0.70
	var hand := Vector3(d, 0.0, 0.0)
	var elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3.DOWN)

	# Analytical expectation.
	var foot_t: float = (UPPER * UPPER - FOREARM * FOREARM + d * d) / (2.0 * d)
	var h: float = sqrt(UPPER * UPPER - foot_t * foot_t)

	assert_almost_eq(elbow.x, foot_t, 0.001, "elbow X matches foot_t along axis")
	assert_almost_eq(elbow.y, -h, 0.001, "elbow Y is -h (pole is -Y)")
	assert_almost_eq(elbow.z, 0.0, 0.001, "no Z offset")

	# Bone-length invariants.
	var shoulder_to_elbow: float = shoulder.distance_to(elbow)
	var elbow_to_hand: float = elbow.distance_to(hand)
	assert_almost_eq(shoulder_to_elbow, UPPER, 0.001, "|shoulder − elbow| = upper_len")
	assert_almost_eq(elbow_to_hand, FOREARM, 0.001, "|elbow − hand| = forearm_len")

# ── Degenerate: hand at shoulder ─────────────────────────────────────────

func test_hand_coincides_with_shoulder_returns_shoulder() -> void:
	# Graceful fallback; no direction is defined.
	var shoulder := Vector3(1.0, 2.0, 3.0)
	var hand: Vector3 = shoulder
	var elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3.DOWN)
	assert_eq(elbow, shoulder, "degenerate case returns shoulder position")

# ── Pole direction controls elbow side ───────────────────────────────────

func test_flipping_pole_flips_elbow() -> void:
	# Same shoulder/hand with pole along +Y vs -Y should produce elbows
	# mirrored across the SH axis.
	var shoulder := Vector3.ZERO
	var hand := Vector3(0.5, 0.0, 0.0)
	var down_elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3.DOWN)
	var up_elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3.UP)
	assert_almost_eq(down_elbow.x, up_elbow.x, 0.001, "X matches (both on the SH axis)")
	assert_almost_eq(down_elbow.y, -up_elbow.y, 0.001, "Y flips with pole")
	assert_almost_eq(down_elbow.z, up_elbow.z, 0.001)

func test_pole_not_perpendicular_to_axis_is_projected() -> void:
	# Pole = (1, -1, 0) has an along-axis component. After projection only
	# the perpendicular part matters → equivalent to passing (0, -1, 0).
	var shoulder := Vector3.ZERO
	var hand := Vector3(0.5, 0.0, 0.0)
	var skewed_elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3(1.0, -1.0, 0.0))
	var clean_elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3.DOWN)
	assert_almost_eq(skewed_elbow.x, clean_elbow.x, 0.001)
	assert_almost_eq(skewed_elbow.y, clean_elbow.y, 0.001)
	assert_almost_eq(skewed_elbow.z, clean_elbow.z, 0.001)

# ── Pole parallel to axis falls back gracefully ──────────────────────────

func test_pole_parallel_to_axis_uses_fallback() -> void:
	# Shoulder→hand along +X, pole also along +X. After projection pole is
	# zero; the solver should substitute a stable fallback so elbow is
	# still defined (not NaN, on a unit sphere slice perpendicular to axis).
	var shoulder := Vector3.ZERO
	var hand := Vector3(0.5, 0.0, 0.0)
	var elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3(1.0, 0.0, 0.0))
	# Expect finite result with expected bone lengths.
	var shoulder_to_elbow: float = shoulder.distance_to(elbow)
	var elbow_to_hand: float = elbow.distance_to(hand)
	assert_almost_eq(shoulder_to_elbow, UPPER, 0.001, "bone length preserved via fallback")
	assert_almost_eq(elbow_to_hand, FOREARM, 0.001)

# ── Unreachable hand clamps gracefully ───────────────────────────────────

func test_hand_beyond_max_reach_does_not_crash() -> void:
	# Hand placed at 1.5 × total reach. Solver should not return NaN; it
	# should produce an elbow on the SH line (arm stretched).
	var shoulder := Vector3.ZERO
	var hand := Vector3(TOTAL * 1.5, 0.0, 0.0)
	var elbow: Vector3 = TwoBoneIK.solve_elbow(
			shoulder, hand, UPPER, FOREARM, Vector3.DOWN)
	# Elbow on the axis (h collapsed to 0 because d_clamped = TOTAL, foot_t = UPPER).
	assert_almost_eq(elbow.y, 0.0, 0.001, "elbow collapses onto SH line at max reach")
	assert_almost_eq(elbow.x, UPPER, 0.001, "elbow at upper_len along axis when stretched")
