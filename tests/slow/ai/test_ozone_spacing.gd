extends GutTest

# ── How the 5v5 attack spreads over the O-zone (#942) ─────────────────────────
# Five bot attackers against five bot defenders, from a set O-zone possession,
# read every tick the attack is in OZONE shape: how many attackers stand high
# (near the blue line) and how many low (below the circle tops). Even strength is
# 3 low / 2 high (docs/5v5-ai-plan.md §2); the failure this pins is 4 high /
# 1 low, which a D holding the puck at the point used to produce on 66% of the
# ticks: his point handed to a forward, F3 held above the puck on the line, and
# the spare body of every pass sent up to SUPPORT's post.
#
# It also prints, unasserted, where each slot stands (depth, weak-side x) and
# how far its nearest defender is: the spread the shape count cannot see
# (docs/bot-net-front-offense-plan.md, step 1).
#
# Team 0 attacks -Z; team 1 defends it. Depth is metres off their goal line.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECS: float = 6.0
const NET_Z: float = -GameRules.GOAL_LINE_Z
# High: within a few strides of the blue line (19.36 m off the goal line), above
# where the strong point sinks to. Low: below the circle tops.
const HIGH_DEPTH_M: float = 14.0
const LOW_DEPTH_M: float = 10.7
# Share of OZONE ticks with four or more attackers high (measured 0 in every
# fixture, 0.66 with the D holding it before #942).
const FOUR_HIGH_CEILING: float = 0.05
# Attackers low per OZONE tick with the D holding it up top (measured 2.49, 1.31
# before #942).
const HELD_LOW_FLOOR: float = 2.2
# Fixture sanity: the attack has to spend time in OZONE shape.
const MIN_OZONE_TICKS: int = 120


class Result:
	var ozone_ticks: int = 0
	var high_hist: Array[int] = [0, 0, 0, 0, 0, 0]
	var low_sum: int = 0
	# Ticks two attackers stood inside the stations' anti-crowd radius.
	var stacked_ticks: int = 0
	# Per slot over its OZONE ticks: [ticks, Σ depth, Σ weak-side x, Σ nearest
	# defender]. Weak-side x is metres across from the middle away from the puck's
	# side (the brain's strong_x), so negative is strong-side.
	var by_slot: Dictionary[int, Array] = {}
	# Off-puck attackers' nearest-defender distance, summed over their ticks.
	var off_puck_ticks: int = 0
	var off_puck_gap_sum: float = 0.0

	func off_puck_gap() -> float:
		return off_puck_gap_sum / float(maxi(off_puck_ticks, 1))

	func four_high_share() -> float:
		return float(high_hist[4] + high_hist[5]) / float(maxi(ozone_ticks, 1))

	func low_per_tick() -> float:
		return float(low_sum) / float(maxi(ozone_ticks, 1))


func _depth(p: Vector3) -> float:
	return p.z - NET_Z


# `attackers` holds a spawn point per bot attacker, or a [path, speed] pair for a
# scripted one (Duel.add_scripted_attacker: a scripted carrier holds the puck).
func _run(attackers: Array, carrier: int) -> Result:
	var duel := Duel.new()
	duel.team_size = 5
	for i: int in attackers.size():
		if attackers[i] is Array:
			var path: Array[Vector3] = []
			path.assign(attackers[i][0])
			duel.add_scripted_attacker(1 + i, 0, path, attackers[i][1])
		else:
			duel.add_skater(1 + i, 0, attackers[i], BotSkillProfile.hard())
		duel.positions[1 + i] = i
	var box: Array[Vector3] = [
		Vector3(4.0, 0.0, NET_Z + 4.0), Vector3(-2.0, 0.0, NET_Z + 2.0),
		Vector3(0.0, 0.0, NET_Z + 8.0), Vector3(6.5, 0.0, NET_Z + 13.0),
		Vector3(-6.5, 0.0, NET_Z + 13.0)]
	for i: int in box.size():
		duel.add_skater(50 + i, 1, box[i], BotSkillProfile.hard())
		duel.positions[50 + i] = i
	duel.start(carrier)
	var brain: TeamBrain = duel.brains[0]
	var stack_r: float = AIStationSearch.ANTI_CROWD_RADIUS_M
	var r := Result.new()
	for _t: int in int(SECS / DT):
		duel.step()
		if brain.state != AIPossessionState.State.OZONE:
			continue
		r.ozone_ticks += 1
		var high: int = 0
		var stacked: bool = false
		for a: int in range(1, 6):
			var pa: Vector3 = duel._skater(a).pos
			var d: float = _depth(pa)
			if d >= HIGH_DEPTH_M:
				high += 1
			elif d <= LOW_DEPTH_M:
				r.low_sum += 1
			for b: int in range(a + 1, 6):
				var pb: Vector3 = duel._skater(b).pos
				if Vector2(pa.x - pb.x, pa.z - pb.z).length() < stack_r:
					stacked = true
		r.high_hist[high] += 1
		if stacked:
			r.stacked_ticks += 1
		_tally_slots(duel, brain, r)
	return r


func _tally_slots(duel: Duel, brain: TeamBrain, r: Result) -> void:
	for a: int in range(1, 6):
		var pa: Vector3 = duel._skater(a).pos
		var gap: float = INF
		for dfn: int in range(50, 55):
			var pd: Vector3 = duel._skater(dfn).pos
			gap = minf(gap, Vector2(pa.x - pd.x, pa.z - pd.z).length())
		var slot: int = brain.slot_assignments.get(a, AIRoleSlots.Slot.NONE)
		if not r.by_slot.has(slot):
			r.by_slot[slot] = [0, 0.0, 0.0, 0.0]
		var row: Array = r.by_slot[slot]
		row[0] += 1
		row[1] += _depth(pa)
		row[2] += -brain.strong_x() * pa.x
		row[3] += gap
		if slot != AIRoleSlots.Slot.CARRIER:
			r.off_puck_ticks += 1
			r.off_puck_gap_sum += gap


func _report(label: String, r: Result) -> void:
	gut.p("  %-24s ozone %4d | high 0..5: %s | 4+ high %3d%% | low/tick %.2f | stacked %3d%%"
			% [label, r.ozone_ticks, str(r.high_hist), roundi(100.0 * r.four_high_share()),
			r.low_per_tick(), roundi(100.0 * r.stacked_ticks / float(maxi(r.ozone_ticks, 1)))])
	gut.p("  %-24s off-puck nearest defender %.2f m" % ["", r.off_puck_gap()])
	for slot: int in r.by_slot:
		var row: Array = r.by_slot[slot]
		var n: float = float(maxi(row[0], 1))
		gut.p("  %-24s   %-14s %4d ticks | depth %5.1f | weak x %+5.1f | nearest D %4.1f"
				% ["", AIRoleSlots.label(slot), row[0], row[1] / n, row[2] / n, row[3] / n])


func _assert_spread(label: String, r: Result) -> void:
	assert_gt(r.ozone_ticks, MIN_OZONE_TICKS, "%s: never settled into OZONE shape" % label)
	assert_lt(r.four_high_share(), FOUR_HIGH_CEILING,
			"%s: the attack stood four high on %d%% of its O-zone ticks"
			% [label, roundi(100.0 * r.four_high_share())])


# C, LW, RW, LD, RD: peers 1..5, in a set 2-high / 3-low shape.
func _set_shape() -> Array:
	return [
		Vector3(0.0, 0.0, NET_Z + 10.0),    # C, high slot
		Vector3(8.5, 0.0, NET_Z + 5.0),     # LW, strong wall low
		Vector3(-1.0, 0.0, NET_Z + 2.5),    # RW, net front
		Vector3(6.0, 0.0, NET_Z + 18.0),    # LD, strong point
		Vector3(-4.0, 0.0, NET_Z + 18.4),   # RD, weak point
	]


func test_a_d_holding_it_up_top_keeps_three_low() -> void:
	# The D pair scripted: the LD holds the puck walking the line, the RD holds
	# the weak point. Only the three bot forwards decide, so this is where they go
	# while a D has the puck up top.
	gut.p("  ── 5v5 O-zone spacing (high = %.1f m+ off the goal line, low = %.1f m or less) ──"
			% [HIGH_DEPTH_M, LOW_DEPTH_M])
	var attack: Array = _set_shape()
	attack[3] = [[Vector3(6.0, 0.0, NET_Z + 18.0), Vector3(1.0, 0.0, NET_Z + 18.5)], 1.5]
	attack[4] = [[Vector3(-4.0, 0.0, NET_Z + 18.4), Vector3(-5.0, 0.0, NET_Z + 18.0)], 1.0]
	var r: Result = _run(attack, 4)
	_report("D holds it up top", r)
	_assert_spread("D holds it up top", r)
	assert_gt(r.low_per_tick(), HELD_LOW_FLOOR,
			"D holds it up top: the forwards drift up off the low ice")


func test_a_bot_attack_stays_spread() -> void:
	# All ten bots, from the D carrying at the point and from a forward carrying
	# low: whatever they do with it, never four high.
	for case: Array in [["D carries at the point", 4], ["F carries low", 2],
			["C carries high slot", 1]]:
		var r: Result = _run(_set_shape(), case[1])
		_report(case[0], r)
		_assert_spread(case[0], r)
