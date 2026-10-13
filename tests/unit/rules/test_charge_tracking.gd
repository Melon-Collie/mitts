extends GutTest

# ChargeTracking — wrister STROKE tracking: the stroke's blade travel (the
# power-ceiling gate signal) and the direction-variance reset that starts a
# fresh stroke. Power is NOT tracked here — it's the pure cursor speed
# (SkaterAimingBehavior.cursor_speed_ema) — so accumulate() reports
# { direction, reset, travel }.
#
# accumulate() reads an INTENT pair (cursor motion, drives direction + variance)
# and a BLADE pair (the shot-line bearing, drives the travel).
# These tests exercise a single combined motion unless noted, so each call
# passes the same prev/current position into both the intent and blade pairs.

const VARIANCE_DEG: float = 45.0
const DT: float = 1.0 / 120.0

func test_no_movement_preserves_direction() -> void:
	var dir := Vector3(1, 0, 0)
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, dir, VARIANCE_DEG)
	assert_eq(result.direction, dir, "direction preserved when no movement")
	assert_false(result.reset, "no motion is not a variance break")

func test_tiny_movement_treated_as_none() -> void:
	# Under the 0.001 threshold — no new direction recorded, travel held.
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3.ZERO, Vector3(0.0005, 0, 0), Vector3.ZERO, Vector3(0.0005, 0, 0),
		Vector3.ZERO, VARIANCE_DEG, 1.5)
	assert_eq(result.direction, Vector3.ZERO, "negligible motion records no direction")
	assert_almost_eq(result.travel, 1.5, 0.001, "negligible motion holds travel")

func test_straight_movement_records_direction() -> void:
	var step1: Dictionary = ChargeTracking.accumulate(
		Vector3.ZERO, Vector3(0.5, 0, 0), Vector3.ZERO, Vector3(0.5, 0, 0),
		Vector3.ZERO, VARIANCE_DEG)
	assert_eq(step1.direction, Vector3(1, 0, 0))
	assert_false(step1.reset)

	# Second tick: continues in +X — same stroke, no reset.
	var step2: Dictionary = ChargeTracking.accumulate(
		Vector3(0.5, 0, 0), Vector3(0.8, 0, 0), Vector3(0.5, 0, 0), Vector3(0.8, 0, 0),
		step1.direction, VARIANCE_DEG)
	assert_eq(step2.direction, Vector3(1, 0, 0))
	assert_false(step2.reset, "same-direction motion is the same stroke")

func test_direction_reversal_resets_stroke() -> void:
	# Prev direction is +X; current movement is -X (180°, way past 45° variance).
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3(0.5, 0, 0),           # prev intent pos
		Vector3(0.3, 0, 0),           # current intent pos (moved -X by 0.2)
		Vector3(0.5, 0, 0),           # prev blade pos
		Vector3(0.3, 0, 0),           # current blade pos (moved -X by 0.2)
		Vector3(1, 0, 0),             # prev direction (+X)
		VARIANCE_DEG,
		5.0)                          # current travel (discarded by the break)
	assert_true(result.reset, "big direction change starts a new stroke")
	assert_eq(result.direction, Vector3(-1, 0, 0))

func test_small_direction_change_keeps_stroke() -> void:
	# Small angle change (under variance threshold) is the same stroke.
	var prev_dir := Vector3(1, 0, 0)
	# Move mostly +X, slightly +Z (angle ~18°, under 45°).
	var delta := Vector3(1.0, 0, 0.3).normalized() * 0.5
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3.ZERO, delta, Vector3.ZERO, delta, prev_dir, VARIANCE_DEG)
	assert_false(result.reset, "small wobble is not a variance break")

func test_first_tick_no_prev_direction_no_reset() -> void:
	# prev_direction == Vector3.ZERO → no variance check.
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3.ZERO, Vector3(0.5, 0, 0), Vector3.ZERO, Vector3(0.5, 0, 0),
		Vector3.ZERO, VARIANCE_DEG)
	assert_false(result.reset, "first motion after entry is not a variance break")
	assert_eq(result.direction, Vector3(1, 0, 0))

# ── Stroke travel (the power-ceiling gate signal) ─────────────────────────────

func test_travel_step_xz_length() -> void:
	assert_almost_eq(ChargeTracking.travel_step(Vector3.ZERO, Vector3(0.3, 0, 0.4)),
		0.5, 0.001, "travel step is the XZ path length")
	assert_almost_eq(ChargeTracking.travel_step(Vector3.ZERO, Vector3(0.3, 5.0, 0.4)),
		0.5, 0.001, "vertical component ignored")
	assert_almost_eq(ChargeTracking.travel_step(Vector3.ZERO, Vector3(3, 0, 4), 0.5),
		0.5, 0.001, "step capped at max_step (anti-teleport bound)")

func test_travel_accumulates_over_stroke() -> void:
	# Two ticks of a steady drag: blade sweeps 0.2 then 0.3 → 0.5 m of stroke.
	var s1: Dictionary = ChargeTracking.accumulate(
		Vector3.ZERO, Vector3(0.5, 0, 0),
		Vector3(1.0, 0, 0), Vector3(1.2, 0, 0),
		Vector3.ZERO, VARIANCE_DEG, 0.0)
	assert_almost_eq(s1.travel, 0.2, 0.001, "first tick banks its blade step")
	var s2: Dictionary = ChargeTracking.accumulate(
		Vector3(0.5, 0, 0), Vector3(1.0, 0, 0),
		Vector3(1.2, 0, 0), Vector3(1.5, 0, 0),
		s1.direction, VARIANCE_DEG, s1.travel)
	assert_almost_eq(s2.travel, 0.5, 0.001, "same-stroke steps sum")

func test_travel_holds_without_cursor_intent() -> void:
	# Cursor idle, blade moved anyway (locomotion/IK noise) — no intent, no
	# travel banked: the gate can't be farmed by skating with the blade out.
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3(0.5, 0, 0), Vector3(0.5, 0, 0),
		Vector3(1.0, 0, 0), Vector3(1.4, 0, 0),
		Vector3(1, 0, 0), VARIANCE_DEG, 0.3)
	assert_almost_eq(result.travel, 0.3, 0.001, "idle cursor holds travel")

func test_travel_resets_on_variance_break() -> void:
	# A wiggle's direction reversal starts a fresh stroke: banked travel is
	# discarded and only this tick's step counts — a zig-zag can never
	# accumulate the full-stroke travel that unlocks the power ceiling.
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3(0.5, 0, 0), Vector3(0.3, 0, 0),          # cursor reverses → break
		Vector3(1.0, 0, 0), Vector3(1.1, 0, 0),
		Vector3(1, 0, 0), VARIANCE_DEG, 2.0)
	assert_true(result.reset)
	assert_almost_eq(result.travel, 0.1, 0.001, "travel reset, then this tick's step counted")

func test_travel_step_capped_in_accumulate() -> void:
	# A one-tick blade-target jump across the arc banks only max_travel_step —
	# forged cursor teleports can't buy the stroke.
	var result: Dictionary = ChargeTracking.accumulate(
		Vector3.ZERO, Vector3(0.5, 0, 0),
		Vector3(1.0, 0, 0), Vector3(-1.0, 0, 0),         # 2.0 m target jump
		Vector3.ZERO, VARIANCE_DEG, 0.0, 0.25)
	assert_almost_eq(result.travel, 0.25, 0.001, "per-tick travel bounded by max_travel_step")

# ── Swing anchor (locomotion compensation for camera-framed cursors) ─────────

func test_swing_anchor_world_pinned_for_world_anchored_cursor() -> void:
	# Gamepad shot cursor: re-anchored on the pin's projection every frame, so
	# the world-pinned origin already isolates the gesture.
	var anchor: Vector3 = ChargeTracking.swing_anchor(
		Vector3(2, 0, 3), Vector3(10, 0, -4), Vector3(1, 0, 2), true)
	assert_eq(anchor, Vector3(2, 0, 3), "world-anchored cursor keeps the pinned origin")

func test_swing_anchor_tracks_skater_for_camera_cursor() -> void:
	# Mouse: the anchor translates with the skater since the pin; y flattened.
	var anchor: Vector3 = ChargeTracking.swing_anchor(
		Vector3(2, 0, 3), Vector3(1, 0.5, 6), Vector3(1, 0, 2), false)
	assert_eq(anchor, Vector3(2, 0, 7), "anchor rides the skater's XZ translation")

func test_retreat_banks_no_travel_with_compensated_anchor() -> void:
	# The mouse's WORLD point rides the skater-following camera, so a retreat
	# drags it along with the skater. About a world-pinned anchor that drift
	# banks as stroke travel nobody gestured; the compensated anchor cancels it
	# and reads only the gesture.
	var origin := Vector3.ZERO                      # pinned at charge start
	var skater_at_pin := Vector3(0, 0, 0.9)
	var ticks: int = 30
	var pinned_travel: float = 0.0
	var compensated_travel: float = 0.0
	var prev_pinned := Vector3.ZERO
	var prev_comp := Vector3.ZERO
	for i in range(ticks + 1):
		var t: float = float(i) / float(ticks)
		# Gesture in the player's (camera) frame: a 0.8 m lateral drag.
		var gesture := Vector3(0.9 - 0.8 * t, 0.0, -1.5)
		# Retreat: 3 m away from the aim over the stroke; the camera tracks the
		# skater, so the cursor's world point carries the same drift.
		var drift := Vector3(0, 0, 3.0 * t)
		var cursor_world: Vector3 = origin + gesture + drift
		var skater_pos: Vector3 = skater_at_pin + drift
		var pinned_bearing: Vector3 = cursor_world - ChargeTracking.swing_anchor(
			origin, skater_pos, skater_at_pin, true)
		var comp_bearing: Vector3 = cursor_world - ChargeTracking.swing_anchor(
			origin, skater_pos, skater_at_pin, false)
		if i > 0:
			pinned_travel += ChargeTracking.travel_step(prev_pinned, pinned_bearing)
			compensated_travel += ChargeTracking.travel_step(prev_comp, comp_bearing)
		prev_pinned = pinned_bearing
		prev_comp = comp_bearing
	assert_almost_eq(compensated_travel, 0.8, 0.01, "compensated travel is the gesture alone")
	assert_gt(pinned_travel, 3.0, "a world-pinned anchor banks the retreat too")
