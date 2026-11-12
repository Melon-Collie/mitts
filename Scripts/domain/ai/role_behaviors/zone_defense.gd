class_name AIRoleZoneDefense

# The five 5v5 DZONE area roles (ZONE_D_STRONG / ZONE_D_WEAK / ZONE_C /
# ZONE_W_STRONG / ZONE_W_WEAK). Geometry lives in AIZoneCoverage, which a team
# a man down reads as the wedge and one. Design: docs/5v5-ai-plan.md §3.
#
# Per dispatch, in priority order:
#   1. PRESSURE — I own the puck (AIZoneCoverage.pressure_slot): my area holds it,
#      or I am goal-side of a carrier coming at pace — unless it is loose and a
#      teammate is elected to race it, when I cover a man like the rest.
#   2. COVER — the man TeamBrain's matching gave me; my area is his eligibility,
#      so when he leaves my ice the neighbour whose ice he enters picks him up.
#   3. BREATHE — the area's rest anchor, which slides with the puck.

static func decide(ctx: RoleContext, role_slot: int) -> RoleDecision:
	var own_goal_z: float = ctx.defending_goal_pos.z
	var strong_x: float = ctx.strong_x
	var man_down: bool = ctx.team_brain != null and ctx.team_brain.man_down()

	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		var d0 := RoleDecision.new()
		d0.target_position = AIZoneCoverage.anchor_of(
				role_slot, strong_x, own_goal_z, ctx.self_pos, man_down)
		return d0

	var puck_pos: Vector3 = ctx.snapshot.puck_state.position

	if AIZoneCoverage.pressure_slot(ctx.team_brain, strong_x, own_goal_z, puck_pos) \
			== role_slot and not AIZoneCoverage.chased_by_another(ctx.snapshot, ctx.team_id,
					ctx.peer_id):
		return AIRolePressure.decide(ctx)

	var man_pid: int = ctx.assigned_threat_peer
	var d := RoleDecision.new()
	if AIDefensiveVerbs.cover_threat(ctx, d, man_pid,
			AIRoleReads.resolve_defensive_play_ref(ctx)):
		d.locked_man_pid = man_pid
		return d

	d.target_position = AIZoneCoverage.anchor_of(
			role_slot, strong_x, own_goal_z, puck_pos, man_down)
	return d
