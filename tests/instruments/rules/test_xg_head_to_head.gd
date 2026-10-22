extends GutTest

# The public-style XGBaseline against the goalie-aware geometric model over the
# same shots, printed side by side so the divergence is visible rather than
# argued about.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z   # team 0 attacks -Z


func _centred(dist: float) -> float:
	return XGBaseline.for_shot(0.0, GOAL_Z + dist, 0, ShotEvent.ShotType.SHOT)


func test_print_head_to_head_vs_geometric() -> void:
	# The geometric model is evaluated against a SET, squared goalie playing his
	# depth — i.e. the honest "nobody is beaten yet" case. Where it diverges most
	# from the baseline is exactly where it conditions on a goalie already moved.
	gut.p("  dist   baseline    geometric(set goalie)")
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	var base_sum: float = 0.0
	var geo_sum: float = 0.0
	for d: float in [2.0, 3.0, 5.0, 8.0, 11.0, 15.0, 20.0]:
		var shooter := Vector3(0.0, 0.0, GOAL_Z + d)
		var goalie := Vector3(0.0, 0.0, GOAL_Z + minf(1.3, d * 0.4))
		var base: float = _centred(d)
		var geo: float = AIActionScoring.expected_goals(shooter, goal, goalie)
		base_sum += base
		geo_sum += geo
		gut.p("  %5.0f m   %.3f       %.3f" % [d, base, geo])
	gut.p("  SUM        %.2f        %.2f" % [base_sum, geo_sum])
	assert_gt(base_sum, 0.0, "baseline produced values")


func test_print_head_to_head_vs_beaten_goalie() -> void:
	# THE divergence. Same shots, but the goalie is pulled off his line — the
	# state a forehand-backhand deke creates. The baseline can't see it (a shot
	# from 6 m is a shot from 6 m); the geometric model prices the wide-open net
	# as if the shot were then trivial to finish. The gap here is the missing
	# execution term: getting the goalie moving is step one, burying it is step
	# two, and only the baseline is currently pricing both.
	gut.p("  dist   baseline    geometric(beaten goalie)   ratio")
	var goal := Vector3(0.0, 0.0, GOAL_Z)
	for d: float in [3.0, 5.0, 8.0, 11.0]:
		var shooter := Vector3(0.0, 0.0, GOAL_Z + d)
		var goalie := Vector3(0.9, 0.0, GOAL_Z + 0.6)   # slid off, mid-recovery
		var base: float = _centred(d)
		var geo: float = AIActionScoring.expected_goals(shooter, goal, goalie)
		gut.p("  %5.0f m   %.3f       %.3f                   %.1fx"
				% [d, base, geo, geo / maxf(base, 0.001)])
	pass_test("printed")
