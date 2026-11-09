extends GutTest

# #924's first step: does a lost puck in their corner send our points home? A
# 5v5 cycle, five Hard bots a side: the puck dies in their corner with their D
# nearer it than our low forward, and (scripted) he rims it round the end boards
# and up the far wall. Logged every LOG_EVERY_S: our brain's state and its
# forecheck margin, and each of our D's slot and target; then who first touches
# the rim, and whether the puck leaves the zone. Run with their D playing it
# himself too. Team 0 attacks -Z; the puck dies on the -x side.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const SECS: float = 4.0
const LOG_EVERY_S: float = 0.1
const OURS: Array[int] = [101, 102, 103, 104, 105]
const THEIRS: Array[int] = [201, 202, 203, 204, 205]
const OUR_D: Array[int] = [104, 105]
const THEIR_D_STRONG: int = 204
# How long their D holds the puck before the scripted rim: his read.
const RIM_AFTER_S: float = 0.35
const RIM_SPEED_M_S: float = 20.0


static func _out(p: Vector3) -> float:
	return p.z + GameRules.GOAL_LINE_Z


static func _slot_name(slot: int) -> String:
	return AIRoleSlots.Slot.keys()[slot] if slot >= 0 and slot < AIRoleSlots.Slot.size() \
			else str(slot)


static func _state_name(state: int) -> String:
	return AIPossessionState.State.keys()[state]


func _setup() -> Object:
	var duel: Object = Duel.new()
	duel.team_size = 5
	for k: int in 5:
		duel.positions[OURS[k]] = k
		duel.positions[THEIRS[k]] = k
	var hard: BotSkillProfile = BotSkillProfile.hard()
	var point_z: float = -(GameRules.BLUE_LINE_Z + 2.0)
	# Ours: the low forward a step behind the race, net front, high slot, the points.
	duel.add_skater(OURS[0], 0, Vector3(-7.5, 0, -22.0), hard, Vector3(-1.5, 0, -1.5))
	duel.add_skater(OURS[1], 0, Vector3(0.5, 0, -23.5), hard)
	duel.add_skater(OURS[2], 0, Vector3(-1.0, 0, -16.0), hard)
	duel.add_skater(OURS[3], 0, Vector3(-6.5, 0, point_z), hard)
	duel.add_skater(OURS[4], 0, Vector3(6.0, 0, point_z), hard)
	# Theirs: F1-F3, then the D pair, the strong D on the puck.
	duel.add_skater(THEIRS[0], 1, Vector3(-2.5, 0, -19.5), hard)
	duel.add_skater(THEIRS[1], 1, Vector3(-8.0, 0, -14.0), hard)
	duel.add_skater(THEIRS[2], 1, Vector3(5.0, 0, -15.0), hard)
	duel.add_skater(THEIRS[3], 1, Vector3(-9.8, 0, -24.8), hard)
	duel.add_skater(THEIRS[4], 1, Vector3(-1.0, 0, -24.5), hard)
	duel.start(-1, Vector3(-11.3, 0, -25.6))
	duel.puck_vel = Vector3(-0.8, 0, -0.6)
	return duel


func _agent(duel: Object, peer: int) -> SkaterAgentStateMachine:
	for s: Object in duel.skaters:
		if s.peer_id == peer:
			return s.agent
	return null


func _run(scripted_rim: bool) -> void:
	var duel: Object = _setup()
	var brain: TeamBrain = duel.brains[0]
	var held_ticks: int = 0
	var rimmed: bool = false
	var first_touch: String = ""
	var exit_at: float = -1.0
	var line_left: Dictionary = {}
	var next_log: float = 0.0
	for i: int in int(SECS / Duel.DT):
		var t: float = i * Duel.DT
		var c: int = duel.carrier()
		if scripted_rim and not rimmed and c == THEIR_D_STRONG:
			held_ticks += 1
			if held_ticks * Duel.DT >= RIM_AFTER_S:
				# Round the end boards behind the net, toward the far (+x) wall.
				duel.carrier_id = -1
				duel.loose_released_by = THEIR_D_STRONG
				duel._release_grace[THEIR_D_STRONG] = duel.ticks + Duel.RELEASE_GRACE_TICKS
				duel.puck_vel = Vector3(0.95, 0, -0.3).normalized() * RIM_SPEED_M_S
				rimmed = true
				gut.p("      %.2f s: their D rims it" % t)
		var before: int = duel.carrier()
		duel.step()
		var after: int = duel.carrier()
		if rimmed and first_touch == "" and after != -1 and after != before:
			first_touch = "%s %d at %.2f s, (%.1f, %.1f out)" % [
					"ours" if duel.team_map[after] == 0 else "theirs", after, t,
					duel.puck_pos.x, _out(duel.puck_pos)]
		if exit_at < 0.0 and duel.puck_pos.z > -GameRules.BLUE_LINE_Z:
			exit_at = t
		for d: int in OUR_D:
			if duel.skater_pos(d).z > -GameRules.BLUE_LINE_Z and not line_left.has(d):
				line_left[d] = t
		if t + 0.0001 >= next_log:
			next_log += LOG_EVERY_S
			var row: String = "      %.2f s %-14s margin %5s | puck (%5.1f, %4.1f out) %s" % [
					t, _state_name(brain.state),
					"-" if brain.forecheck_margin_s == -INF else "%.2f" % brain.forecheck_margin_s,
					duel.puck_pos.x, _out(duel.puck_pos),
					"loose" if after == -1 else ("ours" if duel.team_map[after] == 0 else "theirs")]
			for d: int in OUR_D:
				var a: SkaterAgentStateMachine = _agent(duel, d)
				var tgt: Vector3 = a._cached_role_decision.target_position \
						if a != null and a._cached_role_decision != null else Vector3.INF
				var p: Vector3 = duel.skater_pos(d)
				row += " | D%d %-12s at (%5.1f, %5.1f out) -> (%5.1f, %5.1f out)" % [d,
						_slot_name(int(brain.slot_assignments.get(d, -1))), p.x, _out(p),
						tgt.x, _out(tgt)]
			gut.p(row)
	gut.p("      first touch on the rim: %s | puck out of the zone: %s | our D off the line: %s" % [
			first_touch if first_touch != "" else "-",
			"%.2f s" % exit_at if exit_at >= 0.0 else "no", str(line_left)])


func test_their_d_rims_it_up_the_far_wall() -> void:
	gut.p("  scripted rim:")
	_run(true)
	assert_true(true)


func test_their_d_plays_it_himself() -> void:
	gut.p("  their D's own play:")
	_run(false)
	assert_true(true)
