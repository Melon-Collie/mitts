extends GutTest

# AIRoleWideLane (WIDE_L / WIDE_R): fill the outside lane a lead ahead of the
# play, held NZ-side of the attacking blue line until the puck crosses it.

const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z   # Team 0 defends +Z, attacks -Z
const ATTACKING_BLUE_Z: float = -GameRules.BLUE_LINE_Z
const LANE_X: float = GameRules.RINK_HALF_WIDTH - AIRoleWideLane.LANE_INSET_M


func _make_ctx(self_pos: Vector3, carrier_pos: Vector3,
		own_goal_dir: float = 1.0) -> RoleContext:
	var snap := WorldSnapshot.new()
	var me := SkaterNetworkState.new()
	me.position = self_pos
	snap.skater_states[1] = me
	var carrier := SkaterNetworkState.new()
	carrier.position = carrier_pos
	snap.skater_states[100] = carrier
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 100
	puck.position = carrier_pos
	snap.puck_state = puck

	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.own_goal_dir = own_goal_dir
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -own_goal_dir * OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, own_goal_dir * OUR_NET_Z)
	ctx.team_id_by_peer = {1: TEAM_ID, 100: TEAM_ID}
	return ctx


func test_no_puck_stands_still() -> void:
	var self_pos := Vector3(5, 0, 0)
	var ctx := _make_ctx(self_pos, Vector3(0, 0, 10))
	ctx.snapshot.puck_state = null
	var d: RoleDecision = AIRoleWideLane.decide(ctx, 1.0)
	assert_eq(d.target_position, self_pos, "no play to fill a lane for")


func test_each_side_fills_its_own_outside_lane() -> void:
	var carrier := Vector3(0, 0, 10)
	var left: RoleDecision = AIRoleWideLane.decide(_make_ctx(Vector3.ZERO, carrier), -1.0)
	var right: RoleDecision = AIRoleWideLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(left.target_position.x, -LANE_X, 1e-4)
	assert_almost_eq(right.target_position.x, LANE_X, 1e-4)
	assert_almost_eq(left.target_position.z, right.target_position.z, 1e-4,
			"the two lanes mirror each other")


func test_the_lane_leads_the_play_up_ice_at_pace() -> void:
	var carrier := Vector3(0, 0, 10)
	var d: RoleDecision = AIRoleWideLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(d.target_position.z, carrier.z - AIRoleWideLane.LEAD_AHEAD_M, 1e-4,
			"a lead ahead of the carrier, toward the net we attack")
	assert_true(d.arrive_at_speed, "the lane advances with the rush")


func test_the_lead_holds_onside_until_the_puck_crosses() -> void:
	# The lead alone would put him past the line while the carrier is outside it.
	var carrier := Vector3(0, 0, ATTACKING_BLUE_Z + 2.0)
	var d: RoleDecision = AIRoleWideLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(d.target_position.z, ATTACKING_BLUE_Z + AIRoleWideLane.LINE_HOLD_BACK_M,
			1e-4, "held a stand-off NZ-side of the attacking blue line")


func test_once_the_puck_is_in_the_lane_leads_into_the_zone() -> void:
	var carrier := Vector3(0, 0, ATTACKING_BLUE_Z - 2.0)
	var d: RoleDecision = AIRoleWideLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(d.target_position.z, carrier.z - AIRoleWideLane.LEAD_AHEAD_M, 1e-4)


func test_the_hold_mirrors_for_the_team_attacking_plus_z() -> void:
	var carrier := Vector3(0, 0, -ATTACKING_BLUE_Z - 2.0)
	var d: RoleDecision = AIRoleWideLane.decide(_make_ctx(Vector3.ZERO, carrier, -1.0), 1.0)
	assert_almost_eq(d.target_position.z,
			-ATTACKING_BLUE_Z - AIRoleWideLane.LINE_HOLD_BACK_M, 1e-4)
