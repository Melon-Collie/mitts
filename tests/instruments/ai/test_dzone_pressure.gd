extends GutTest

# How hard the puck's owner plays a carrier holding the puck in our end: set
# defenders (3v3 and 5v5, each tier) against a scripted, strippable carrier who
# stands or skates a loop on the half-wall, in the corner, behind the net, at
# the point and in the high slot, with his mates parked. Per run: how near the
# owner's body and blade get, how long until the first touch (a blade in poke
# range, a body on his, a lift, a strip), and how it ends.
#
# Each is run twice. "open": the carrier faces the net with the puck out in
# front of him and protects nothing, the easiest man to strip there is.
# "shield": he keeps his body between the puck and the nearest defender
# (SimSkater.script_shields), the hardest. DZONE_PRESSURE_TRACE names one
# scenario to print tick by tick (DZONE_PRESSURE_STICK adds the owner's cursor,
# blade and facing to it), DZONE_PRESSURE_TIERS the tiers to run.
#
# Read the blade column with the cursor in mind: every stick aim off the puck is
# a facing aim, the cursor on the aim ring (AIBotMechanics
# .CARRY_BLADE_AIM_FORWARD_M) toward its point, so the blade stops that far from
# the body however far the point is.
#
# Team 1 defends -Z.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECS: float = 8.0
const CARRIER := 1
const TRACE_EVERY_TICKS: int = 18

# [name, carrier path, speed, mates' spots].
const SCENARIOS: Array = [
	["half-wall stand", [Vector3(-11.0, 0, -17.0)], 0.0],
	["half-wall walk", [Vector3(-11.0, 0, -14.0), Vector3(-11.0, 0, -21.0)], 3.0],
	["corner stand", [Vector3(-10.0, 0, -25.0)], 0.0],
	["corner cycle", [Vector3(-11.0, 0, -20.0), Vector3(-9.0, 0, -26.0), Vector3(-5.0, 0, -28.0),
			Vector3(-9.0, 0, -26.0)], 4.0],
	["behind net", [Vector3(-1.5, 0, -29.3)], 0.0],
	["behind net walk", [Vector3(-4.0, 0, -29.2), Vector3(4.0, 0, -29.2)], 3.0],
	["point stand", [Vector3(-7.0, 0, -9.0)], 0.0],
	["point walk", [Vector3(-9.0, 0, -9.0), Vector3(6.0, 0, -9.0)], 3.0],
	["high slot loop", [Vector3(-5.0, 0, -12.0), Vector3(5.0, 0, -12.0), Vector3(5.0, 0, -17.0),
			Vector3(-5.0, 0, -17.0)], 4.5],
	["dot stand", [Vector3(-6.7, 0, -20.0)], 0.0],
]
const MATES_3: Array[Vector3] = [Vector3(6.0, 0, -11.0), Vector3(3.0, 0, -22.0)]
const MATES_5: Array[Vector3] = [Vector3(6.0, 0, -11.0), Vector3(3.0, 0, -22.0),
		Vector3(-7.0, 0, -10.0), Vector3(1.0, 0, -15.0)]
const DEFENDERS_3: Array[Vector3] = [Vector3(-3.0, 0, -20.0), Vector3(1.5, 0, -23.0),
		Vector3(1.0, 0, -14.0)]
# Low pair, slot, points (the seats test_zone_coverage_shape.gd uses).
const DEFENDERS_5: Array[Vector3] = [Vector3(-3.5, 0, -22.5), Vector3(2.0, 0, -23.5),
		Vector3(0.0, 0, -18.0), Vector3(-6.0, 0, -14.0), Vector3(5.0, 0, -14.0)]
const DEFENDER_SEATS: Array[int] = [3, 4, 0, 1, 2]


class Run:
	var end: String = "held"
	var end_t: float = SECS
	var touch_t: float = -1.0
	var closest_m: float = INF
	# Over the ticks from 2 s on with the puck still his.
	var settled_ticks: int = 0
	var gap_sum: float = 0.0
	var blade_sum: float = 0.0
	var in_poke_ticks: int = 0
	var unowned_ticks: int = 0
	var owner_speed_sum: float = 0.0
	var states: Dictionary = {}


func _profile(tier: String) -> BotSkillProfile:
	match tier:
		"easy":
			return BotSkillProfile.easy()
		"normal":
			return BotSkillProfile.normal()
	return BotSkillProfile.hard()


func _setup(scenario: Array, size: int, tier: String, shields: bool) -> Object:
	var duel: Object = Duel.new()
	duel.team_size = size
	var path: Array[Vector3] = []
	path.assign(scenario[1])
	if path.size() == 1:
		path.append(path[0])
	duel.add_scripted_attacker(CARRIER, 0, path, scenario[2])
	duel._skater(CARRIER).script_strippable = true
	duel._skater(CARRIER).script_shields = shields
	duel.positions[CARRIER] = 0
	var mates: Array[Vector3] = MATES_3 if size == 3 else MATES_5
	for i: int in mates.size():
		duel.add_scripted_attacker(2 + i, 0, [mates[i], mates[i]] as Array[Vector3], 0.0)
		duel.positions[2 + i] = 1 + i
	var defenders: Array[Vector3] = DEFENDERS_3 if size == 3 else DEFENDERS_5
	for i: int in defenders.size():
		duel.add_skater(50 + i, 1, defenders[i], _profile(tier))
		duel.positions[50 + i] = DEFENDER_SEATS[i] if size == 5 else i
		duel._skater(50 + i).facing = Vector2(0.0, 1.0)
	duel.start(CARRIER)
	return duel


# The defender who has the carrier: the one whose decision is engaged with him
# or says he plays the puck, the nearest of them; -1 when nobody's does.
func _owner(duel: Object) -> int:
	var best: int = -1
	var best_d: float = INF
	var car: Vector3 = duel._skater(CARRIER).pos
	for s: Object in duel.skaters:
		if s.team_id != 1 or s.agent == null:
			continue
		var d: RoleDecision = s.agent._cached_role_decision
		if d == null or not (d.engaged_peer_id == CARRIER or d.pressures_puck or d.commit_check):
			continue
		var dist: float = s.pos.distance_to(car)
		if dist < best_d:
			best_d = dist
			best = s.peer_id
	return best


func _run(scenario: Array, size: int, tier: String, shields: bool, trace: bool) -> Run:
	var duel: Object = _setup(scenario, size, tier, shields)
	var contact_m: float = 2.0 * duel._match_body.radius
	var brain: TeamBrain = duel.brains[1]
	var r := Run.new()
	for i: int in int(SECS / DT):
		duel.step()
		var t: float = (i + 1) * DT
		var car: Object = duel._skater(CARRIER)
		var owner_pid: int = _owner(duel)
		var nearest: Object = null
		for s: Object in duel.skaters:
			if s.team_id == 1 and (nearest == null \
					or s.pos.distance_to(car.pos) < nearest.pos.distance_to(car.pos)):
				nearest = s
		var who: Object = duel._skater(owner_pid) if owner_pid != -1 else nearest
		var gap: float = who.pos.distance_to(car.pos)
		var blade_m: float = who.blade.distance_to(duel.puck_pos)
		r.closest_m = minf(r.closest_m, gap)
		var state: String = AIPossessionState.State.keys()[brain.state]
		r.states[state] = int(r.states.get(state, 0)) + 1
		if r.touch_t < 0.0 and (gap <= contact_m or blade_m <= GameRules.POKE_RADIUS_M
				or duel.strips > 0 or duel.lifts > 0 or duel.hit_strips > 0):
			r.touch_t = t
		if trace and i % TRACE_EVERY_TICKS == 0:
			var d: RoleDecision = who.agent._cached_role_decision
			var slot: int = brain.slot_assignments.get(who.peer_id, 0)
			gut.p("  %.1fs %s own=%d(%s) %s gap=%.2f stand=%.2f blade=%.2f v=%.1f %s%s%s car=(%.1f,%.1f) me=(%.1f,%.1f)" % [
					t, state, owner_pid, AIRoleSlots.Slot.keys()[slot],
					"" if owner_pid != -1 else "NEAREST=%d" % who.peer_id, gap,
					d.target_position.distance_to(car.pos) if d != null else -1.0, blade_m,
					who.vel.length(),
					"CHECK " if d != null and d.commit_check else "",
					"ONPUCK " if d != null and d.pressures_puck else "",
					"hit " if who.input.hit_held else "",
					car.pos.x, car.pos.z, who.pos.x, who.pos.z])
			if OS.get_environment("DZONE_PRESSURE_STICK") != "":
				gut.p("      puck=(%.2f,%.2f) blade=(%.2f,%.2f) mouse=(%.2f,%.2f) facing=(%.2f,%.2f) body-puck=%.2f body-blade=%.2f live=%s lift=%s" % [
						duel.puck_pos.x, duel.puck_pos.z, who.blade.x, who.blade.z,
						who.input.mouse_world_pos.x, who.input.mouse_world_pos.z,
						who.facing.x, who.facing.y, who.pos.distance_to(duel.puck_pos),
						who.pos.distance_to(who.blade), who.agent._off_puck_stick_live,
						who.agent._off_puck_lift_live])
		if duel.carrier_id != CARRIER:
			r.end = "lifted" if duel.lifts > 0 else ("hit" if duel.hit_strips > 0 else "poked")
			r.end_t = t
			return r
		if t >= 2.0:
			r.settled_ticks += 1
			r.gap_sum += gap
			r.blade_sum += blade_m
			r.owner_speed_sum += who.vel.length()
			if blade_m <= GameRules.POKE_RADIUS_M:
				r.in_poke_ticks += 1
			if owner_pid == -1:
				r.unowned_ticks += 1
	return r


func test_dzone_pressure() -> void:
	var only: String = OS.get_environment("DZONE_PRESSURE_TRACE")
	var tiers: Array = ["normal", "hard"]
	if OS.get_environment("DZONE_PRESSURE_TIERS") != "":
		tiers = OS.get_environment("DZONE_PRESSURE_TIERS").split(",")
	for size: int in [3, 5]:
		for tier: String in tiers:
			gut.p("── %dv%d %s ── end@s | first touch s | closest m | settled: gap m, blade-puck m, "
					% [size, size, tier] + "in-poke %, unowned %, owner m/s")
			var taken: Dictionary = {false: 0, true: 0}
			for scenario: Array in SCENARIOS:
				if only != "" and only != scenario[0]:
					continue
				for shields: bool in [false, true]:
					var r: Run = _run(scenario, size, tier, shields, only != "")
					var n: float = maxf(r.settled_ticks, 1)
					if r.end != "held":
						taken[shields] += 1
					gut.p("%-16s %-7s %-6s@%.1f | %5s | %.2f | %.2f, %.2f, %3.0f%%, %3.0f%%, %.1f" % [
							scenario[0], "shield" if shields else "open", r.end, r.end_t,
							"%.1f" % r.touch_t if r.touch_t >= 0.0 else "never", r.closest_m,
							r.gap_sum / n, r.blade_sum / n, 100.0 * r.in_poke_ticks / n,
							100.0 * r.unowned_ticks / n, r.owner_speed_sum / n])
			gut.p("   taken off him: %d of %d open, %d of %d shielding" % [taken[false],
					SCENARIOS.size(), taken[true], SCENARIOS.size()])
	assert_true(true)
