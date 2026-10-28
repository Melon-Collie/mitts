extends GutTest

# ── The lone defender against a 2-on-1 ───────────────────────────────────────
# A carrier with a mate wide, one defender (RUSH_D1, odd numbers) with a start.
# What the defence gives up is read in one currency: the first shot each rush
# produces, at its release —
#
#   a one-timer   the receiver fires within ONE_TIMER_WINDOW_S of the catch:
#                 the feed's odds (AIShotValue.feed), the keeper home on the
#                 passer as it leaves
#   any other     the shot from where it leaves, the keeper set on it, the
#                 defender where he stands (score_shoot_value)
#
# and nothing for a strip or an interception. The doctrine is "the goalie takes
# the shooter, I take the pass": a defender who gives up the shot from the
# carrier's side to deny the seam is doing his job, so the reading is the
# conceded odds, not which of the two shot.
#
# The sweep cannot rank fan designs: rushes are chaotic, and variants a few
# hundredths apart swap places when the ATTACK changes. Mean conceded over this
# 30-rush sweep, against two versions of the attack (the outlet's spot read
# before and after it moved onto AIPossessionValue):
#
#                                                   old attack   new attack
#   the fan gated on LANE_PLAY_DANGER_BAR (shipping)    0.180        0.291
#   the arc fan offered every receiver's lane            0.352        0.251
#   a slide-across fan offered every lane                0.209        0.272
#
# (#798 has the 90-rush readings.) So the bar bounds the pathology, a defender
# who gives the 2-on-1 its shot every time, and sits above every reading.
#
# WHAT THE HARNESS DOES NOT MODEL: body collisions, and a goalie's behaviour (the
# harness keeps a static keeper home in each net).

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECS: float = 5.0
const RUSH_SPEED_M_S: float = 7.0
const START_Z: float = 4.0
const ONE_TIMER_WINDOW_S: float = 0.5
const MAX_MEAN_CONCEDED: float = 0.40


# One rush: carrier 1 at `carrier_x`, mate 3 at `mate_x`, both at speed; the
# defender 2 at `d_z` shading the carrier's side.
func _rush(carrier_x: float, mate_x: float, d_z: float) -> Dictionary:
	var duel := Duel.new()
	var v := Vector3(0.0, 0.0, -RUSH_SPEED_M_S)
	duel.add_skater(1, 0, Vector3(carrier_x, 0.0, START_Z), BotSkillProfile.hard(), v)
	duel.add_skater(3, 0, Vector3(mate_x, 0.0, START_Z), BotSkillProfile.hard(), v)
	duel.add_skater(2, 1, Vector3(carrier_x * 0.3, 0.0, d_z), BotSkillProfile.hard())
	duel.start(1)
	duel._skater(2).facing = Vector2(0.0, 1.0)

	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var keeper := net + Vector3(0.0, 0.0, AIGoalieModel.GOALIE_RESTING_DEPTH_M)
	var holder: int = 1
	var caught_tick: int = 0
	var passer_pos: Vector3 = Vector3.INF
	var seen: int = 0
	for _t: int in int(SECS / DT):
		duel.step()
		if duel.carrier_id == 2 or duel.strips > 0:
			return {"ended": "won", "xg": 0.0, "where": duel.puck_pos}
		if duel.carrier_id != -1 and duel.carrier_id != holder:
			holder = duel.carrier_id
			caught_tick = duel.ticks
		while seen < duel.releases.size():
			var rec: Dictionary = duel.releases[seen]
			seen += 1
			var from: Vector3 = rec["pos"]
			# A release toward the mate is a pass; anything else is the shot.
			var mate: Vector3 = duel._skater(4 - int(rec["peer"])).pos
			var to_mate: Vector3 = mate - from
			var to_net: Vector3 = net - from
			var is_pass: bool = duel.puck_vel.normalized().dot(to_mate.normalized()) \
					> duel.puck_vel.normalized().dot(to_net.normalized())
			if is_pass:
				passer_pos = from
				continue
			var d: Array[Vector3] = [duel._skater(2).pos]
			if passer_pos.is_finite() \
					and float(duel.ticks - caught_tick) * DT <= ONE_TIMER_WINDOW_S:
				return {"ended": "one-timer", "where": from,
						"xg": AIShotValue.feed(passer_pos, from,
								AIPuckLane.expected_pass_speed(passer_pos, from), net,
								keeper, true)}
			return {"ended": "carrier shot" if int(rec["peer"]) == 1 else "mate shot",
					"where": from,
					"xg": AIActionScoring.score_shoot_value(from, net, Vector3.INF, d)}
	return {"ended": "no shot", "xg": 0.0, "where": duel.puck_pos}


func test_the_lone_defender_against_a_two_on_one() -> void:
	var tally: Dictionary = {}
	var xg_sum: float = 0.0
	var n: int = 0
	for d_z: float in [-8.0, -11.0, -14.0, -17.0, -20.0]:
		var row: String = "  D z%4.0f :" % d_z
		for side: float in [-1.0, 1.0]:
			for width: float in [6.0, 8.0, 10.0]:
				var r: Dictionary = _rush(side * 3.0, side * (3.0 - width), d_z)
				n += 1
				xg_sum += r["xg"]
				tally[r["ended"]] = int(tally.get(r["ended"], 0)) + 1
				row += " %s%.0f %s %.3f" % ["L" if side < 0.0 else "R", width,
						r["ended"].substr(0, 4), r["xg"]]
		gut.p(row)
	gut.p("  → mean conceded %.3f over %d rushes | %s" % [xg_sum / float(n), n,
			str(tally)])
	assert_lt(xg_sum / float(n), MAX_MEAN_CONCEDED,
			"the lone defender is giving a 2-on-1 its shot: %s" % str(tally))
