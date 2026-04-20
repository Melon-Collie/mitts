extends GutTest

# PuckInteractionRules — segment-segment swept detection.
# Both puck and blade paths are swept across the tick, so fast blade swings
# against a stationary puck are caught. Y components kept at zero unless a
# test needs 3D coverage. Static-blade tests pass the same vector for
# blade_prev and blade_curr to match the old capsule-vs-point behaviour.


# ── check_pickup — static blade (degenerate blade segment) ───────────────────

func test_pickup_detects_direct_hit() -> void:
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0), Vector3(0.5, 0, 0), 0.5))


func test_pickup_misses_when_blade_outside_radius() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.6), Vector3(0.5, 0, 0.6), 0.5))


func test_pickup_hits_at_exact_radius_boundary() -> void:
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.5), Vector3(0.5, 0, 0.5), 0.5))


func test_pickup_misses_when_blade_beyond_path_end() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(3, 0, 0), Vector3(3, 0, 0), 0.5))


func test_pickup_misses_when_blade_behind_path_start() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(2, 0, 0), Vector3(3, 0, 0),
		Vector3(0, 0, 0.4), Vector3(0, 0, 0.4), 0.5))


func test_pickup_detects_when_prev_is_inside_radius() -> void:
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0.1, 0, 0), Vector3(2, 0, 0),
		Vector3(0, 0, 0), Vector3(0, 0, 0), 0.5))


# ── Zero-length puck segment (stationary puck), static blade ─────────────────

func test_pickup_stationary_puck_inside_radius() -> void:
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(0.3, 0, 0), Vector3(0.3, 0, 0), 0.5))


func test_pickup_stationary_puck_outside_radius() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(0.6, 0, 0), Vector3(0.6, 0, 0), 0.5))


# ── Tunneling protection — fast puck, static blade ───────────────────────────

func test_pickup_catches_fast_puck_that_passes_through_zone() -> void:
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(10, 0, 0),
		Vector3(5, 0, 0.3), Vector3(5, 0, 0.3), 0.5))


func test_pickup_fast_puck_still_misses_when_offset_exceeds_radius() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(10, 0, 0),
		Vector3(5, 0, 0.6), Vector3(5, 0, 0.6), 0.5))


# ── Stationary puck + fast blade swing (was missed by old point test) ─────────

func test_pickup_stationary_puck_fast_blade_sweep_through_zone() -> void:
	# Puck at origin; blade sweeps from X=−2 to X=+2 in one tick.
	# Old test: point at X=+2, 2 m away from puck → miss. New: segment hits.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(-2, 0, 0), Vector3(2, 0, 0), 0.5))


func test_pickup_stationary_puck_fast_blade_sweep_misses_with_lateral_offset() -> void:
	# Blade sweeps parallel but 0.6 m away in Z — outside radius.
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(-2, 0, 0.6), Vector3(2, 0, 0.6), 0.5))


# ── Both puck and blade moving toward each other ─────────────────────────────

func test_pickup_both_moving_toward_each_other() -> void:
	# Puck moves from X=2 → X=1; blade moves from X=−1 → X=0.
	# At closest approach they are 1 m apart — within radius 0.5? No, 1 > 0.5.
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(2, 0, 0), Vector3(1, 0, 0),
		Vector3(-1, 0, 0), Vector3(0, 0, 0), 0.5))


func test_pickup_both_moving_toward_each_other_collision() -> void:
	# Puck moves from X=1 → X=0.3; blade moves from X=0 → X=0.6.
	# Segments overlap in X around 0.3–0.6 → within radius.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(1, 0, 0), Vector3(0.3, 0, 0),
		Vector3(0, 0, 0), Vector3(0.6, 0, 0), 0.5))


# ── Degenerate zero-length blade segment ─────────────────────────────────────

func test_pickup_degenerate_blade_segment_hit() -> void:
	# blade_prev == blade_curr — degenerates to segment-vs-point.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.3), Vector3(0.5, 0, 0.3), 0.5))


func test_pickup_degenerate_blade_segment_miss() -> void:
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.6), Vector3(0.5, 0, 0.6), 0.5))


func test_pickup_both_segments_degenerate() -> void:
	# puck_prev == puck_curr and blade_prev == blade_curr — pure point-vs-point.
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(0.3, 0, 0), Vector3(0.3, 0, 0), 0.5))
	assert_false(PuckInteractionRules.check_pickup(
		Vector3(0, 0, 0), Vector3(0, 0, 0),
		Vector3(0.6, 0, 0), Vector3(0.6, 0, 0), 0.5))


# ── 3D coverage ───────────────────────────────────────────────────────────────

func test_pickup_works_correctly_with_y_offset() -> void:
	assert_true(PuckInteractionRules.check_pickup(
		Vector3(0, 0.05, 0), Vector3(1, 0.05, 0),
		Vector3(0.5, 0.05, 0.3), Vector3(0.5, 0.05, 0.3), 0.5))


# ── check_poke ────────────────────────────────────────────────────────────────

func test_poke_detects_direct_hit() -> void:
	assert_true(PuckInteractionRules.check_poke(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0), Vector3(0.5, 0, 0), 0.5))


func test_poke_misses_when_outside_radius() -> void:
	assert_false(PuckInteractionRules.check_poke(
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0.5, 0, 0.6), Vector3(0.5, 0, 0.6), 0.5))


func test_poke_and_pickup_return_same_result_for_same_inputs() -> void:
	var cases: Array = [
		[Vector3(0,0,0), Vector3(1,0,0), Vector3(0.5,0,0.3), Vector3(0.5,0,0.3), 0.5],
		[Vector3(0,0,0), Vector3(1,0,0), Vector3(0.5,0,0.6), Vector3(0.5,0,0.6), 0.5],
		[Vector3(0,0,0), Vector3(0,0,0), Vector3(0.4,0,0),   Vector3(0.4,0,0),   0.5],
		[Vector3(0,0,0), Vector3(10,0,0), Vector3(5,0,0.3),  Vector3(5,0,0.3),   0.5],
		# Fast blade sweep through stationary puck.
		[Vector3(0,0,0), Vector3(0,0,0), Vector3(-2,0,0),    Vector3(2,0,0),     0.5],
	]
	for c: Array in cases:
		var pickup := PuckInteractionRules.check_pickup(c[0], c[1], c[2], c[3], c[4])
		var poke   := PuckInteractionRules.check_poke(c[0], c[1], c[2], c[3], c[4])
		assert_eq(pickup, poke, "check_pickup and check_poke disagree for %s" % str(c))
