extends GutTest

# TopHandIK — 1-bone inverse kinematics for the stick's top hand. Given a
# desired blade target in upper-body-local XZ space, the solver returns
# (hand, blade) respecting fixed stick length and an asymmetric ROM.

# Baselines from the design plan.
const STICK_LENGTH: float = 1.50
const BLADE_Y: float = -0.95
const HAND_REST_Y: float = 0.0
const SHOULDER_OFFSET: float = 0.22
# Derived horizontal stick projection: sqrt(1.50² − 0.95²) ≈ 1.1608
const STICK_HORIZ: float = 1.16081

# ROM
const FORE_ANGLE: float = PI / 4.0        # 45°
const BACK_ANGLE: float = 2.0 * PI / 3.0  # 120°
const FORE_REACH: float = 0.20
const BACK_REACH: float = 0.70

func _cfg() -> Dictionary:
	return {
		"stick_length": STICK_LENGTH,
		"blade_y": BLADE_Y,
		"hand_rest_y": HAND_REST_Y,
		"rom_forehand_angle_max": FORE_ANGLE,
		"rom_backhand_angle_max": BACK_ANGLE,
		"rom_forehand_reach_max": FORE_REACH,
		"rom_backhand_reach_max": BACK_REACH,
	}

# A left-handed skater has blade on −X and shoulder (top hand) on +X.
func _lefty_shoulder() -> Vector3:
	return Vector3(SHOULDER_OFFSET, 0.0, 0.0)

# A right-handed skater has blade on +X and shoulder (top hand) on −X.
func _righty_shoulder() -> Vector3:
	return Vector3(-SHOULDER_OFFSET, 0.0, 0.0)

# ── Invariants ────────────────────────────────────────────────────────────

func test_blade_is_always_stick_horiz_from_hand() -> void:
	# Sweep targets all around the shoulder at various distances; the
	# horizontal distance between hand and blade must always equal stick_horiz.
	var shoulder: Vector3 = _lefty_shoulder()
	for deg: int in range(-180, 180, 15):
		for dist: float in [0.2, 0.8, 1.16, 1.5, 2.5, 5.0]:
			var angle: float = deg_to_rad(deg)
			var target := Vector2(sin(angle) * dist, -cos(angle) * dist)
			var result: Dictionary = TopHandIK.solve(shoulder, target, -1.0, _cfg())
			var hand_xz := Vector2(result.hand.x, result.hand.z)
			var blade_xz := Vector2(result.blade.x, result.blade.z)
			assert_almost_eq(
				hand_xz.distance_to(blade_xz), STICK_HORIZ, 0.001,
				"stick length violated at deg=%d dist=%.2f" % [deg, dist])

func test_hand_and_blade_y_locked() -> void:
	var shoulder: Vector3 = _lefty_shoulder()
	var result: Dictionary = TopHandIK.solve(shoulder, Vector2(-1.5, -1.5), -1.0, _cfg())
	assert_almost_eq(result.hand.y, HAND_REST_Y, 0.0001, "hand Y locked at hand_rest_y")
	assert_almost_eq(result.blade.y, BLADE_Y, 0.0001, "blade Y locked at blade_y")

# ── Target within reach ───────────────────────────────────────────────────

func test_target_inside_stick_range_hand_stays_at_shoulder() -> void:
	# Target close to the shoulder (well inside stick_horiz) → hand shouldn't
	# need to extend; blade sits at stick_horiz along the aim line.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 0.3, shoulder.z - 0.5)  # ~0.58 m from shoulder
	var result: Dictionary = TopHandIK.solve(shoulder, target, -1.0, _cfg())
	assert_almost_eq(result.hand.x, shoulder.x, 0.001, "hand stays at shoulder X")
	assert_almost_eq(result.hand.z, shoulder.z, 0.001, "hand stays at shoulder Z")

func test_target_on_stick_sphere_hits_target_exactly() -> void:
	# Target exactly stick_horiz from shoulder, dead ahead of shoulder.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x, shoulder.z - STICK_HORIZ)
	var result: Dictionary = TopHandIK.solve(shoulder, target, -1.0, _cfg())
	assert_almost_eq(result.blade.x, target.x, 0.001, "blade X == target X")
	assert_almost_eq(result.blade.z, target.y, 0.001, "blade Z == target Z")

func test_target_slightly_past_stick_range_hand_extends_blade_reaches() -> void:
	# Target just beyond stick_horiz but well within backhand ROM on the
	# backhand side. The hand should extend just enough; blade should land
	# exactly on target (reachable case).
	var shoulder: Vector3 = _lefty_shoulder()
	# Backhand side for a lefty is +X. Put target at backhand, distance > stick_horiz.
	var target := Vector2(shoulder.x + STICK_HORIZ + 0.15, shoulder.z - 0.2)
	var result: Dictionary = TopHandIK.solve(shoulder, target, -1.0, _cfg())
	assert_almost_eq(result.blade.x, target.x, 0.001, "reachable: blade lands on target X")
	assert_almost_eq(result.blade.z, target.y, 0.001, "reachable: blade lands on target Z")

# ── Forehand ROM clamp ────────────────────────────────────────────────────

func test_forehand_target_past_rom_clamps_hand_short() -> void:
	# Lefty forehand side is −X. Put target far on the forehand side,
	# outside reach. Hand should clamp to forehand_reach_max; blade should
	# fall short of target along the aim line.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x - 4.0, shoulder.z - 0.1)
	var result: Dictionary = TopHandIK.solve(shoulder, target, -1.0, _cfg())

	var hand_disp := Vector2(
			result.hand.x - shoulder.x, result.hand.z - shoulder.z).length()
	assert_almost_eq(
			hand_disp, FORE_REACH, 0.001,
			"hand clamped to rom_forehand_reach_max on forehand side")

	# Blade must be short of the target (|blade.xz - target| > 0).
	var blade_xz := Vector2(result.blade.x, result.blade.z)
	assert_gt(
			blade_xz.distance_to(target), 0.1,
			"blade falls short of unreachable forehand target")

# ── Backhand ROM allows more reach ────────────────────────────────────────

func test_backhand_target_reaches_farther_than_forehand() -> void:
	# Symmetric test: target at distance D on forehand side vs backhand side.
	# On backhand side the hand can extend farther → blade ends up closer to
	# target. For identical |target − shoulder|, backhand blade is farther
	# along aim than forehand blade.
	var shoulder: Vector3 = _lefty_shoulder()
	var d: float = STICK_HORIZ + 0.50  # past immediate stick reach

	# Forehand target (lefty: −X side).
	var fore_target := Vector2(shoulder.x - d, shoulder.z)
	var fore_result: Dictionary = TopHandIK.solve(shoulder, fore_target, -1.0, _cfg())
	var fore_blade := Vector2(fore_result.blade.x, fore_result.blade.z)
	var fore_reach_achieved: float = shoulder.distance_to(
			Vector3(fore_blade.x, shoulder.y, fore_blade.y))

	# Backhand target (lefty: +X side).
	var back_target := Vector2(shoulder.x + d, shoulder.z)
	var back_result: Dictionary = TopHandIK.solve(shoulder, back_target, -1.0, _cfg())
	var back_blade := Vector2(back_result.blade.x, back_result.blade.z)
	var back_reach_achieved: float = shoulder.distance_to(
			Vector3(back_blade.x, shoulder.y, back_blade.y))

	assert_gt(
			back_reach_achieved, fore_reach_achieved + 0.1,
			"backhand blade reaches meaningfully farther than forehand at same target distance")

func test_backhand_hand_can_extend_to_backhand_reach_max() -> void:
	# Very far on backhand side: hand should clamp to rom_backhand_reach_max,
	# which is larger than rom_forehand_reach_max.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x + 5.0, shoulder.z - 0.1)
	var result: Dictionary = TopHandIK.solve(shoulder, target, -1.0, _cfg())
	var hand_disp := Vector2(
			result.hand.x - shoulder.x, result.hand.z - shoulder.z).length()
	assert_almost_eq(
			hand_disp, BACK_REACH, 0.001,
			"hand clamped to rom_backhand_reach_max on backhand side")

# ── Handedness mirror ─────────────────────────────────────────────────────

func test_righty_mirrors_lefty_in_x() -> void:
	# Mirror invariant: solving for a righty with a target X-mirrored from a
	# lefty's target should yield an X-mirrored (hand, blade) pair.
	var lefty_shoulder: Vector3 = _lefty_shoulder()
	var righty_shoulder: Vector3 = _righty_shoulder()
	var lefty_target := Vector2(-1.5, -1.2)
	var righty_target := Vector2(1.5, -1.2)

	var lefty: Dictionary = TopHandIK.solve(lefty_shoulder, lefty_target, -1.0, _cfg())
	var righty: Dictionary = TopHandIK.solve(righty_shoulder, righty_target, 1.0, _cfg())

	assert_almost_eq(lefty.hand.x, -righty.hand.x, 0.001, "hand X mirrors")
	assert_almost_eq(lefty.hand.z, righty.hand.z, 0.001, "hand Z matches")
	assert_almost_eq(lefty.blade.x, -righty.blade.x, 0.001, "blade X mirrors")
	assert_almost_eq(lefty.blade.z, righty.blade.z, 0.001, "blade Z matches")

# ── Degenerate: target at shoulder ────────────────────────────────────────

func test_target_at_shoulder_places_blade_straight_forward() -> void:
	# Pathological: target coincides with shoulder. Hand should stay at
	# shoulder; blade should point straight forward (−Z) at stick_horiz.
	var shoulder: Vector3 = _lefty_shoulder()
	var target := Vector2(shoulder.x, shoulder.z)
	var result: Dictionary = TopHandIK.solve(shoulder, target, -1.0, _cfg())
	assert_almost_eq(result.hand.x, shoulder.x, 0.001)
	assert_almost_eq(result.hand.z, shoulder.z, 0.001)
	assert_almost_eq(result.blade.x, shoulder.x, 0.001, "blade X stays on shoulder")
	assert_almost_eq(result.blade.z, shoulder.z - STICK_HORIZ, 0.001, "blade goes straight forward")
