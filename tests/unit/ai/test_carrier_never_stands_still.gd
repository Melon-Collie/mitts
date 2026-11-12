extends GutTest

# A lone carrier on empty ice outside their zone always has somewhere better to
# be: keeping the puck is worth more up the ice (the floor rises toward their
# zone) and no read goes stale by being skated to, so standing still never wins
# the carry (docs/possession-floor-plan.md §2.4, step 5).

const OUR_NET_Z: float = GameRules.GOAL_LINE_Z


func _ctx(self_pos: Vector3, vel: Vector3) -> RoleContext:
	var snap := WorldSnapshot.new()
	var s := SkaterNetworkState.new()
	s.position = self_pos
	s.velocity = vel
	s.facing = Vector2(0.0, -1.0)
	snap.skater_states[1] = s
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 1
	puck.position = self_pos
	snap.puck_state = puck
	var keeper := GoalieNetworkState.new()
	keeper.position_z = -OUR_NET_Z + 1.3
	snap.goalie_states[1] = keeper
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.self_velocity = vel
	ctx.team_id = 0
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = {1: 0}
	return ctx


func test_a_lone_carrier_outside_their_zone_never_stands_still() -> void:
	for z: float in [24.0, 18.0, 12.0, 6.0, 0.0, -4.0, -6.5]:
		for x: float in [-11.0, -4.0, 0.0, 6.0, 12.0]:
			for vel: Vector3 in [Vector3.ZERO, Vector3(0.0, 0.0, -4.0), Vector3(3.0, 0.0, 2.0)]:
				var c := AIRoleCarrier.new()
				c.decide(_ctx(Vector3(x, 0.0, z), vel))
				var stands: bool = c.intended_action == AIRoleCarrier.INTENT_CARRY \
						and c.carry_move == -1 and c._carry_plan != AIRoleCarrier.CarryPlan.DRIVE_IN
				assert_false(stands, "at (%.0f, %.0f) moving %s he stands still" % [x, z, vel])
