extends GutTest

# ── A defender caught flat in the neutral zone at a turnover ─────────────────
# The regime test_rush_gap_discipline does not reach: that suite starts the gap
# defender at home, behind the stand, so his question is how to MEET a rush. Here
# the puck turns over near him — he is standing (or still drifting up-ice from
# the attack) a few metres goal-side of a carrier who has just got it, and his
# question is whether he can still stop the rush before it reaches the house.
#
# Under the skating ramp a standing body concedes metres before it can match a
# carrier who is already moving, so many of these races are lost by physics
# before any decision is made. The test is therefore scored against the BEST a
# body could do: a straight-line retreat at full drive from the start, after a
# real bot's reaction, priced on the same stride ramp the movement model runs
# (AIStrideRamp). A start is WINNABLE when that retreat reaches the house gate
# with room to spare; the bot is held to winning those, and to containing the
# rush (the puck stripped, the carrier held short of the gate, or the shot forced
# from outside it) as often as it did when the gap model learned the ramp. Where
# each forced shot came from is printed, so a carrier giving up a shot from the
# top of the house shows as what it is.
#
# The sweep is the real decision stack on the duel harness, measured as bodies
# over the rush — no single dispatch can see it. Reference readings over these 36
# starts:
#
#                                   contained   winnable races lost
#   gap-up on current pace              16              3 / 9
#   ramp cushion + gap-up race          19              1 / 9
#   depth-first on the carrier's race   20              1 / 9
#   the carrier's cuts in the stance    18              3 / 9
#   turn-and-skate on retreats only     17              3 / 9
#   hips on the skating line            16              3 / 9
#   hysteresis rides the stand          17              1 / 9
#
# The hips riding the line cost a backpedal its angle to an off-lane carrier,
# and with it the share of the backward top-speed penalty an angled body skips
# (SkaterMovementRules): he skates at the flat 80% his retreat is priced at.
#
# Most of what is still lost sits off the carrier's lane, where the straight-line
# bound ignores the lateral ice the defender must also cover: he drifts wide, the
# defender matches the drift, and the carrier cuts back in the stance faster than
# a defender at that lateral speed can reverse. Covering that is doctrine — how
# much of the drift to give — not a race the defender mispriced.
#
# WHAT THE HARNESS DOES NOT MODEL: body collisions. The carrier skates through
# the defender, so a body in his lane only stops him by stripping the puck.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECS: float = 4.0
const CARRIER_START := Vector3(0.0, 0.0, 3.0)
# The best retreat still has to be read: a hard bot's perception delay plus one
# brain period before its role can change.
const BOUND_REACTION_S: float = 0.05 + TeamBrain.TICK_PERIOD
# How much room the best retreat must have at the gate for the start to count
# as winnable — a body's width, so a coin-flip finish is not held against the bot.
const WINNABLE_MARGIN_M: float = 0.5

const MIN_CONTAINED: int = 16
const MAX_WINNABLE_LOST: int = 3


func _gate_z() -> float:
	return -(GameRules.GOAL_LINE_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M)


# One rush: defender `depth` goal-side of a carrier receiving at `carrier_speed`,
# `lane_x` across, with `up_ice` m/s still carrying him away from his own net and
# facing up-ice, as he would be mid-attack. Returns "contained", the forced
# shot's distance from our net, or the margin by which the defender is goal-side
# when the carrier reaches the house gate.
func _rush(depth: float, lane_x: float, up_ice: float,
		carrier_speed: float) -> Variant:
	var duel := Duel.new()
	duel.add_skater(1, 0, CARRIER_START, BotSkillProfile.hard(),
			Vector3(0.0, 0.0, -carrier_speed))
	duel.add_skater(2, 1, Vector3(lane_x, 0.0, CARRIER_START.z - depth),
			BotSkillProfile.hard(), Vector3(0.0, 0.0, up_ice))
	duel.start(1)
	duel._skater(2).facing = Vector2(0.0, 1.0)
	duel._skater(1).facing = Vector2(0.0, -1.0)
	for _t: int in int(SECS / DT):
		duel.step()
		if duel.strips > 0:
			return "contained"
		for rec: Dictionary in duel.releases:
			if int(rec["peer"]) == 1:
				var at: Vector3 = rec["pos"]
				return "shot %2.0fm" % Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z).distance_to(at)
		var car: Object = duel._skater(1)
		if car.pos.z <= _gate_z():
			return car.pos.z - duel._skater(2).pos.z
	return "contained"


# The straight-line bound: how far goal-side of the carrier the best possible
# retreat is when the carrier reaches the gate, both on the harness's own skating.
func _best_margin(cfg: SkaterMovementRules.MovementConfig, depth: float,
		up_ice: float, carrier_speed: float) -> float:
	var to_gate: float = CARRIER_START.z - _gate_z()
	var carry_max: float = cfg.max_speed * cfg.puck_carry_speed_multiplier
	var t: float = AIStrideRamp.time_to_cover(carrier_speed, to_gate, carry_max,
			cfg.thrust)
	var drift: float = -up_ice * minf(BOUND_REACTION_S, t)
	var retreat: float = AIStrideRamp.signed_distance_in(-up_ice,
			maxf(t - BOUND_REACTION_S, 0.0), cfg.max_speed, cfg.thrust,
			cfg.stop_decel)
	return depth - to_gate + drift + retreat


func test_defender_caught_in_the_neutral_zone_wins_the_races_he_can() -> void:
	var cfg: SkaterMovementRules.MovementConfig = Duel.new().move_cfg
	var contained: int = 0
	var winnable: int = 0
	var lost: Array[String] = []
	for speed: float in [3.0, 6.0]:
		for depth: float in [8.0, 5.0, 3.0]:
			var row: String = "  carrier %.0f m/s, %.0f m goal-side :" % [speed, depth]
			for up: float in [0.0, 3.0]:
				for x: float in [0.0, 2.0, 4.0]:
					var r: Variant = _rush(depth, x, up, speed)
					var best: float = _best_margin(cfg, depth, up, speed)
					var can_win: bool = best > WINNABLE_MARGIN_M
					if can_win:
						winnable += 1
					var tag: String = "v%.0f/d%.0f/up%.0f/x%.0f" % [speed, depth, up, x]
					if r is String:
						contained += 1
						row += "  up%.0f x%.0f %8s" % [up, x,
								"held" if r == "contained" else r]
						continue
					row += "  up%.0f x%.0f %+8.1f" % [up, x, r]
					if can_win and float(r) < 0.0:
						lost.append(tag + " (best %+.1f)" % best)
			gut.p(row)
	gut.p("  → contained %d/36 | winnable races lost %d/%d %s"
			% [contained, lost.size(), winnable, str(lost)])
	assert_gte(contained, MIN_CONTAINED,
			"the rush got through more often than the ramp-aware gap allows")
	assert_lte(lost.size(), MAX_WINNABLE_LOST,
			"the defender lost races a straight retreat would have won: %s"
					% str(lost))
