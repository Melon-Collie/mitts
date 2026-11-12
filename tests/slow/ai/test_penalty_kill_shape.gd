extends GutTest

# ── Does a team a man down hold the wedge and one? ───────────────────────────
# Four bots kill a penalty against five attackers set up round the zone, the
# puck carried round the perimeter on the strong side: point, half wall, corner
# and back. Real brains, agents and bodies (the duel harness), over a
# multi-second sim, read every tick the killers are in their D-zone shape.
#
# What it pins is the shape's two halves (AIZoneCoverage's wedge):
#   THE WEDGE STAYS HOME — each of the three wedge men is inside the house on
#     most of those ticks. A wedge man who chases to the wall is the hole the
#     shape exists to deny.
#   THE ONE HUNTS — the fourth man is closer to the puck, on average, than any
#     wedge man is: the perimeter is his.
# Both are orderings, not tuned thresholds. The harness skates no goalie and
# the attackers are scripted, so nothing here says what the kill is worth.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = Duel.DT
const NET_Z: float = -GameRules.GOAL_LINE_Z   # the killers (team 1) defend -Z
const SECS: float = 12.0
# A wedge man leaning out of the house to play a man on its rim is still home.
const HOUSE_RIM_M: float = AIZoneCoverage.AREA_RELEASE_MARGIN_M

const WEDGE: Array[int] = [AIRoleSlots.Slot.ZONE_D_STRONG, AIRoleSlots.Slot.ZONE_D_WEAK,
		AIRoleSlots.Slot.ZONE_C]
const THE_ONE: int = AIRoleSlots.Slot.ZONE_W_STRONG


func _at(x: float, depth: float) -> Vector3:
	return Vector3(x, 0.0, NET_Z + depth)


func _in_the_house(pos: Vector3) -> bool:
	var depth: float = AIZoneCoverage.depth_of(NET_Z, pos)
	return depth >= -HOUSE_RIM_M and depth < AIZoneCoverage.SLOT_TOP_DEPTH_M + HOUSE_RIM_M \
			and absf(pos.x) <= AIZoneCoverage.SLOT_HALF_WIDTH_M + HOUSE_RIM_M


# Runs the kill. `seats` are the four killers' lobby seats (PlayerRules
# positions), so the man in the box is whichever seat is missing.
func _kill(seats: Array[int]) -> Dictionary:
	var duel := Duel.new()
	duel.team_size = 5
	var carrier_path: Array[Vector3] = [_at(6.0, 14.0), _at(10.0, 8.0), _at(9.0, 2.0),
			_at(10.0, 8.0)]
	duel.add_scripted_attacker(1, 0, carrier_path, 4.0)
	var posts: Array[Vector3] = [_at(-1.5, 2.65), _at(0.5, 7.0), _at(-9.0, 8.0),
			_at(-6.0, 14.0)]
	for i: int in posts.size():
		var post: Array[Vector3] = [posts[i]]
		duel.add_scripted_attacker(2 + i, 0, post, 0.0)
	for i: int in 5:
		duel.positions[1 + i] = i
	var spawns: Array[Vector3] = [_at(2.0, 3.0), _at(-2.0, 3.0), _at(1.0, 7.0), _at(6.0, 11.0)]
	for i: int in seats.size():
		duel.add_skater(50 + i, 1, spawns[i], BotSkillProfile.hard())
		duel.positions[50 + i] = seats[i]
	duel.start(1)

	var brain: TeamBrain = duel.brains[1]
	var ticks: int = 0
	var home_ticks: Dictionary = {}
	var slot_ticks: Dictionary = {}
	var dist_sum: Dictionary = {}
	for _t: int in int(SECS / DT):
		duel.step()
		if brain.state != AIPossessionState.State.DZONE or not brain.man_down():
			continue
		ticks += 1
		for pid: int in brain.slot_assignments:
			var slot: int = brain.slot_assignments[pid]
			var pos: Vector3 = duel.skater_pos(pid)
			slot_ticks[slot] = int(slot_ticks.get(slot, 0)) + 1
			dist_sum[slot] = float(dist_sum.get(slot, 0.0)) + pos.distance_to(duel.puck_pos)
			if _in_the_house(pos):
				home_ticks[slot] = int(home_ticks.get(slot, 0)) + 1
	var result: Dictionary = {"ticks": ticks, "home": {}, "puck_dist": {}}
	for slot: int in slot_ticks:
		result.home[slot] = float(home_ticks.get(slot, 0)) / float(slot_ticks[slot])
		result.puck_dist[slot] = float(dist_sum[slot]) / float(slot_ticks[slot])
	return result


func _report(label: String, r: Dictionary) -> void:
	gut.p("  %s: %d D-zone ticks a man down" % [label, r.ticks])
	for slot: int in r.home:
		gut.p("    %-16s in the house %3.0f%%   mean %.1f m from the puck" % [
				AIRoleSlots.Slot.keys()[slot], 100.0 * float(r.home[slot]),
				float(r.puck_dist[slot])])


func _assert_wedge_and_one(label: String, r: Dictionary) -> void:
	assert_gt(int(r.ticks), int(2.0 / DT), "%s: the killers set up in their zone" % label)
	assert_true(r.home.has(THE_ONE), "%s: somebody is the one" % label)
	for slot: int in WEDGE:
		assert_true(r.home.has(slot), "%s: %s is manned"
				% [label, AIRoleSlots.Slot.keys()[slot]])
		if not r.home.has(slot):
			continue
		assert_gt(float(r.home[slot]), 0.5, "%s: %s is home more than he is away"
				% [label, AIRoleSlots.Slot.keys()[slot]])
		if r.puck_dist.has(THE_ONE):
			assert_lt(float(r.puck_dist[THE_ONE]), float(r.puck_dist[slot]),
					"%s: the one is nearer the puck than %s" % [label, AIRoleSlots.Slot.keys()[slot]])


func test_with_a_forward_in_the_box_the_killers_hold_the_wedge_and_one() -> void:
	var r: Dictionary = _kill([3, 4, 0, 1])   # LD, RD, C, LW: the right wing sits
	_report("a forward off", r)
	_assert_wedge_and_one("a forward off", r)


func test_with_a_defenseman_in_the_box_the_killers_hold_the_wedge_and_one() -> void:
	var r: Dictionary = _kill([4, 0, 1, 2])   # RD, C, LW, RW: the left defenseman sits
	_report("a defenseman off", r)
	_assert_wedge_and_one("a defenseman off", r)


# ── Their puck outside our zone: the 1-3 ─────────────────────────────────────
# The same four killers with the attackers breaking out: their carrier starts
# behind his own net and skates the puck up the ice. Read every tick the
# killers are in the set shape.
#   NOBODY IS SENT DEEP — no killer is in the attackers' zone.
#   THREE BACK AND ONE HIGH — the high man is the killer nearest the carrier,
#     and the other three are nearer our line than he is.

const THREE_BACK: Array[int] = [AIRoleSlots.Slot.BACK_STRONG, AIRoleSlots.Slot.BACK_MID,
		AIRoleSlots.Slot.BACK_WEAK]
const HIGH_MAN: int = AIRoleSlots.Slot.NZ_F1
# A body eases onto a stand at their line; this much past it is still on it.
const LINE_SLACK_M: float = 1.0


func _set_shape(seats: Array[int]) -> Dictionary:
	var duel := Duel.new()
	duel.team_size = 5
	var breakout: Array[Vector3] = [Vector3(0.0, 0.0, -NET_Z - 1.5), Vector3(4.0, 0.0, 12.0),
			Vector3(6.0, 0.0, -2.0)]
	duel.add_scripted_attacker(1, 0, breakout, 3.0)
	var posts: Array[Vector3] = [Vector3(-8.0, 0.0, 16.0), Vector3(8.0, 0.0, 14.0),
			Vector3(-5.0, 0.0, 6.0), Vector3(0.0, 0.0, 8.0)]
	for i: int in posts.size():
		var post: Array[Vector3] = [posts[i]]
		duel.add_scripted_attacker(2 + i, 0, post, 0.0)
	for i: int in 5:
		duel.positions[1 + i] = i
	var spawns: Array[Vector3] = [Vector3(-4.0, 0.0, 2.0), Vector3(4.0, 0.0, 2.0),
			Vector3(0.0, 0.0, 6.0), Vector3(-6.0, 0.0, 8.0)]
	for i: int in seats.size():
		duel.add_skater(50 + i, 1, spawns[i], BotSkillProfile.hard())
		duel.positions[50 + i] = seats[i]
	duel.start(1)

	var brain: TeamBrain = duel.brains[1]
	var ticks: int = 0
	var deep_ticks: int = 0
	var slot_ticks: Dictionary = {}
	var carrier_dist: Dictionary = {}
	var line_dist: Dictionary = {}
	for _t: int in int(8.0 / DT):
		duel.step()
		if brain.state != AIPossessionState.State.TRANS_DEFENSE or not brain.man_down():
			continue
		ticks += 1
		var anyone_deep: bool = false
		for pid: int in brain.slot_assignments:
			var slot: int = brain.slot_assignments[pid]
			var pos: Vector3 = duel.skater_pos(pid)
			slot_ticks[slot] = int(slot_ticks.get(slot, 0)) + 1
			carrier_dist[slot] = float(carrier_dist.get(slot, 0.0)) \
					+ pos.distance_to(duel.skater_pos(1))
			# Our line is at -BLUE_LINE_Z; theirs at +BLUE_LINE_Z.
			line_dist[slot] = float(line_dist.get(slot, 0.0)) \
					+ absf(pos.z + GameRules.BLUE_LINE_Z)
			if pos.z > GameRules.BLUE_LINE_Z + LINE_SLACK_M:
				anyone_deep = true
		if anyone_deep:
			deep_ticks += 1
	var result: Dictionary = {"ticks": ticks, "deep_ticks": deep_ticks,
			"carrier_dist": {}, "line_dist": {}}
	for slot: int in slot_ticks:
		result.carrier_dist[slot] = float(carrier_dist[slot]) / float(slot_ticks[slot])
		result.line_dist[slot] = float(line_dist[slot]) / float(slot_ticks[slot])
	return result


func _assert_one_three(label: String, r: Dictionary) -> void:
	gut.p("  %s: %d set-shape ticks a man down, %d with a killer in their zone"
			% [label, r.ticks, r.deep_ticks])
	for slot: int in r.carrier_dist:
		gut.p("    %-12s mean %.1f m from the carrier, %.1f m from our line" % [
				AIRoleSlots.Slot.keys()[slot], float(r.carrier_dist[slot]),
				float(r.line_dist[slot])])
	assert_gt(int(r.ticks), int(2.0 / DT), "%s: the killers set up" % label)
	assert_eq(int(r.deep_ticks), 0, "%s: nobody is sent into their zone" % label)
	assert_true(r.carrier_dist.has(HIGH_MAN), "%s: somebody is the high man" % label)
	assert_false(r.carrier_dist.has(AIRoleSlots.Slot.NZ_MID),
			"%s: the middle layer is the post given up" % label)
	for slot: int in THREE_BACK:
		assert_true(r.carrier_dist.has(slot), "%s: %s is manned"
				% [label, AIRoleSlots.Slot.keys()[slot]])
		if not r.carrier_dist.has(slot) or not r.carrier_dist.has(HIGH_MAN):
			continue
		assert_lt(float(r.carrier_dist[HIGH_MAN]), float(r.carrier_dist[slot]),
				"%s: the high man is nearer the carrier than %s"
				% [label, AIRoleSlots.Slot.keys()[slot]])
		assert_lt(float(r.line_dist[slot]), float(r.line_dist[HIGH_MAN]),
				"%s: %s is nearer our line than the high man"
				% [label, AIRoleSlots.Slot.keys()[slot]])


func test_with_a_forward_in_the_box_the_killers_set_up_one_and_three() -> void:
	_assert_one_three("a forward off", _set_shape([3, 4, 0, 1]))


func test_with_a_defenseman_in_the_box_the_killers_set_up_one_and_three() -> void:
	_assert_one_three("a defenseman off", _set_shape([4, 0, 1, 2]))
