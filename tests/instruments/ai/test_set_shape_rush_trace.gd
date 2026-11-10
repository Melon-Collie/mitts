extends GutTest

# test_five_on_five_set_shape's 3-on-2 off a failed forecheck, traced for the
# starts it still lists as thin (#899): every few ticks, each of ours with his
# slot, where he is and how fast, his distance off our net, and each of theirs
# with how many of ours are goal-side of him (by distance to our net, the test's
# own count) and whether he has the puck. Staged exactly as that test stages it.
# Team 0 (them) attacks -Z; team 1 (us) defends it.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
const THEM: Array[int] = [1, 2, 3]
const US: Array[int] = [11, 12, 13, 14, 15]
const RUSH_Z: float = 16.0
const EVERY_TICKS: int = 18


func _trace(cx: float, fwd_z: float, speed: float, secs: float) -> void:
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
	duel.add_skater(12, 1, Vector3(_side(duel, 12) * 6.0, 0.0, fwd_z - 2.0), BotSkillProfile.hard())
	duel.add_skater(13, 1, Vector3(_side(duel, 13) * 6.0, 0.0, fwd_z + 2.0), BotSkillProfile.hard())
	duel.add_skater(14, 1, Vector3(_side(duel, 14) * 6.0, 0.0, GameRules.BLUE_LINE_Z + 1.0),
			BotSkillProfile.hard())
	duel.add_skater(15, 1, Vector3(_side(duel, 15) * 6.0, 0.0, GameRules.BLUE_LINE_Z + 1.0),
			BotSkillProfile.hard())
	duel.start(1)
	for pid: int in THEM:
		duel._skater(pid).facing = Vector2(0.0, -1.0)
	for pid: int in US:
		duel._skater(pid).facing = Vector2(0.0, 1.0)
	var entered: bool = false
	for t: int in int(secs / DT):
		var released: int = duel.releases.size()
		duel.step()
		if duel.releases.size() > released:
			var rel: Dictionary = duel.releases[-1]
			gut.p("   >>> %.2f release by %d: %s at %s" % [t * DT, rel["peer"],
					rel.get("decision", ""), str(rel["pos"])])
			if rel["team"] == 0 and (rel.get("decision", "") == "SHOOT"
					or rel.get("decision", "") == "ONE_TIMER"):
				return
		var c: int = duel.carrier()
		if c != -1 and duel.team_map[c] == 1:
			gut.p("   >>> %.2f ours has it (%d)" % [t * DT, c])
			return
		var entering: bool = not entered and c != -1 \
				and duel._skater(c).pos.z < -GameRules.BLUE_LINE_Z
		if entering:
			entered = true
		if t % EVERY_TICKS != 0 and not entering:
			continue
		var brain: TeamBrain = duel.brains[1]
		var line: String = "%5.2f%s state %-8s |" % [t * DT, " ENTRY" if entering else "      ",
				AIPossessionState.State.keys()[brain.state]]
		for pid: int in US:
			var s: Object = duel._skater(pid)
			line += " %d %-7s (%5.1f %5.1f) v(%4.1f %4.1f) %4.1fm |" % [pid,
					AIRoleSlots.label(brain.slot_assignments.get(pid, AIRoleSlots.Slot.NONE)),
					s.pos.x, s.pos.z, s.vel.x, s.vel.z, s.pos.distance_to(NET)]
		for pid: int in THEM:
			var a: Vector3 = duel._skater(pid).pos
			line += " %d%s (%5.1f %5.1f) %4.1fm gs %d |" % [pid, "*" if pid == c else " ",
					a.x, a.z, a.distance_to(NET), _goal_side_of(duel, a)]
		gut.p(line)


static func _side(duel: Object, pid: int) -> float:
	return PlayerRules.home_side_x(duel.positions[pid], NET.z)


static func _goal_side_of(duel: Object, pos: Vector3) -> int:
	var n: int = 0
	var d: float = pos.distance_to(NET)
	for pid: int in US:
		if duel._skater(pid).pos.distance_to(NET) < d:
			n += 1
	return n


func test_trace_v7_z24_c6() -> void:
	_trace(6.0, RUSH_Z + 8.0, 7.0, 6.0)
	assert_true(true)


func test_trace_v7_z24_c0() -> void:
	_trace(0.0, RUSH_Z + 8.0, 7.0, 6.0)
	assert_true(true)


func test_trace_v7_z20_c0() -> void:
	# The start beside them that sets three back, to read against.
	_trace(0.0, RUSH_Z + 4.0, 7.0, 6.0)
	assert_true(true)
