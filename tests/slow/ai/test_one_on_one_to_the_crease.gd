extends GutTest

# ── A lone carrier never walks onto the crease untouched ─────────────────────
# One carrier at speed against the one defender between him and the net, from
# the speed-rush sweep's starts (test_speed_rush_defence), run on until he
# releases, loses the puck or reaches the net. However the defender plays the
# gap, a carrier who gets within a stick of the crease with the puck must have
# been touched on the way, at the very last: the defender's body on his, or his
# blade on the puck (in poke range of it, or a strip or lift). A carrier who
# shoots from range, or loses the puck, never got there and passes.
#
# Each row reads the end of each rush (rel/lost/net/time @ metres off our net)
# and the closest the defender came. The keeper is the harness's static one on
# his crease: what the carrier prices his shot against, not a body in the way.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECS: float = 7.0
const START_Z: float = 8.0
const CARRIER := 1
const DEFENDER := 2
# At the crease: a stick off its paint.
const NET_REACHED_M: float = CreaseRules.ARC_RADIUS + GameRules.DEFAULT_STICK_LENGTH_M


class Rush:
	var reached_net: bool = false
	var touched: bool = false
	var outcome: String = "time"
	var end_net_m: float = INF
	var closest_m: float = INF


func _rush(carrier_x: float, d_x: float, depth: float, speed: float) -> Rush:
	var duel := Duel.new()
	duel.add_skater(CARRIER, 0, Vector3(carrier_x, 0.0, START_Z), BotSkillProfile.hard(),
			Vector3(0.0, 0.0, -speed))
	duel.add_skater(DEFENDER, 1, Vector3(d_x, 0.0, START_Z - depth), BotSkillProfile.hard())
	duel.start(CARRIER)
	duel._skater(CARRIER).facing = Vector2(0.0, -1.0)
	duel._skater(DEFENDER).facing = Vector2(0.0, 1.0)
	var contact_m: float = 2.0 * duel._match_body.radius
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var r := Rush.new()
	for _t: int in int(SECS / DT):
		var released: int = duel.releases.size()
		duel.step()
		var car: Object = duel._skater(CARRIER)
		var def: Object = duel._skater(DEFENDER)
		r.closest_m = minf(r.closest_m, car.pos.distance_to(def.pos))
		r.end_net_m = car.pos.distance_to(net)
		if car.pos.distance_to(def.pos) <= contact_m \
				or def.blade.distance_to(duel.puck_pos) <= GameRules.POKE_RADIUS_M \
				or duel.strips > 0 or duel.lifts > 0:
			r.touched = true
		if duel.releases.size() > released:
			r.outcome = "rel"
			return r
		if duel.carrier_id != CARRIER:
			r.outcome = "lost"
			return r
		if r.end_net_m <= NET_REACHED_M:
			r.reached_net = true
			r.outcome = "net"
			return r
	return r


func test_a_carrier_reaches_the_net_only_through_the_defender() -> void:
	var untouched: Array[String] = []
	var reached: int = 0
	for speed: float in [7.5, 9.0]:
		for depth: float in [8.0, 10.0, 12.0, 14.0]:
			var row: String = "  v%.1f %2.0f m :" % [speed, depth]
			for lane: Array in [[0.0, 0.0], [-8.0, -3.0], [8.0, 3.0], [-8.0, -8.0]]:
				var r: Rush = _rush(lane[0], lane[1], depth, speed)
				row += "  c%+2.0f/d%+2.0f %4s@%4.1f closest %.1f%s" % [lane[0], lane[1],
						r.outcome, r.end_net_m, r.closest_m, "" if r.touched else " ·"]
				if r.reached_net:
					reached += 1
					if not r.touched:
						untouched.append("v%.1f/%.0fm/c%.0f/d%.0f" % [speed, depth, lane[0],
								lane[1]])
			gut.p(row)
	gut.p("  → reached the net %d/32 | untouched %d %s  (· = never touched)"
			% [reached, untouched.size(), str(untouched)])
	assert_eq(untouched.size(), 0,
			"a lone carrier walked onto the crease without the defender touching him: %s"
					% str(untouched))
