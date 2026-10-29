extends GutTest

# ── The 1-1-3 holds a rush as a team ─────────────────────────────────────────
# A failed forecheck in 5v5: we have lost the puck in their zone with our three
# forwards caught around it and our D on their blue line, and their three
# forwards break out with it at speed. The shape that has to form is the set
# 1-1-3 filled from the back (Scripts/domain/ai/CLAUDE.md → "Forecheck or set
# up"): our line held before anything up the ice, the carrier stood up at it,
# the middle and the weak lane held behind him, the forwards layering in ahead.
# A role test sees one body; only the whole team can show the layer holding.
#
# Real bots on both sides (the duel harness, its static keepers), so their
# carrier passes and shoots as he reads it. Per start, three readings:
#   formed — ours goal-side of the carrier as he crosses our blue line;
#   open   — share of ticks with one of theirs inside our blue line and none of
#            ours goal-side of him (an odd man behind the layer);
#   shot   — where their first shot comes from (metres off our net), if any
#            comes before we take the puck back.
#
# Team 0 (them) attacks -Z; team 1 (us) defends it.
#
# Reference readings over these 12 starts: the back line is never thinner than
# two at entry; an odd man stands behind it for 12% of zone ticks; one start
# ends in a slot shot (KNOWN_SLOT_SHOTS). There their middle man drops it to
# the left wing at our line and both our D stay in the middle while he comes
# down the boards, then cuts across in front of them: BACK_STRONG has no answer
# yet to a wide carrier who gains depth on him outside his reach.
const KNOWN_SLOT_SHOTS: Array[String] = ["v8.5/z24/c-6"]
const MAX_OPEN_SHARE: float = 0.15

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECS: float = 6.0
const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const THEM: Array[int] = [1, 2, 3]
const US: Array[int] = [11, 12, 13, 14, 15]
# The slot a defence must keep a rush out of: out to the hash marks, the posts'
# width plus a stride (test_advantage_scenarios' home plate).
const SLOT_DEPTH_M: float = 10.0
const SLOT_HALF_WIDTH_M: float = 4.0
# Where the break starts: their high slot, already at speed, with our forwards
# caught behind it.
const RUSH_Z: float = 16.0


class Rush:
	var formed: int = -1
	var open_ticks: int = 0
	var zone_ticks: int = 0
	var shot_at: Vector3 = Vector3.INF
	var outcome: String = "time"
	var won_z: float = INF

	func in_slot() -> bool:
		return shot_at.is_finite() and shot_at.distance_to(NET) < SLOT_DEPTH_M \
				and absf(shot_at.x) < SLOT_HALF_WIDTH_M


# Their carrier in lane `cx`, his wingers in the other two of the three lanes,
# all at `speed` from their zone; our forwards caught `fwd_z` deep in it.
func _rush(cx: float, fwd_z: float, speed: float) -> Rush:
	var duel := Duel.new()
	duel.team_size = 5
	duel.positions = {1: 0, 2: 1, 3: 2, 11: 0, 12: 1, 13: 2, 14: 3, 15: 4}
	var vel := Vector3(0.0, 0.0, -speed)
	duel.add_skater(1, 0, Vector3(cx, 0.0, RUSH_Z), BotSkillProfile.hard(), vel)
	var wing: int = 2
	for lane: float in [-8.0, 0.0, 8.0]:
		if absf(lane - cx) < 4.0:
			continue
		duel.add_skater(wing, 0, Vector3(lane, 0.0, RUSH_Z - 1.5), BotSkillProfile.hard(), vel)
		wing += 1
	duel.add_skater(11, 1, Vector3(0.0, 0.0, fwd_z), BotSkillProfile.hard())
	duel.add_skater(12, 1, Vector3(-6.0, 0.0, fwd_z - 2.0), BotSkillProfile.hard())
	duel.add_skater(13, 1, Vector3(6.0, 0.0, fwd_z + 2.0), BotSkillProfile.hard())
	duel.add_skater(14, 1, Vector3(-6.0, 0.0, GameRules.BLUE_LINE_Z + 1.0),
			BotSkillProfile.hard())
	duel.add_skater(15, 1, Vector3(6.0, 0.0, GameRules.BLUE_LINE_Z + 1.0),
			BotSkillProfile.hard())
	duel.start(1)
	for pid: int in THEM:
		duel._skater(pid).facing = Vector2(0.0, -1.0)
	for pid: int in US:
		duel._skater(pid).facing = Vector2(0.0, 1.0)

	var r := Rush.new()
	for _t: int in int(SECS / DT):
		var released: int = duel.releases.size()
		duel.step()
		if duel.releases.size() > released:
			var rel: Dictionary = duel.releases[-1]
			var decision: String = rel.get("decision", "")
			if rel["team"] == 0 and (decision == "SHOOT" or decision == "ONE_TIMER"):
				r.shot_at = rel["pos"]
				r.outcome = "shot"
				return r
		var c: int = duel.carrier()
		if c != -1 and duel.team_map[c] == 1:
			r.outcome = "ours"
			r.won_z = duel.puck_pos.z
			return r
		if c != -1 and r.formed == -1 and duel._skater(c).pos.z < -GameRules.BLUE_LINE_Z:
			r.formed = _goal_side_of(duel, duel._skater(c).pos)
		var any_in: bool = false
		var open: bool = false
		for pid: int in THEM:
			var a: Vector3 = duel._skater(pid).pos
			if a.z >= -GameRules.BLUE_LINE_Z:
				continue
			any_in = true
			if _goal_side_of(duel, a) == 0:
				open = true
		if any_in:
			r.zone_ticks += 1
			if open:
				r.open_ticks += 1
	return r


# How many of ours stand nearer our net than `pos`.
static func _goal_side_of(duel: Object, pos: Vector3) -> int:
	var n: int = 0
	var d: float = pos.distance_to(NET)
	for pid: int in US:
		if duel._skater(pid).pos.distance_to(NET) < d:
			n += 1
	return n


func test_a_failed_forecheck_sets_the_1_1_3_and_it_holds() -> void:
	var thin: Array[String] = []
	var slot_shots: Array[String] = []
	var open_sum: int = 0
	var zone_sum: int = 0
	for speed: float in [7.0, 8.5]:
		for fwd_z: float in [RUSH_Z + 4.0, RUSH_Z + 8.0]:
			var row: String = "  v%.1f fwds z%+.0f :" % [speed, fwd_z]
			for cx: float in [-6.0, 0.0, 6.0]:
				var r: Rush = _rush(cx, fwd_z, speed)
				open_sum += r.open_ticks
				zone_sum += r.zone_ticks
				var label := "v%.1f/z%.0f/c%.0f" % [speed, fwd_z, cx]
				row += "  c%+2.0f formed %d open %3d/%3d %4s%s" % [cx, r.formed,
						r.open_ticks, r.zone_ticks, r.outcome,
						"@%.1f" % r.shot_at.distance_to(NET) if r.shot_at.is_finite()
						else ("@z%+.0f" % r.won_z if r.won_z < INF else "")]
				if r.formed != -1 and r.formed < 2:
					thin.append(label)
				if r.in_slot():
					slot_shots.append(label)
			gut.p(row)
	var open_share: float = float(open_sum) / maxf(float(zone_sum), 1.0)
	gut.p("  → back line thin at entry %d %s | open %.0f%% of zone ticks | slot shots %d %s"
			% [thin.size(), str(thin), open_share * 100.0, slot_shots.size(), str(slot_shots)])
	assert_eq(thin.size(), 0, "the back line was not set when he got there: %s" % str(thin))
	assert_lte(open_share, MAX_OPEN_SHARE, "an odd man stood behind the layer too long")
	for label: String in slot_shots:
		assert_has(KNOWN_SLOT_SHOTS, label, "a rush got a slot shot: %s" % label)
