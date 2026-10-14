class_name AIRoleZoneDefense

# The five 5v5 DZONE area roles (ZONE_D_STRONG / ZONE_D_WEAK / ZONE_C /
# ZONE_W_STRONG / ZONE_W_WEAK). Geometry lives in AIZoneCoverage. Design:
# docs/5v5-ai-plan.md §3.
#
# Per dispatch, in priority order:
#   1. PRESSURE — my area owns the puck (AIZoneCoverage.pressure_owner).
#   2. COVER — the man TeamBrain's matching gave me; my area is his eligibility,
#      so when he leaves my ice the neighbour whose ice he enters picks him up.
#   3. BREATHE — the area's rest anchor, which slides with the puck.

static func decide(ctx: RoleContext, role_slot: int) -> RoleDecision:
	var own_goal_z: float = ctx.defending_goal_pos.z
	var strong_x: float = ctx.strong_x

	if ctx.snapshot == null or ctx.snapshot.puck_state == null:
		var d0 := RoleDecision.new()
		d0.target_position = AIZoneCoverage.anchor_of(
				role_slot, strong_x, own_goal_z, ctx.self_pos)
		return d0

	var puck_pos: Vector3 = ctx.snapshot.puck_state.position

	if AIZoneCoverage.pressure_owner(strong_x, own_goal_z, puck_pos) == role_slot:
		return AIRolePressure.decide(ctx)

	var man_pid: int = ctx.assigned_threat_peer
	var d := RoleDecision.new()
	if AIRoleHelpers.cover_threat(ctx, d, man_pid,
			AIRoleHelpers.resolve_defensive_play_ref(ctx)):
		d.locked_man_pid = man_pid
		return d

	d.target_position = AIZoneCoverage.anchor_of(
			role_slot, strong_x, own_goal_z, puck_pos)
	return d
