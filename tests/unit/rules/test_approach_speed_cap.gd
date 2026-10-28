extends GutTest

# AILastManDiscipline.approach_speed_cap — the bound behind the last man's
# step-up discipline (PRESSURE's cut-off and RUSH_D1's gap stand both ride it).
#
# It answers one question: how fast may a defender be closing on a rush, given
# the depth he has to spare and the pace the rush is coming at, if he is to be
# travelling WITH that rush by the time it reaches him? Getting rush-matched from
# `v` costs his brake (v²/2B), the ground the rush covers meanwhile, and the
# pivot back up to its pace, and the cap is where that equals the spare depth.
# A rush that can accelerate builds pace and ground through the brake; one held
# at its pace costs closing·v/B + closing²/2a, the closed form.
#
# These pin the SHAPE — monotonicity and the two limits. The shape is what makes
# it a stable control law rather than a plan: every way the situation gets more
# urgent lowers the cap.

const V_MAX: float = 9.0
const ACCEL: float = 10.5


func _cap(spare: float, closing: float) -> float:
	return AILastManDiscipline.approach_speed_cap(spare, closing, V_MAX, ACCEL)


func test_more_spare_depth_allows_more_approach_speed() -> void:
	var prev: float = -1.0
	for spare: float in [1.0, 3.0, 6.0, 10.0, 15.0]:
		var v: float = _cap(spare, 7.0)
		assert_gte(v, prev, "cap is monotone in spare depth; %.2f m -> %.2f m/s"
				% [spare, v])
		prev = v


func test_a_faster_rush_lowers_the_cap() -> void:
	var prev: float = INF
	for closing: float in [1.0, 3.0, 5.0, 7.0, 9.0]:
		var v: float = _cap(10.0, closing)
		assert_lte(v, prev, "cap is monotone (down) in the rush's pace; %.1f m/s -> %.2f"
				% [closing, v])
		prev = v


func test_a_rush_in_tight_leaves_no_approach_at_all() -> void:
	# The whole point of the floor: with barely any depth to spare against a
	# rush at pace there is no closing speed that still gets him turned around,
	# so he holds his ground and makes the rush come to him.
	assert_eq(_cap(0.5, 8.0), 0.0,
			"no spare depth against a flying rush means no approach")


func test_a_stalled_rush_lifts_the_cap_to_the_body_s_own_limit() -> void:
	# Nothing is closing, so there is no rendezvous to lose — the limit must get
	# out of the way entirely or it would veto the gap-up.
	assert_almost_eq(_cap(12.0, 0.0), V_MAX, 0.001,
			"a stalled carrier leaves the defender his full pace")


func test_the_cap_never_exceeds_the_body() -> void:
	# Far from the play the geometry permits more than the legs can deliver.
	assert_lte(_cap(60.0, 2.0), V_MAX, "the cap is bounded by the skater")


func test_the_cap_is_continuous_across_its_floor() -> void:
	# It reaches zero by shrinking, not by falling off a cliff — a step there
	# would put a discontinuity in the stand right where the rush arrives.
	var below: float = _cap(1.0, 8.0)
	var above: float = _cap(1.35, 8.0)
	assert_lt(above, 1.0, "just past the floor the cap is still small; got %.3f"
			% above)
	assert_lte(below, above, "and it climbs from there, not jumps")


func test_a_stalled_carrier_s_burst_caps_the_approach() -> void:
	# Standing still he is no invitation to charge: he starts the moment the
	# defender commits, so the faster his burst the slower the step-up.
	var still: float = _cap(4.0, 0.0)
	var prev: float = still
	for burst: float in [3.0, 6.0, 9.0]:
		var v: float = AILastManDiscipline.approach_speed_cap(4.0, 0.0, V_MAX, ACCEL,
				8.0, burst)
		assert_lt(v, prev, "a %.0f m/s² burst lowers the cap; got %.2f" % [burst, v])
		prev = v


func test_a_carrier_already_at_his_top_speed_has_no_burst_left() -> void:
	# Accelerating from his top speed builds nothing, so the cap is the closed form.
	assert_almost_eq(AILastManDiscipline.approach_speed_cap(10.0, 7.0, V_MAX, ACCEL,
			7.0, 6.0), _cap(10.0, 7.0), 0.001, "nothing left to build")
