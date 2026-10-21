extends GutTest

# PuckReceptionRules — receive-vs-deflect decision.
#
# Reactive, RELATIVE-frame model: catch depends on the puck's speed in the
# receiver's frame (puck velocity − receiver velocity) and the blade angle at
# contact. Still no blade-velocity / cushion term — the receiver's SKATING
# velocity is a frame correction, not a stick gesture.

const PICKUP_MAX: float = 8.0
const DEFLECT_MIN: float = 22.0  # mirrors Puck.deflect_min_speed default
const ALIGN_BONUS: float = 8.0
const STILL := Vector3.ZERO  # stationary receiver — collapses to the old absolute model


func test_slow_puck_always_received() -> void:
	# Below pickup_max_speed, alignment doesn't matter.
	var puck_vel := Vector3(5, 0, 0)
	var bad_normal := Vector3(0, 0, 1)  # perpendicular to puck travel
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, STILL, bad_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))


func test_quick_pass_received_at_any_angle() -> void:
	# A snap pass (14 m/s) lands on a blade angled the worst possible way
	# (perpendicular, alignment 0). 14 < threshold 22 → receive, regardless of
	# angle. Passes are not angle-gated.
	var puck_vel := Vector3(14, 0, 0)
	var perp_normal := Vector3(0, 0, 1)
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, STILL, perp_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"a 14 m/s pass should receive even on a perpendicular blade")


func test_bot_arrival_pace_received_at_any_angle_when_static() -> void:
	# The bot pass magnet (PASS_TARGET_CLOSING_M_S) is the puck's CLOSING speed in
	# the receiver's frame; for a stationary receiver that equals its world speed,
	# and it catches at any angle because the target sits under the any-angle
	# ceiling (deflect_min 22).
	var puck_vel := Vector3(AIPuckLane.PASS_TARGET_CLOSING_M_S, 0, 0)
	var perp_normal := Vector3(0, 0, 1)
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, STILL, perp_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"a magnet-pace bot feed should receive on a static receiver at any angle")
	assert_lt(AIPuckLane.PASS_TARGET_CLOSING_M_S, DEFLECT_MIN,
		"the magnet closing pace sits under the any-angle catch ceiling")


func test_hard_shot_glancing_alignment_deflected() -> void:
	# A hard shot (26 m/s) at a glancing blade (alignment 0). Threshold stays 22 →
	# 26 >= 22, deflect. Fast pucks still need a square blade.
	var puck_vel := Vector3(26, 0, 0)
	var face_normal := Vector3(0, 0, 1)
	assert_false(PuckReceptionRules.should_receive(
		puck_vel, STILL, face_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))


func test_hard_shot_dead_on_alignment_received() -> void:
	# Same 26 m/s shot, but the blade face is pointed dead-on (alignment 1.0):
	# threshold = 22 + 8 = 30 → 26 < 30, a clean square reception of a hard shot.
	var puck_vel := Vector3(26, 0, 0)
	var face_normal := Vector3(-1, 0, 0)
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, STILL, face_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))


func test_hard_slapshot_at_square_blade_still_deflects() -> void:
	# 34 m/s slapshot, face pointed dead-on. Even with the full alignment bonus
	# the threshold is 30 m/s — 34 > 30, deflect. Guards against the change
	# making everything sticky: a rocket can't be corralled, square or not.
	var puck_vel := Vector3(34, 0, 0)
	var face_normal := Vector3(-1, 0, 0)
	assert_false(PuckReceptionRules.should_receive(
		puck_vel, STILL, face_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))


func test_partial_alignment_scales_threshold() -> void:
	# Blade ~45° to the incoming puck → alignment ≈ 0.707, threshold ≈ 27.7.
	# A 26 m/s puck catches (26 < 27.7); a 29 m/s puck deflects (29 > 27.7).
	var face_normal := Vector3(-1, 0, 1).normalized()  # 45° off the -X incoming line
	assert_true(PuckReceptionRules.should_receive(
		Vector3(26, 0, 0), STILL, face_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))
	assert_false(PuckReceptionRules.should_receive(
		Vector3(29, 0, 0), STILL, face_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))


func test_zero_alignment_bonus_is_flat_speed_gate() -> void:
	# With alignment_bonus = 0, behavior collapses to a flat relative-speed check
	# at deflect_min_speed regardless of angle.
	var face_normal := Vector3(-1, 0, 0)
	assert_false(PuckReceptionRules.should_receive(
		Vector3(24, 0, 0), STILL, face_normal, PICKUP_MAX, DEFLECT_MIN, 0.0),
		"24 m/s puck with no alignment bonus should deflect at threshold 22")
	assert_true(PuckReceptionRules.should_receive(
		Vector3(20, 0, 0), STILL, face_normal, PICKUP_MAX, DEFLECT_MIN, 0.0),
		"20 m/s puck under baseline threshold should still receive")


# ── Relative frame — the receiver's own velocity shifts the read ─────────────

func test_stretch_pass_to_streaking_receiver_received() -> void:
	# The headline case: a hard 24 m/s stretch pass would deflect off a static
	# perpendicular blade (24 > 22), but the receiver is streaking WITH the pass
	# at 8 m/s — in their frame it arrives at 16 m/s. Easy catch at any angle.
	var puck_vel := Vector3(24, 0, 0)
	var receiver_vel := Vector3(8, 0, 0)
	var perp_normal := Vector3(0, 0, 1)
	assert_false(PuckReceptionRules.should_receive(
		puck_vel, STILL, perp_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"the same pass deflects off a static badly-angled blade")
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, receiver_vel, perp_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"a streaking receiver sees the stretch pass arrive soft")


func test_closing_hard_on_a_feed_steepens_it() -> void:
	# A 20 m/s feed a static receiver catches at any angle (20 < 22) becomes a
	# 30.6 m/s contact for a receiver sprinting head-on into it — above even the
	# fully-squared ceiling (30) → bobble/deflect. Don't charge the pass.
	var puck_vel := Vector3(20, 0, 0)
	var sprint_at_pass := Vector3(-10.6, 0, 0)
	var square_normal := Vector3(-1, 0, 0)
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, STILL, square_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))
	assert_false(PuckReceptionRules.should_receive(
		puck_vel, sprint_at_pass, square_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"sprinting head-on into a hard feed pushes past the squared ceiling")


func test_retreating_with_a_wrister_cushions_it() -> void:
	# Emergent "give with the puck": a max wrister (33 m/s) deflects off a static
	# squared blade (33 > 30), but a receiver skating backward with it at 4 m/s
	# reads it at 29 — squared, that's a catch. Cushioning is a skating read.
	var puck_vel := Vector3(33, 0, 0)
	var retreat := Vector3(4, 0, 0)
	var square_normal := Vector3(-1, 0, 0)
	assert_false(PuckReceptionRules.should_receive(
		puck_vel, STILL, square_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"a max wrister into a static squared blade still deflects")
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, retreat, square_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"retreating with the shot cushions it under the squared ceiling")


func test_skating_onto_a_dying_pass_is_instant_pickup() -> void:
	# Receiver overtaking a slow puck from behind: relative speed is the
	# difference (|9 − 5| = 4 ≤ pickup_max) → unconditional pickup, any angle.
	var puck_vel := Vector3(5, 0, 0)
	var receiver_vel := Vector3(9, 0, 0)
	var perp_normal := Vector3(0, 0, 1)
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, receiver_vel, perp_normal, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS))


func test_alignment_is_judged_in_the_receiver_frame() -> void:
	# A lateral receiver changes the approach LINE, not just the speed. Puck
	# flies +X at 26; receiver strafes 14 m/s along -Z, so in their frame it
	# approaches along (26, 0, 14) at ≈29.5 m/s. A blade squared to the WORLD
	# line (-X face) reads alignment 26/29.5 ≈ 0.88 → threshold ≈29.0 < 29.5 →
	# deflect; squaring to the RELATIVE line (alignment 1.0 → threshold 30)
	# restores the catch. Squareness must track the relative approach.
	var puck_vel := Vector3(26, 0, 0)
	var world_square := Vector3(-1, 0, 0)
	var strafe_fast := Vector3(0, 0, -14)
	assert_false(PuckReceptionRules.should_receive(
		puck_vel, strafe_fast, world_square, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"a hard strafe steepens the relative line past a world-squared blade")
	var rel := puck_vel - strafe_fast
	var rel_square: Vector3 = -rel.normalized()
	assert_true(PuckReceptionRules.should_receive(
		puck_vel, strafe_fast, rel_square, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
		"squaring to the relative approach line restores the catch")


# ── reception_load / settle_time — how hard the catch was ────────────────────

const CLEAN_LOAD: float = 0.30
const SETTLE_MAX_S: float = 0.40


func test_load_agrees_with_the_catch_decision() -> void:
	# should_receive above pickup_max is exactly load < 1, across speeds and angles.
	var normals: Array[Vector3] = [Vector3(0, 0, 1), Vector3(-1, 0, 0),
			Vector3(-1, 0, 1).normalized()]
	for n: Vector3 in normals:
		for speed: float in [9.0, 15.0, 21.9, 22.1, 27.0, 29.9, 30.1, 35.0]:
			var v := Vector3(speed, 0, 0)
			var catch_load: float = PuckReceptionRules.reception_load(v, STILL, n, DEFLECT_MIN, ALIGN_BONUS)
			assert_eq(PuckReceptionRules.should_receive(v, STILL, n, PICKUP_MAX, DEFLECT_MIN, ALIGN_BONUS),
					catch_load < 1.0, "speed %.1f normal %s" % [speed, n])


func test_load_is_relative_speed_over_ceiling_squared() -> void:
	var perp := Vector3(0, 0, 1)
	assert_almost_eq(PuckReceptionRules.reception_load(
			Vector3(11, 0, 0), STILL, perp, DEFLECT_MIN, ALIGN_BONUS), 0.25, 0.0001)
	# A receiver skating with the pass halves the relative speed — a quarter of the load.
	assert_almost_eq(PuckReceptionRules.reception_load(
			Vector3(22, 0, 0), Vector3(11, 0, 0), perp, DEFLECT_MIN, ALIGN_BONUS), 0.25, 0.0001)


func test_squared_blade_carries_less_load() -> void:
	var v := Vector3(18, 0, 0)
	var perp: float = PuckReceptionRules.reception_load(v, STILL, Vector3(0, 0, 1), DEFLECT_MIN, ALIGN_BONUS)
	var square: float = PuckReceptionRules.reception_load(v, STILL, Vector3(-1, 0, 0), DEFLECT_MIN, ALIGN_BONUS)
	assert_lt(square, perp)
	assert_almost_eq(square, 0.36, 0.0001, "18 / 30 squared")


func test_settle_is_zero_up_to_the_clean_load() -> void:
	assert_eq(PuckReceptionRules.settle_time(0.0, CLEAN_LOAD, SETTLE_MAX_S), 0.0)
	assert_eq(PuckReceptionRules.settle_time(CLEAN_LOAD, CLEAN_LOAD, SETTLE_MAX_S), 0.0)


func test_settle_rises_monotonically_to_the_max_at_the_ceiling() -> void:
	var prev: float = 0.0
	for i: int in range(31, 101):
		var t: float = PuckReceptionRules.settle_time(i / 100.0, CLEAN_LOAD, SETTLE_MAX_S)
		assert_gt(t, prev, "load %.2f" % (i / 100.0))
		prev = t
	assert_almost_eq(prev, SETTLE_MAX_S, 0.0001)
	assert_eq(PuckReceptionRules.settle_time(1.5, CLEAN_LOAD, SETTLE_MAX_S), SETTLE_MAX_S,
			"clamped above the ceiling")


func test_short_pass_pace_catches_clean_and_hard_feed_settles() -> void:
	# NHL short passes are received at ~11 m/s on average; failed receptions sit
	# at 13–22 (docs/stick-settling-plan.md). On a poorly angled blade the first
	# is clean and an 18 m/s feed settles for ~0.2 s.
	var perp := Vector3(0, 0, 1)
	var soft: float = PuckReceptionRules.reception_load(Vector3(11, 0, 0), STILL, perp, DEFLECT_MIN, ALIGN_BONUS)
	var hard: float = PuckReceptionRules.reception_load(Vector3(18, 0, 0), STILL, perp, DEFLECT_MIN, ALIGN_BONUS)
	assert_eq(PuckReceptionRules.settle_time(soft, CLEAN_LOAD, SETTLE_MAX_S), 0.0)
	assert_almost_eq(PuckReceptionRules.settle_time(hard, CLEAN_LOAD, SETTLE_MAX_S), 0.21, 0.01)


func test_disabled_settle_never_locks() -> void:
	assert_eq(PuckReceptionRules.settle_time(0.99, 1.0, SETTLE_MAX_S), 0.0)
	assert_eq(PuckReceptionRules.settle_time(0.99, CLEAN_LOAD, 0.0), 0.0)


# ── the bobble: where on the blade, and how hard ────────────────────────────

const AXIS := Vector3(1, 0, 0)       # heel → toe along +X
const MID := Vector3.ZERO
const HALF: float = 0.15


func test_a_path_across_the_middle_meets_it_dead_centre() -> void:
	assert_almost_eq(PuckReceptionRules.blade_contact_offset(
			Vector3(0, 0, 2), Vector3(0, 0, -20), MID, AXIS, HALF), 0.0, 0.0001)


func test_the_offset_runs_out_to_the_toe_and_heel() -> void:
	assert_almost_eq(PuckReceptionRules.blade_contact_offset(
			Vector3(0.075, 0, 2), Vector3(0, 0, -20), MID, AXIS, HALF), 0.5, 0.0001)
	assert_almost_eq(PuckReceptionRules.blade_contact_offset(
			Vector3(-0.15, 0, 2), Vector3(0, 0, -20), MID, AXIS, HALF), 1.0, 0.0001,
			"the heel")
	assert_eq(PuckReceptionRules.blade_contact_offset(
			Vector3(0.4, 0, 2), Vector3(0, 0, -20), MID, AXIS, HALF), 1.0,
			"past the toe, inside the pickup radius, reads as the toe")


func test_an_angled_path_is_read_where_its_line_crosses_the_blade() -> void:
	# From (−1, 2) heading (+1, −2): its line crosses z = 0 at x = 0.
	assert_almost_eq(PuckReceptionRules.blade_contact_offset(
			Vector3(-1, 0, 2), Vector3(5, 0, -10), MID, AXIS, HALF), 0.0, 0.0001)


func test_an_end_on_path_meets_the_toe_or_heel() -> void:
	assert_eq(PuckReceptionRules.blade_contact_offset(
			Vector3(-2, 0, 0.01), Vector3(20, 0, 0), MID, AXIS, HALF), 1.0)


func test_the_crossing_is_read_in_the_receivers_frame() -> void:
	# World path straight down onto the middle; the receiver skating along the
	# blade sees it come in angled, crossing his blade off centre.
	var still: float = PuckReceptionRules.blade_contact_offset(
			Vector3(0, 0, 1), Vector3(0, 0, -10) - Vector3.ZERO, MID, AXIS, HALF)
	var skating: float = PuckReceptionRules.blade_contact_offset(
			Vector3(0, 0, 1), Vector3(0, 0, -10) - Vector3(1.0, 0, 0), MID, AXIS, HALF)
	assert_almost_eq(still, 0.0, 0.0001)
	assert_gt(skating, 0.5)


func test_the_edge_bobbles_sooner_than_the_middle() -> void:
	assert_almost_eq(PuckReceptionRules.bobble_load_at(0.0, 0.67, 0.4), 0.67, 0.0001)
	assert_almost_eq(PuckReceptionRules.bobble_load_at(1.0, 0.67, 0.4), 0.402, 0.0001)
	assert_lt(PuckReceptionRules.bobble_load_at(0.6, 0.67, 0.4),
			PuckReceptionRules.bobble_load_at(0.3, 0.67, 0.4))


func test_the_blade_axis_is_the_face_normals_perpendicular() -> void:
	var blade := Vector3(1.2, 0, -0.3)
	var hand := Vector3(0.2, 0.9, 0.4)
	var axis: Vector3 = PuckReceptionRules.blade_axis(blade, hand, Vector3.FORWARD)
	var normal: Vector3 = PuckReceptionRules.blade_face_normal(blade, hand,
			Vector3(0, 0, 1), Vector3.FORWARD)
	assert_almost_eq(axis.dot(normal), 0.0, 0.0001)
	assert_almost_eq(axis.y, 0.0, 0.0001)


# ── blade_can_interact — on-ice/off-ice gate ─────────────────────────────────

func test_grounded_blade_interacts_with_grounded_puck() -> void:
	assert_true(PuckReceptionRules.blade_can_interact(false, false))


func test_grounded_blade_ignores_airborne_puck() -> void:
	# The saucer-pass change: a stationary grounded blade lets an airborne puck
	# fly over instead of corralling it.
	assert_false(PuckReceptionRules.blade_can_interact(false, true))


func test_lifted_blade_ignores_grounded_puck() -> void:
	assert_false(PuckReceptionRules.blade_can_interact(true, false))


func test_lifted_blade_interacts_with_airborne_puck() -> void:
	# Lifted blade only reaches airborne pucks (and may only tip them — the
	# tip-vs-catch restriction is enforced at the call site, not here). A deflect
	# at HIGH sets blade_up, so this is also the HIGH-deflect (knock-down) reach;
	# FLAT/LOW deflects keep blade_up false and play the ice through the grounded
	# cases above.
	assert_true(PuckReceptionRules.blade_can_interact(true, true))


# ── blade_face_normal ────────────────────────────────────────────────────────

func test_blade_face_normal_opposes_incoming_puck() -> void:
	# Shaft runs hand(origin) → blade(+X). The face perpendicular to it that
	# opposes a +Z-moving puck is -Z.
	var n: Vector3 = PuckReceptionRules.blade_face_normal(
		Vector3(1, 0, 0), Vector3.ZERO, Vector3(0, 0, 5), Vector3(1, 0, 0))
	assert_almost_eq(n, Vector3(0, 0, -1), Vector3(0.001, 0.001, 0.001))


func test_blade_face_normal_is_horizontal_unit() -> void:
	var n: Vector3 = PuckReceptionRules.blade_face_normal(
		Vector3(2, 0.5, 1), Vector3(0, 0.3, 0), Vector3(-1, 0, -1), Vector3(1, 0, 0))
	assert_almost_eq(n.length(), 1.0, 0.001, "result is a unit vector")
	assert_almost_eq(n.y, 0.0, 0.001, "result is horizontal")


func test_blade_face_normal_falls_back_when_shaft_degenerate() -> void:
	# Hand and blade coincident → use the fallback shaft direction (+X here), so
	# the face is along ±Z; the +Z reference flips it to -Z.
	var n: Vector3 = PuckReceptionRules.blade_face_normal(
		Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 1), Vector3(1, 0, 0))
	assert_almost_eq(n, Vector3(0, 0, -1), Vector3(0.001, 0.001, 0.001))
