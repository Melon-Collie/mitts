extends GutTest

# ── A lone carrier skating it in is played, not escorted ─────────────────────
# A carrier who ignores the bots: he holds the puck in his own end while both
# teams settle (they set up rather than chase him), then skates it up through
# the neutral zone and in on their net at his full carry speed, his teammates
# trailing the play. Down the middle and down the wall, 3v3 and 5v5. However the
# defence plays him, he must not reach the net front untouched: through the
# neutral zone their high forward steers him, at their line the D who rode him
# back keeps him (Scripts/domain/ai/CLAUDE.md → "Forecheck or set up"), and the
# zone coverage stays in its zone rather than escorting the trailers.
#
# The carrier is the duel harness's scripted skater on the real stride, strippable
# and checkable; every other body is a real bot.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const ME := 1
const HOLD_S: float = 3.0
const RUSH_S: float = 8.0
const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
# At the net front: a stick off the crease.
const NET_FRONT_M: float = CreaseRules.ARC_RADIUS + GameRules.DEFAULT_STICK_LENGTH_M


class Rush:
	var outcome: String = "time"
	var at_s: float = INF
	var end_net_m: float = INF


# Our carrier from our own slot up lane `lane_x` and in on their net, with our
# two (or four) bots trailing; their three (or five) bots spread through the
# neutral zone to start.
func _rush(five: bool, lane_x: float) -> Rush:
	var duel := Duel.new()
	duel.team_size = 5 if five else 3
	var hold := Vector3(lane_x * 0.3, 0.0, GameRules.GOAL_LINE_Z - 5.65)
	duel.add_scripted_attacker(ME, 0, [hold, hold] as Array[Vector3], 0.0)
	var me: Object = duel._skater(ME)
	me.script_skates = true
	var mates: Array = [[2, Vector3(-8, 0, GameRules.BLUE_LINE_Z + 4.71)], [3, Vector3(8, 0, GameRules.BLUE_LINE_Z + 4.71)]]
	var them: Array = [[11, Vector3(0, 0, -4)], [12, Vector3(-7, 0, -6)],
			[13, Vector3(7, 0, -6)]]
	if five:
		mates += [[4, Vector3(-5, 0, GameRules.GOAL_LINE_Z - 4.65)], [5, Vector3(5, 0, GameRules.GOAL_LINE_Z - 4.65)]]
		them += [[14, Vector3(-5, 0, -GameRules.BLUE_LINE_Z - 8.71)], [15, Vector3(5, 0, -GameRules.BLUE_LINE_Z - 8.71)]]
		duel.positions = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 11: 0, 12: 2, 13: 1, 14: 4, 15: 3}
	for m: Array in mates:
		duel.add_skater(m[0], 0, m[1], BotSkillProfile.hard())
	for t: Array in them:
		duel.add_skater(t[0], 1, t[1], BotSkillProfile.hard())
	duel.start(ME)
	for t: Array in them:
		duel._skater(t[0]).facing = Vector2(0.0, 1.0)

	var r := Rush.new()
	var go_tick: int = int(HOLD_S / DT)
	for t: int in int((HOLD_S + RUSH_S) / DT):
		if t == go_tick:
			me.script_path = [hold, Vector3(lane_x, 0.0, GameRules.BLUE_LINE_Z - 1.29),
					Vector3(lane_x, 0.0, -GameRules.BLUE_LINE_Z + 1.29),
					Vector3(lane_x * 0.4, 0.0, -(GameRules.GOAL_LINE_Z - 8.65)),
					Vector3(0.0, 0.0, -(GameRules.GOAL_LINE_Z - 2.5))] as Array[Vector3]
			me.script_idx = 1
			me.script_speed = duel.move_cfg.max_speed * duel.move_cfg.puck_carry_speed_multiplier
			me.script_strippable = true
		duel.step()
		r.end_net_m = me.pos.distance_to(NET)
		if duel.carrier_id != ME:
			r.outcome = "lost"
			r.at_s = t * DT - HOLD_S
			return r
		if r.end_net_m <= NET_FRONT_M:
			r.outcome = "net"
			r.at_s = t * DT - HOLD_S
			return r
	return r


func test_a_lone_carrier_never_reaches_the_net_front_untouched() -> void:
	var walked_in: Array[String] = []
	for five: bool in [true, false]:
		for lane_x: float in [0.0, -9.0]:
			var label := "%s/x%+.0f" % ["5v5" if five else "3v3", lane_x]
			var r: Rush = _rush(five, lane_x)
			gut.p("  %s: %s at %.2f s, %.1f m off the net" % [label, r.outcome, r.at_s,
					r.end_net_m])
			if r.outcome != "lost":
				walked_in.append(label)
	assert_eq(walked_in.size(), 0, "a lone carrier was not stopped: %s" % str(walked_in))
