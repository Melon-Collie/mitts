extends GutTest

# How the 5v5 attack spreads over the O-zone from more starts than the gate
# runs (tests/slow/ai/test_ozone_spacing.gd, whose run and measures this
# borrows): every attacker carrying in turn, from the set shape, its mirror,
# the forwards cycled low on the strong side, and the puck-side D sunk to his
# half-wall. Per run: the share of OZONE ticks with four or more attackers
# high, with three, the attackers low per tick, and how near the high line the
# fourth man came while three stood high (negative: over it).
#
# OZONE_SPREAD_ONLY names one shape to run.

const Spacing := preload("res://tests/slow/ai/test_ozone_spacing.gd")
const NET_Z: float = -GameRules.GOAL_LINE_Z

# C, LW, RW, LD, RD (peers 1..5), depth as metres off their goal line.
const SHAPES: Dictionary = {
	"set": [Vector2(0.0, 10.0), Vector2(8.5, 5.0), Vector2(-1.0, 2.5), Vector2(6.0, 18.0),
			Vector2(-4.0, 18.4)],
	"low cycle": [Vector2(4.0, 7.0), Vector2(10.0, 3.5), Vector2(-1.0, 2.5), Vector2(7.5, 15.0),
			Vector2(-3.0, 18.0)],
	"D sunk": [Vector2(1.0, 9.0), Vector2(9.5, 4.0), Vector2(-2.0, 3.0), Vector2(9.0, 11.5),
			Vector2(-3.0, 18.0)],
	"spread": [Vector2(-2.0, 11.0), Vector2(10.0, 9.0), Vector2(-8.0, 6.0), Vector2(6.5, 18.0),
			Vector2(-5.0, 18.2)],
}


func _shape(spots: Array, mirrored: bool) -> Array:
	var out: Array = []
	for spot: Vector2 in spots:
		out.append(Vector3(-spot.x if mirrored else spot.x, 0.0, NET_Z + spot.y))
	return out


func test_ozone_spread_sweep() -> void:
	var only: String = OS.get_environment("OZONE_SPREAD_ONLY")
	var spacing: Object = Spacing.new()
	var four_high_runs: int = 0
	var runs: int = 0
	for shape: String in SHAPES:
		if only != "" and only != shape:
			continue
		for mirrored: bool in [false, true]:
			gut.p("── %s%s ── carrier | ozone ticks | 4+ high | 3 high | low/tick | fourth under"
					% [shape, " (mirrored)" if mirrored else ""])
			for carrier: int in range(1, 6):
				var r: Object = spacing._run(_shape(SHAPES[shape], mirrored), carrier)
				var n: float = maxf(r.ozone_ticks, 1)
				runs += 1
				if r.high_hist[4] + r.high_hist[5] > 0:
					four_high_runs += 1
				gut.p("   %d | %4d | %3.0f%% | %3.0f%% | %.2f | %s" % [carrier, r.ozone_ticks,
						100.0 * r.four_high_share(), 100.0 * r.high_hist[3] / n, r.low_per_tick(),
						"%+.2f m" % r.fourth_under_m if r.fourth_under_m < INF else "—"])
	gut.p("   four high on any tick in %d of %d runs" % [four_high_runs, runs])
	spacing.free()
	assert_true(true)
