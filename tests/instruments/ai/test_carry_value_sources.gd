extends GutTest

# Where the carrier's decisions get their value, through the breakout and the
# neutral-zone entry drills: every SAMPLE_S while our carrier has the puck, what
# won the compete (pass, shot, carry), and for a carry what set the winning
# move's worth — the spot the move ends on (its own position value), the
# destination carried on from there, the second step searched from there, or the
# pass option it opens — and how far off the destination was. Tallied by the
# zone currency the carrier was in (exit, enter, score). The chosen move is
# re-priced from the carrier's last search at the sample, as
# test_entry_moment_trace.gd does. Reports only.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const Entry := preload("res://tests/instruments/ai/test_nz_entry_drill.gd")
const Breakout := preload("res://tests/instruments/ai/test_breakout_drill.gd")
const SAMPLE_S: float = 0.25
const RUN_S: float = 8.0
const EPS: float = 1e-4
const OBJECTIVES: Array[String] = ["score", "enter", "exit"]
const SOURCES: Array[String] = ["pass", "shoot", "stand", "drive-in floor", "spot", "destination",
		"second step", "pass option"]

# objective → source → count; objective → destination distances (m) when the
# destination set the value.
var _tally: Dictionary = {}
var _dest_m: Dictionary = {}


func test_carry_value_sources() -> void:
	for o: String in OBJECTIVES:
		_tally[o] = {}
		_dest_m[o] = []
	var entry: Object = Entry.new()
	for n_def: int in [2, 3]:
		for x: float in [0.0, 3.0, 5.0, -6.0, -9.0]:
			for v: float in [1.0, 3.0, 5.0]:
				_sample_run(entry._setup(x, v, n_def))
	entry.free()
	var breakout: Object = Breakout.new()
	for cx: float in [-8.0, -3.0, 0.0, 4.0, 9.0]:
		for cz: float in [20.0, 24.0]:
			for f1_gap: float in [4.0, 7.0]:
				var carrier := Vector3(cx, 0, cz)
				var f1 := carrier + Vector3(-signf(cx + 0.1), 0, -f1_gap)
				_sample_run(breakout._setup(carrier, f1, Vector3(-cx * 0.5, 0, 12.0)))
	breakout.free()
	for o: String in OBJECTIVES:
		var counts: Dictionary = _tally[o]
		var total: int = 0
		for k: String in counts:
			total += int(counts[k])
		if total == 0:
			continue
		var line: String = "%-5s %4d samples:" % [o, total]
		for k: String in SOURCES:
			if counts.has(k):
				line += "  %s %.0f%%" % [k, 100.0 * int(counts[k]) / total]
		gut.p(line)
		var ds: Array = _dest_m[o]
		if not ds.is_empty():
			ds.sort()
			gut.p("      destination %.0f m off at the median (%.0f–%.0f m)" % [ds[ds.size() / 2],
					ds[0], ds[-1]])
	assert_true(true)


# One drill run: every SAMPLE_S while team 0 has the puck, tally its decision.
func _sample_run(duel: Object) -> void:
	var every: int = int(SAMPLE_S / Duel.DT)
	for i: int in int(RUN_S / Duel.DT):
		duel.step()
		if (i + 1) % every != 0:
			continue
		var c: int = duel.carrier()
		if c == -1:
			continue
		if duel.team_map[c] != 0:
			return
		_sample(duel._skater(c))


func _sample(s: Object) -> void:
	var agent: SkaterAgentStateMachine = s.agent
	var car: AIRoleCarrier = agent._carrier
	var field: AICarrierField = car._field
	var o: String = OBJECTIVES[field.objective]
	var winner: String = agent.debug_winner()
	if winner == "PASS" or winner == "SHOOT":
		_count(o, winner.to_lower())
		return
	if winner != "CARRY":
		return
	if field.drive_in_reached.is_finite() and car.last_carry_anchor == field.drive_in_reached:
		_count(o, "drive-in floor")
		return
	var cs: AICarrierCarrySearch = car._carry
	if cs.move < 0:
		_count(o, "stand")
		return
	var source: String = _source(agent._role_ctx, cs, cs.move)
	_count(o, source)
	if source == "destination" and cs.destination.is_finite():
		_dest_m[o].append(agent._role_ctx.self_pos.distance_to(cs.destination))


# Which term set rolled move `m`'s worth: re-priced one-ply, then with the pass
# option only, then with the second step too.
func _source(ctx: RoleContext, cs: AICarrierCarrySearch, m: int) -> String:
	var caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var dest_i: int = cs._dest.kinds.find(cs.destination_kind)
	var dest_arrival: float = cs._dest_arrival[dest_i] if dest_i >= 0 else 0.0
	var incumbent: int = cs._incumbent_move
	cs._incumbent_move = -1
	var one_ply: float = _row(ctx, cs, m, caps, dest_arrival)
	if one_ply == -INF:
		cs._incumbent_move = incumbent
		return "spot"
	var reach: int = cs._move_reach[m]
	var end: Vector3 = cs.rollout.reach_pos(m, reach)
	var t0: float = AICarryRollout.HORIZON_S * reach / AICarryRollout.SAMPLES
	cs._field.project_opponents(t0, cs._scratch_opponents_path, cs._scratch_vels_path, end)
	var arrive: float = cs._arrival_value(ctx, end, cs.rollout.reach_vel(m, reach, ctx.self_pos), t0)
	cs._upgrade_candidate_two_ply(ctx, 0, false, caps, -INF)
	var with_option: float = cs._beam_dest[0]
	_row(ctx, cs, m, caps, dest_arrival)
	cs._upgrade_candidate_two_ply(ctx, 0, true, caps, -INF)
	var full: float = cs._beam_dest[0]
	cs._incumbent_move = incumbent
	if full > with_option + EPS:
		return "second step"
	if with_option > one_ply + EPS:
		return "pass option"
	if one_ply > arrive + EPS:
		return "destination"
	return "spot"


# Rolled move `m`'s one-ply row, priced afresh into an empty beam; its worth, or
# -INF when it adds no row.
func _row(ctx: RoleContext, cs: AICarrierCarrySearch, m: int,
		caps: AISkaterCaps, dest_arrival: float) -> float:
	cs._beam_pos.clear()
	cs._beam_total.clear()
	cs._beam_dest.clear()
	cs._beam_decay.clear()
	cs._beam_safety.clear()
	cs._beam_cost.clear()
	cs._beam_move.clear()
	cs._beam_prune_bound = -INF
	cs._score_move(ctx, m, false, caps, dest_arrival)
	return cs._beam_dest[0] if not cs._beam_dest.is_empty() else -INF


func _count(o: String, source: String) -> void:
	_tally[o][source] = int(_tally[o].get(source, 0)) + 1
