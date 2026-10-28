extends GutTest

# The blocked breakout rim (test_role_carrier.gd's _rim_breakout_ctx) taken
# apart: our D deep in our end with a forechecker on his hip, the winger up the
# half-wall, a defender in the straight lane. Prints what each part of the
# carrier's read comes to — the cached receiver values the rim is ranked by, the
# flat feed's lane, the rim launch and its reach odds, and every term of the
# rim's price (_pass_ev: release contest, lane, miss, the receiver's value on the
# catch, the catch's safety, each loss mode's cost) — beside the carry it is
# compared against. Reports only.

const OUR_NET_Z: float = 26.65
const TEAM_ID: int = 0


func test_rim_breakout_trace() -> void:
	var ctx: RoleContext = _ctx()
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	var field: AICarrierField = c._field
	var ps: AICarrierPassSearch = c._pass
	gut.p("objective %d (0 score, 1 enter, 2 exit); best pass %.4f to %d, rim %s" % [
			field.objective, c._phase_best_pass_score, c._phase_best_pass_peer,
			c._phase_best_pass_rim_dir])
	for i: int in field.receiver_pos.size():
		gut.p("  receiver at (%.1f, %.1f): cached value %.4f" % [field.receiver_pos[i].x,
				field.receiver_pos[i].z, field.receiver_val[i]])
	var recv: SkaterNetworkState = ctx.snapshot.skater_states[2]
	var caps: AISkaterCaps = ctx.caps_by_peer.get(2)
	var origin: Vector3 = AICarrierField.pass_origin(ctx)
	gut.p("flat lane to the winger: %.3f" % AIPuckLane.lane_clear(origin, recv.position,
			field.opponents_release, AIPuckLane.PASS_SPEED_M_S, field.opponent_vels,
			field.opponent_caps, true, field.opponent_blades_release))
	AIRimPass.build(origin, ctx.self_wrister_shot_speed, ctx.defending_goal_pos.z,
			field.opponents, field.opponent_vels, field.opponent_caps)
	var sure: float = ps._rim_launch_for(ctx, recv, 0.0, caps, false)
	gut.p("rim: sure %.3f, x the winger's cached value %.4f = rank %.4f" % [sure,
			field.receiver_value_at(recv.position), sure * field.receiver_value_at(recv.position)])
	if sure <= 0.0:
		assert_true(true)
		return
	var k: int = ps._rim_k
	var t: float = ps._rim_t
	var meet: Vector3 = AIRimPass.meet_point(k, t)
	gut.p("  launch %d at %.1f m/s, meets him at (%.1f, %.1f) %.2f s on; lane %.3f, miss %.3f" % [
			k, AIRimPass.paces[k], meet.x, meet.z, t, ps._rim_lane, ps._rim_miss])
	_price(ctx, field, ps, meet, k, t, recv, caps)
	gut.p("the compete: carry %.4f, pass %.4f, shoot %.4f" % [c.debug_carry_score,
			c.debug_pass_score, c.debug_shoot_score])
	assert_true(true)


# The rim's _pass_ev, term by term.
func _price(ctx: RoleContext, field: AICarrierField, ps: AICarrierPassSearch, meet: Vector3,
		k: int, t: float, recv: SkaterNetworkState, caps: AISkaterCaps) -> void:
	var self_pos: Vector3 = ctx.self_pos
	var release_clean: float = AIPuckLane.release_contest_clean(
			AIPuckLane.release_point_toward(self_pos, self_pos + AIRimPass.dirs[k]),
			field.opponents, field.opponent_caps)
	var drive_in: float = field.receiver_drive_in_value(ctx, meet, caps, recv.velocity,
			Vector3.INF, t)
	var possession: float = ps._possession_on_clock(meet, recv.velocity, caps, t, t)
	var catch_clear: float = AICarrySpace.reach_clearance(meet, t, field.opponents_release,
			field.opponent_vels, field.opponent_caps, AICarrySpace.EVADE_HORIZON_S)
	var catch_safety: float = AICarrySpace.clearance_to_safety(catch_clear,
			AICarrySpace.reach_band_m)
	var horizon: float = field.horizon_value(meet, t, recv.velocity, caps)
	gut.p("  release clean %.3f | drive in from the meet %.4f | his possession on the clock %.4f" % [
			release_clean, drive_in, possession])
	gut.p("  (horizon value at the meet, undiscounted: %.4f; exit odds from there)" % horizon)
	gut.p("  exit odds, split: at the meet now %.4f, at the meet %.2f s on %.4f; where he stands now %.4f, %.2f s on %.4f" % [
			field.horizon_value(meet, 0.0, recv.velocity, caps), t, horizon,
			field.horizon_value(recv.position, 0.0, recv.velocity, caps), t,
			field.horizon_value(recv.position, t, recv.velocity, caps)])
	gut.p("  catch clearance %.2f m -> catch safety %.3f" % [catch_clear, catch_safety])
	var total: float = ps._pass_ev(ctx, meet, AIRimPass.paces[k], t,
			t + AIBotMechanics.BOT_WRISTER_LOOKAHEAD_S, t, caps, ps._rim_lane, ps._rim_miss, recv.velocity, -INF, AIRimPass.dirs[k],
			AIRimPass.opp_meet[k])
	var benefit: float = release_clean * ps._rim_lane * (1.0 - ps._rim_miss) * catch_safety \
			* maxf(drive_in * AIActionScoring.delay_discount(t), possession)
	gut.p("  benefit ~%.4f, rim's price %.4f (so the loss modes cost ~%.4f)" % [benefit, total,
			benefit - total])
	gut.p("  a loss at the release costs %.4f a whole turnover; on the lane %.4f; at the meet %.4f" % [
			field.turnover_cost(AICarrierField.pass_origin(ctx), 1.0),
			field.turnover_cost(AIRimPass.opp_meet[k], 1.0, t) if AIRimPass.opp_meet[k].is_finite()
					else 0.0, field.turnover_cost(meet, 1.0, t)])


# test_role_carrier.gd's _rim_breakout_ctx(true) on its _make_ctx.
func _ctx() -> RoleContext:
	var self_pos := Vector3(3.0, 0, 28.0)
	var skaters: Array = [
		[1, TEAM_ID, self_pos, Vector3.ZERO],
		[2, TEAM_ID, Vector3(11.5, 0, 14.0), Vector3.ZERO],
		[3, 1, Vector3(1.5, 0, 28.5), Vector3(5.0, 0, -1.5)],
		[5, 1, Vector3(-3.0, 0, 18.0), Vector3.ZERO],
		[4, 1, Vector3(7.0, 0, 21.0), Vector3.ZERO],
	]
	var snap := WorldSnapshot.new()
	var team_map: Dictionary = {}
	for entry: Array in skaters:
		var sk := SkaterNetworkState.new()
		sk.position = entry[2]
		sk.facing = Vector2(0.0, -1.0)
		sk.velocity = entry[3]
		snap.skater_states[entry[0]] = sk
		team_map[entry[0]] = entry[1]
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 1
	puck.position = self_pos
	snap.puck_state = puck
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.self_velocity = Vector3.ZERO
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	return ctx
