extends GutTest

# ── A carrier already at speed against one defender with a start ─────────────
# test_nz_turnover_recovery catches the defender flat on a turnover; this one
# gives him the depth a gap D should have and asks whether a carrier who has
# built his speed through the neutral zone still burns him.
#
# Scored against the best a body could do: a straight backward retreat to the
# house gate from a stand, after a real bot's reaction, on the movement model's
# own backward caps (AIStrideRamp). A start is WINNABLE when that retreat reaches
# the gate a body's width goal-side. A rush is LOST when, at any tick with the
# carrier inside our blue line, the defender is not goal-side of him — not
# between him and our net along his line to it (a defender inside a carrier on
# the wall is goal-side however far the two are from the net). Reference
# readings over these 32 starts, winnable rushes lost:
#
#   the last man commits a hit at the blue line                  7
#   no hit without support behind; RUSH_D1's route past the line 2
#
# WHAT THE HARNESS DOES NOT MODEL: body collisions. The carrier skates through
# the defender, so a body in his lane only stops him by stripping the puck.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = 1.0 / 120.0
const SECS: float = 5.0
const START_Z: float = 8.0
# A hard bot's perception delay plus one brain period before its role changes.
const BOUND_REACTION_S: float = 0.05 + TeamBrain.TICK_PERIOD
# A body's width, so a coin-flip finish is not held against the bot.
const WINNABLE_MARGIN_M: float = 0.5

const MAX_WINNABLE_LOST: int = 3


func _gate_z() -> float:
	return -(GameRules.GOAL_LINE_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M)


# One rush: the carrier at `speed` from `carrier_x`, the defender standing
# `depth` goal-side at `d_x`, facing the play. Returns the worst margin (+ =
# the defender goal-side of the carrier, along the carrier's line to our net)
# while the carrier is inside our blue line, or INF if he never got in.
func _rush(carrier_x: float, d_x: float, depth: float, speed: float) -> float:
	var duel := Duel.new()
	duel.add_skater(1, 0, Vector3(carrier_x, 0.0, START_Z), BotSkillProfile.hard(),
			Vector3(0.0, 0.0, -speed))
	duel.add_skater(2, 1, Vector3(d_x, 0.0, START_Z - depth), BotSkillProfile.hard())
	duel.start(1)
	duel._skater(1).facing = Vector2(0.0, -1.0)
	duel._skater(2).facing = Vector2(0.0, 1.0)
	var net := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	var worst: float = INF
	for _t: int in int(SECS / DT):
		duel.step()
		if duel.strips > 0 or duel.carrier_id != 1:
			break
		var car: Object = duel._skater(1)
		if car.pos.z < -GameRules.BLUE_LINE_Z:
			var to_net: Vector3 = (net - car.pos).normalized()
			worst = minf(worst, (duel._skater(2).pos - car.pos).dot(to_net))
		if car.pos.z <= _gate_z():
			break
	return worst


# The best backward retreat's margin at the gate when the carrier gets there.
func _best_margin(cfg: SkaterMovementRules.MovementConfig, depth: float,
		speed: float) -> float:
	var to_gate: float = START_Z - _gate_z()
	var t: float = AIStrideRamp.time_to_cover(speed, to_gate,
			cfg.max_speed * cfg.puck_carry_speed_multiplier, cfg.thrust)
	var retreat: float = AIStrideRamp.distance_in(0.0, maxf(t - BOUND_REACTION_S, 0.0),
			cfg.max_speed * cfg.backward_max_speed_multiplier,
			cfg.thrust * cfg.backward_thrust_multiplier)
	return depth + retreat - to_gate


func test_a_defender_with_a_start_is_not_burned_by_speed() -> void:
	var cfg: SkaterMovementRules.MovementConfig = Duel.new().move_cfg
	var lost: Array[String] = []
	var winnable: int = 0
	for speed: float in [7.5, 9.0]:
		for depth: float in [8.0, 10.0, 12.0, 14.0]:
			var best: float = _best_margin(cfg, depth, speed)
			var row: String = "  v%.1f %2.0f m [best %+5.1f] :" % [speed, depth, best]
			for lane: Array in [[0.0, 0.0], [-8.0, -3.0], [8.0, 3.0], [-8.0, -8.0]]:
				var worst: float = _rush(lane[0], lane[1], depth, speed)
				row += "  c%+2.0f/d%+2.0f %s" % [lane[0], lane[1],
						"   ok" if worst >= 0.0 else "%+5.1f" % worst]
				if best <= WINNABLE_MARGIN_M:
					continue
				winnable += 1
				if worst < 0.0:
					lost.append("v%.1f/%.0fm/c%.0f/d%.0f" % [speed, depth, lane[0], lane[1]])
			gut.p(row)
	gut.p("  → winnable rushes lost %d/%d %s" % [lost.size(), winnable, str(lost)])
	assert_gt(winnable, 16, "the sweep produced too few winnable starts to read anything")
	assert_lte(lost.size(), MAX_WINNABLE_LOST,
			"a carrier at speed burned a defender a straight retreat would have kept: %s"
					% str(lost))
