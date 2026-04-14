extends GutTest

# ReconciliationRules — threshold checks for deciding when to overwrite
# client-side prediction with server state.

# ── skater_needs_reconcile ───────────────────────────────────────────────────

func test_skater_no_reconcile_when_close() -> void:
	var result: bool = ReconciliationRules.skater_needs_reconcile(
		Vector3.ZERO, Vector3.ZERO,     # client pos + vel
		Vector3(0.01, 0, 0), Vector3.ZERO,  # server (tiny pos diff)
		0.05, 0.1)                      # thresholds
	assert_false(result, "0.01 pos error is under 0.05 threshold")

func test_skater_reconcile_when_position_exceeds_threshold() -> void:
	var result: bool = ReconciliationRules.skater_needs_reconcile(
		Vector3.ZERO, Vector3.ZERO,
		Vector3(0.2, 0, 0), Vector3.ZERO,
		0.05, 0.1)
	assert_true(result, "0.2 pos error exceeds 0.05")

func test_skater_reconcile_when_velocity_exceeds_threshold() -> void:
	var result: bool = ReconciliationRules.skater_needs_reconcile(
		Vector3.ZERO, Vector3.ZERO,
		Vector3.ZERO, Vector3(0.5, 0, 0),
		0.05, 0.1)
	assert_true(result, "0.5 vel error exceeds 0.1")

func test_skater_reconcile_at_exact_threshold() -> void:
	# Using >= semantics: exactly equal triggers reconcile
	var result: bool = ReconciliationRules.skater_needs_reconcile(
		Vector3.ZERO, Vector3.ZERO,
		Vector3(0.05, 0, 0), Vector3.ZERO,
		0.05, 0.1)
	assert_true(result, "equal to threshold counts as reconcile")

func test_skater_no_reconcile_when_both_under() -> void:
	var result: bool = ReconciliationRules.skater_needs_reconcile(
		Vector3(1, 0, 0), Vector3(2, 0, 0),
		Vector3(1.01, 0, 0), Vector3(2.05, 0, 0),
		0.05, 0.1)
	assert_false(result, "both deltas under thresholds → no reconcile")

# ── puck_needs_hard_snap ─────────────────────────────────────────────────────

func test_puck_no_snap_within_threshold() -> void:
	var result: bool = ReconciliationRules.puck_needs_hard_snap(
		Vector3.ZERO, Vector3(2, 0, 0), 3.0)
	assert_false(result, "2.0 error under 3.0 threshold")

func test_puck_snap_past_threshold() -> void:
	var result: bool = ReconciliationRules.puck_needs_hard_snap(
		Vector3.ZERO, Vector3(5, 0, 0), 3.0)
	assert_true(result, "5.0 error past 3.0 threshold")

func test_puck_no_snap_at_exact_threshold() -> void:
	# Using > semantics: exactly equal does NOT snap (only strictly greater)
	var result: bool = ReconciliationRules.puck_needs_hard_snap(
		Vector3.ZERO, Vector3(3, 0, 0), 3.0)
	assert_false(result, "strictly greater than threshold required")
