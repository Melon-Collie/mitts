extends GutTest

# PuckInteractionRules — swept sphere (capsule vs point) detection.
# Each test drives the geometry directly so intent is unambiguous.
# Y components are kept at zero unless a test specifically needs 3D coverage.


# ── check_pickup ─────────────────────────────────────────────────────────────

func test_pickup_detects_direct_hit() -> void:
	# Puck travels straight through the blade position.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0), 0.5))


func test_pickup_misses_when_blade_outside_radius() -> void:
	# Blade is 0.6 m from the puck path, radius is 0.5.
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.6), 0.5))


func test_pickup_hits_at_exact_radius_boundary() -> void:
	# Blade is exactly 0.5 m from the closest point on the path.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.5), 0.5))


func test_pickup_misses_when_blade_beyond_path_end() -> void:
	# Blade is ahead of where the puck travelled this tick.
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(3, 0, 0), 0.5))


func test_pickup_misses_when_blade_behind_path_start() -> void:
	# Blade is behind the puck's starting position.
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(2, 0, 0), Vector3(3, 0, 0),
		Vector3(0, 0, 0.4), 0.5))


func test_pickup_detects_when_prev_is_inside_radius() -> void:
	# Puck starts inside the pickup zone — still a hit.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0.1, 0, 0), Vector3(2, 0, 0),
		Vector3(0, 0, 0), 0.5))


# ── Zero-length segment (stationary puck) ────────────────────────────────────

func test_pickup_stationary_puck_inside_radius() -> void:
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(0.3, 0, 0), 0.5))


func test_pickup_stationary_puck_outside_radius() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(0.6, 0, 0), 0.5))


# ── Tunneling protection ──────────────────────────────────────────────────────

func test_pickup_catches_fast_puck_that_passes_through_zone() -> void:
	# Puck travels 10 m in one tick (extreme speed). A point test at curr
	# would miss; the swept test finds the blade mid-path.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(10, 0, 0),
		Vector3(5, 0, 0.3), 0.5))


func test_pickup_fast_puck_still_misses_when_offset_exceeds_radius() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(10, 0, 0),
		Vector3(5, 0, 0.6), 0.5))


# ── 3D coverage ───────────────────────────────────────────────────────────────

func test_pickup_works_correctly_with_y_offset() -> void:
	# Puck riding at ice height, blade slightly offset in Z — same XZ geometry.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0.05, 0), Vector3(1, 0.05, 0),
		Vector3(0.5, 0.05, 0.3), 0.5))


# ── check_poke ────────────────────────────────────────────────────────────────

func test_poke_detects_direct_hit() -> void:
	assert_true(PuckInteractionRules.check_poke(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0), 0.5))


func test_poke_misses_when_outside_radius() -> void:
	assert_false(PuckInteractionRules.check_poke(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.6), 0.5))


func test_poke_and_pickup_return_same_result_for_same_inputs() -> void:
	# Both functions use identical math — verify they agree on several cases.
	var cases: Array = [
		[Vector3(0,0,0), Vector3(1,0,0), Vector3(0.5,0,0.3), 0.5],
		[Vector3(0,0,0), Vector3(1,0,0), Vector3(0.5,0,0.6), 0.5],
		[Vector3(0,0,0), Vector3(0,0,0), Vector3(0.4,0,0), 0.5],
		[Vector3(0,0,0), Vector3(10,0,0), Vector3(5,0,0.3), 0.5],
	]
	for c: Array in cases:
		var pickup := PuckInteractionRules.check_pickup(c[0], c[1], c[2], c[3])
		var poke   := PuckInteractionRules.check_poke(c[0], c[1], c[2], c[3])
		assert_eq(pickup, poke, "check_pickup and check_poke disagree for %s" % str(c))
