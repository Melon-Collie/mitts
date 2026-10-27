extends "res://tests/instruments/ai/test_entry_decision_maps.gd"

# One decision moment of the entry drill, taken apart: the carrier's last carry
# search at that tick — every destination on the menu and its value, standing
# still, and each rolled move's row (where it ends, its worth there and what
# made it: the arrival value, the destination carried on, the pass option, the
# second step; the decay, the keep odds and the strip cost) — beside the pass and
# the drive-in floor, and how a standing man's chance at a spot grows with how
# far ahead it is read. The moment is MITTS_TRACE_RUN (an index into RUNS) at
# MITTS_TRACE_T seconds. Reports only.

const DEST_NAMES: Array[String] = ["SLOT", "WIDE_L", "WIDE_R", "EXIT_L", "EXIT_R", "WALK_L",
		"WALK_R", "WHEEL_L", "WHEEL_R", "REGROUP"]
const MOVE_NAMES: Array[String] = ["STRAIGHT", "SOFT_L", "SOFT_R", "HARD_L", "HARD_R", "BRAKE",
		"CUT_BACK"]


func test_entry_decision_maps() -> void:
	pass


func test_trace_moment() -> void:
	var run: int = int(OS.get_environment("MITTS_TRACE_RUN")) \
			if OS.has_environment("MITTS_TRACE_RUN") else 0
	var at_s: float = float(OS.get_environment("MITTS_TRACE_T")) \
			if OS.has_environment("MITTS_TRACE_T") else 2.5
	var cfg: Array = RUNS[run]
	var duel: Object = _setup(cfg[0], cfg[1], cfg[2])
	for i: int in int(at_s / Duel.DT + 0.5):
		duel.step()
	var c: int = duel.carrier()
	if c == -1 or duel.team_map[c] != 0:
		gut.p("no carrier of ours at %.2f s" % at_s)
		assert_true(true)
		return
	var s: Object = duel._skater(c)
	var agent: SkaterAgentStateMachine = s.agent
	var car: AIRoleCarrier = agent._carrier
	var cs: AICarrierCarrySearch = car._carry
	var field: AICarrierField = car._field
	var ctx: RoleContext = agent._role_ctx
	gut.p("run %d at %.2f s: carrier %d at (%.1f, %.1f) vel (%.1f, %.1f), objective %d" % [
			run, at_s, c, s.pos.x, s.pos.z, s.vel.x, s.vel.z, field.objective])
	gut.p("  read at (%.1f, %.1f) vel (%.1f, %.1f)" % [ctx.self_pos.x, ctx.self_pos.z,
			ctx.self_velocity.x, ctx.self_velocity.z])
	for o: Object in duel.skaters:
		if o.peer_id != c:
			gut.p("  %d team %d at (%.1f, %.1f) vel (%.1f, %.1f)" % [o.peer_id,
					duel.team_map[o.peer_id], o.pos.x, o.pos.z, o.vel.x, o.vel.z])
	gut.p("decision %s: carry %.3f to (%.1f, %.1f), pass %.3f to %d" % [agent.debug_winner(),
			car.debug_carry_score, car.debug_carry_pos.x, car.debug_carry_pos.z,
			car.debug_pass_score, car.debug_pass_peer_id])
	gut.p("search: value %.3f, move %s, anchor (%.1f, %.1f)" % [cs.value,
			MOVE_NAMES[cs.move] if cs.move >= 0 else "STAND", cs.anchor.x, cs.anchor.z])
	_trace_destinations(cs)
	_trace_stand(ctx, field)
	_trace_moves(ctx, cs)
	var drive: float = field.receiver_drive_in_value(ctx, ctx.self_pos,
			ctx.caps_by_peer.get(ctx.peer_id), ctx.self_velocity, Vector3.INF, 0.0, true)
	gut.p("drive-in floor %.3f, reached (%.1f, %.1f)" % [drive, field.drive_in_reached.x,
			field.drive_in_reached.z])
	_trace_value_field(ctx, field)
	var odds: String = "a man standing 6 m off a spot has his stick set on it, by how far ahead:"
	for t: float in [0.25, 0.5, 1.0, 1.5, 2.0, 3.0]:
		odds += "  %.2f s %.2f" % [t, AIStripOdds.chance_at(Vector3(6.0, 0, 0), Vector3.ZERO, null,
				Vector3.ZERO, t)]
	gut.p(odds)
	assert_true(true)


func _trace_destinations(cs: AICarrierCarrySearch) -> void:
	gut.p("destinations (chosen %s, total %.3f):" % [
			DEST_NAMES[cs.destination_kind] if cs.destination_kind >= 0 else "none",
			cs._dest.chosen_total])
	for i: int in cs._dest.kinds.size():
		var spot: Vector3 = cs._dest.spots[i]
		gut.p("  %-8s at (%5.1f, %5.1f): total %7.3f, worth on arrival %.3f" % [
				DEST_NAMES[cs._dest.kinds[i]], spot.x, spot.z, cs._dest_totals[i],
				cs._dest_arrival[i]])


func _trace_stand(ctx: RoleContext, field: AICarrierField) -> void:
	var here: float = field.horizon_value(ctx.self_pos, 0.0, Vector3.ZERO,
			ctx.caps_by_peer.get(ctx.peer_id))
	var decay: float = AIActionScoring.delay_discount(AICarryRollout.HORIZON_S)
	var puck: Vector3 = AICarrierField.puck_pos_at(ctx.self_pos, ctx.attacking_goal_pos)
	var safety: float = AICarrySpace.carry_safety(puck, puck, AICarrySpace.EVADE_HORIZON_S,
			field.opponents, field.opponent_vels, field.opponent_caps)
	var cost: float = field.turnover_cost(puck, 1.0 - safety)
	gut.p("stand: worth here %.3f x decay %.3f x keep %.3f - cost %.3f = %.3f" % [here, decay,
			safety, cost, here * decay * safety - cost])


# Each move's row priced afresh with no prune, then completed two-ply as the
# search completes its beam.
func _trace_moves(ctx: RoleContext, cs: AICarrierCarrySearch) -> void:
	var caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var our_goalie: Vector3 = AIRoleReads.resolve_our_goalie_pos(ctx)
	var dest_i: int = cs._dest.kinds.find(cs.destination_kind)
	var dest_arrival: float = cs._dest_arrival[dest_i] if dest_i >= 0 else 0.0
	cs._incumbent_move = -1
	gut.p("moves (fan aimed at (%.1f, %.1f)):" % [cs._fan_aim(ctx).x, cs._fan_aim(ctx).z])
	gut.p("  %-9s %-13s %-12s %6s %6s %6s %6s %6s %6s %6s %6s" % ["move", "end", "end vel",
			"arrive", "dest", "1-ply", "2-ply", "decay", "keep", "cost", "total"])
	for m: int in AICarryRollout.MOVE_COUNT:
		cs._beam_pos.clear()
		cs._beam_total.clear()
		cs._beam_dest.clear()
		cs._beam_decay.clear()
		cs._beam_safety.clear()
		cs._beam_cost.clear()
		cs._beam_move.clear()
		cs._beam_prune_bound = -INF
		cs._score_move(ctx, m, our_goalie, false, caps, dest_arrival)
		if cs._beam_total.is_empty():
			gut.p("  %-9s illegal" % MOVE_NAMES[m])
			continue
		var reach: int = cs._move_reach[m]
		var end: Vector3 = cs.rollout.reach_pos(m, reach)
		var end_vel: Vector3 = cs.rollout.reach_vel(m, reach, ctx.self_pos)
		var t0: float = AICarryRollout.HORIZON_S * reach / AICarryRollout.SAMPLES
		cs._field.project_opponents(t0, cs._scratch_opponents_path, cs._scratch_vels_path, end)
		var arrive: float = cs._arrival_value(ctx, end, end_vel, t0)
		var one_ply: float = cs._beam_dest[0]
		cs._upgrade_candidate_two_ply(ctx, 0, true, our_goalie, caps, -INF)
		gut.p("  %-9s (%5.1f,%5.1f) (%5.1f,%5.1f) %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f" % [
				MOVE_NAMES[m], end.x, end.z, end_vel.x, end_vel.z, arrive,
				maxf(one_ply - arrive, 0.0), one_ply, cs._beam_dest[0], cs._beam_decay[0],
				cs._beam_safety[0], cs._beam_cost[0],
				cs._beam_dest[0] * cs._beam_decay[0] * cs._beam_safety[0] - cs._beam_cost[0]])
	gut.p("  (arrive: the shot or position at the end; dest: what carrying on to the "
			+ "destination adds over it; 2-ply: with the pass option and the second step)")


# Our possession of the spot (horizon_value, arriving at the carrier's pace now)
# on a coarse grid ahead of and around him: the shape the moves are valued on.
func _trace_value_field(ctx: RoleContext, field: AICarrierField) -> void:
	var caps: AISkaterCaps = ctx.caps_by_peer.get(ctx.peer_id)
	var v: Vector3 = ctx.self_velocity
	gut.p("worth of the spot, arriving 1 s on at his present velocity (rows z, columns x):")
	var header: String = "        "
	for x: float in [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]:
		header += "%7.0f" % x
	gut.p(header)
	for z: float in [8.0, 5.0, 2.0, -1.0, -4.0, -6.0]:
		var row: String = "  %5.0f " % z
		for x: float in [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]:
			row += "%7.3f" % field.horizon_value(Vector3(x, 0.0, z), 1.0, v, caps)
		gut.p(row)
