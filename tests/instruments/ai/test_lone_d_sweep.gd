extends GutTest

# What a lone defender concedes to a carrier at speed: a Hard bot carrier against
# one Hard defender over a wider grid than test_one_on_one_to_the_crease (three
# speeds, four depths, seven lanes), each rush run until he releases, loses the
# puck or the window ends.
#
# Read all three columns together, never the conceded mean alone:
#   conceded — the odds of his shot at the release, the defender where he
#     stands; a strip or a rush that runs out the window scores 0. So a defender
#     who backs off and never engages reads as conceding LESS: the carrier has
#     not shot yet. A change that lowers this by raising `time` and lowering
#     `lost` has made him passive, not better
#     (test_rush_gap_discipline's stalled carrier is the gate for that).
#   ends — how many rushes ended in a release, a strip, or the window.
#   per release — conceded over the releases alone.
#
# One grid is 84 chaotic rollouts and is not a measurement on its own: a handful
# of shots worth 0.6 carry its sum, and moving the carrier's start 0.4 m across
# has moved its mean from 0.029 to 0.068 with no code change. So the grid is run
# at each of JITTERS_M and the total is what to compare, before against after
# on the same machine.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECS: float = 7.0
const START_Z: float = GameRules.BLUE_LINE_Z + 0.71
const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
# The carrier's start moved this far across the ice, one grid each.
const JITTERS_M: Array[float] = [0.0, 0.4, -0.4]
# A shot worth listing by its start.
const DEAR_SHOT: float = 0.15
# Carrier x, defender x.
const LANES: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(-8.0, -3.0), Vector2(8.0, 3.0),
		Vector2(-8.0, -8.0), Vector2(8.0, 8.0), Vector2(-4.0, 0.0), Vector2(4.0, 0.0)]


class Tally:
	var rushes: int = 0
	var conceded: float = 0.0
	var released: int = 0
	var lost: int = 0
	var timed_out: int = 0
	var in_tight: int = 0

	func add(other: Tally) -> void:
		rushes += other.rushes
		conceded += other.conceded
		released += other.released
		lost += other.lost
		timed_out += other.timed_out
		in_tight += other.in_tight

	func describe() -> String:
		return "%3d rushes | conceded mean %.3f (sum %.2f) | ends: release %d, strip %d, time %d | per release %.3f | released inside 10 m %d" % [
				rushes, conceded / maxf(rushes, 1.0), conceded, released, lost, timed_out,
				conceded / maxf(released, 1.0), in_tight]


# One rush: {end: "rel" | "lost" | "time", m: metres off our net, xg}.
func _rush(carrier_x: float, d_x: float, depth: float, speed: float) -> Dictionary:
	var duel := Duel.new()
	duel.add_skater(1, 0, Vector3(carrier_x, 0.0, START_Z), BotSkillProfile.hard(),
			Vector3(0.0, 0.0, -speed))
	duel.add_skater(2, 1, Vector3(d_x, 0.0, START_Z - depth), BotSkillProfile.hard())
	duel.start(1)
	duel._skater(1).facing = Vector2(0.0, -1.0)
	duel._skater(2).facing = Vector2(0.0, 1.0)
	for _t: int in int(SECS / DT):
		var released: int = duel.releases.size()
		duel.step()
		if duel.releases.size() > released:
			var from: Vector3 = duel.releases[-1]["pos"]
			var defenders: Array[Vector3] = [duel._skater(2).pos]
			return {"end": "rel", "m": from.distance_to(NET),
					"xg": AIActionScoring.score_shoot_value(from, NET, Vector3.INF, defenders)}
		if duel.carrier_id != 1:
			return {"end": "lost", "m": duel._skater(1).pos.distance_to(NET), "xg": 0.0}
	return {"end": "time", "m": duel._skater(1).pos.distance_to(NET), "xg": 0.0}


func _grid(jitter_m: float) -> Tally:
	var tally := Tally.new()
	var dear: Array[String] = []
	for speed: float in [7.5, 8.25, 9.0]:
		for depth: float in [8.0, 10.0, 12.0, 14.0]:
			for lane: Vector2 in LANES:
				var r: Dictionary = _rush(lane.x + jitter_m, lane.y, depth, speed)
				tally.rushes += 1
				tally.conceded += r["xg"]
				match r["end"]:
					"rel":
						tally.released += 1
						if r["m"] < 10.0:
							tally.in_tight += 1
					"lost":
						tally.lost += 1
					_:
						tally.timed_out += 1
				if r["xg"] >= DEAR_SHOT:
					dear.append("v%.2f/%.0fm/c%.0f/d%.0f %.2f@%.1f" % [speed, depth, lane.x,
							lane.y, r["xg"], r["m"]])
	gut.p("  jitter %+.1f m: %s" % [jitter_m, tally.describe()])
	gut.p("      shots worth %.2f+: %s" % [DEAR_SHOT, str(dear)])
	return tally


func test_what_a_lone_defender_concedes() -> void:
	var total := Tally.new()
	for jitter_m: float in JITTERS_M:
		total.add(_grid(jitter_m))
	gut.p("  → total: %s" % total.describe())
	assert_true(true)
