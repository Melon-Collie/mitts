extends GutTest

# AIRoleRushLane (WIDE_L / WIDE_R): fill the outside lane a lead ahead of the
# play, held NZ-side of the attacking blue line until the puck crosses it.

const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z   # Team 0 defends +Z, attacks -Z
const ATTACKING_BLUE_Z: float = -GameRules.BLUE_LINE_Z
const LANE_X: float = GameRules.RINK_HALF_WIDTH - AIRoleRushLane.LANE_INSET_M
const EDGE_X: float = LANE_X * 0.5


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
	var d: RoleDecision = AIRoleRushLane.decide(ctx, 1.0)
	assert_eq(d.target_position, self_pos, "no play to fill a lane for")


func test_with_the_carrier_in_the_middle_both_wings_fill() -> void:
	var carrier := Vector3(0, 0, 10)
	var left: RoleDecision = AIRoleRushLane.decide(_make_ctx(Vector3.ZERO, carrier), -1.0)
	var right: RoleDecision = AIRoleRushLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(left.target_position.x, -LANE_X, 1e-4)
	assert_almost_eq(right.target_position.x, LANE_X, 1e-4)
	assert_almost_eq(left.target_position.z, right.target_position.z, 1e-4,
			"the two lanes mirror each other")


func test_the_lane_leads_the_play_up_ice_at_pace() -> void:
	var carrier := Vector3(0, 0, 10)
	var d: RoleDecision = AIRoleRushLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(d.target_position.z, carrier.z - AIRoleRushLane.LEAD_AHEAD_M, 1e-4,
			"a lead ahead of the carrier, toward the net we attack")
	assert_true(d.arrive_at_speed, "the lane advances with the rush")


func test_the_lead_holds_onside_until_the_puck_crosses() -> void:
	# The lead alone would put him past the line while the carrier is outside it.
	var carrier := Vector3(0, 0, ATTACKING_BLUE_Z + 2.0)
	var d: RoleDecision = AIRoleRushLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(d.target_position.z, ATTACKING_BLUE_Z + AIRoleRushLane.LINE_HOLD_BACK_M,
			1e-4, "held a stand-off NZ-side of the attacking blue line")


func test_once_the_puck_is_in_the_lane_leads_into_the_zone() -> void:
	var carrier := Vector3(0, 0, ATTACKING_BLUE_Z - 2.0)
	var d: RoleDecision = AIRoleRushLane.decide(_make_ctx(Vector3.ZERO, carrier), 1.0)
	assert_almost_eq(d.target_position.z, carrier.z - AIRoleRushLane.LEAD_AHEAD_M, 1e-4)


func test_the_hold_mirrors_for_the_team_attacking_plus_z() -> void:
	var carrier := Vector3(0, 0, -ATTACKING_BLUE_Z - 2.0)
	var d: RoleDecision = AIRoleRushLane.decide(_make_ctx(Vector3.ZERO, carrier, -1.0), 1.0)
	assert_almost_eq(d.target_position.z,
			-ATTACKING_BLUE_Z - AIRoleRushLane.LINE_HOLD_BACK_M, 1e-4)


func _lane_target_x(carrier_lane: int, side: float) -> float:
	var ctx: RoleContext = _make_ctx(Vector3.ZERO, Vector3(0, 0, 10))
	ctx.carrier_lane = carrier_lane
	return AIRoleRushLane.decide(ctx, side).target_position.x


func test_with_the_carrier_on_a_wing_the_middle_and_far_wing_fill() -> void:
	assert_almost_eq(_lane_target_x(-1, -1.0), 0.0, 1e-4, "LANE_L drives the middle")
	assert_almost_eq(_lane_target_x(-1, 1.0), LANE_X, 1e-4, "LANE_R takes the far wing")
	assert_almost_eq(_lane_target_x(1, -1.0), -LANE_X, 1e-4, "LANE_L takes the far wing")
	assert_almost_eq(_lane_target_x(1, 1.0), 0.0, 1e-4, "LANE_R drives the middle")


func test_the_two_fillers_never_share_a_lane_or_the_carriers() -> void:
	for carrier: int in [-1, 0, 1]:
		var l: int = AIRoleRushLane.filled_lane(carrier, -1.0)
		var r: int = AIRoleRushLane.filled_lane(carrier, 1.0)
		assert_lt(l, r, "LANE_L is left of LANE_R with the carrier in lane %d" % carrier)
		assert_ne(l, carrier)
		assert_ne(r, carrier)


func test_the_carrier_is_read_in_the_lane_he_skates() -> void:
	assert_eq(AIRoleRushLane.carrier_lane(-LANE_X, 0), -1)
	assert_eq(AIRoleRushLane.carrier_lane(0.0, 1), 0)
	assert_eq(AIRoleRushLane.carrier_lane(LANE_X, -1), 1)


func test_a_carrier_on_a_lane_edge_keeps_his_lane() -> void:
	var just_past: float = EDGE_X + AIRoleRushLane.CARRIER_LANE_HYSTERESIS_M * 0.5
	assert_eq(AIRoleRushLane.carrier_lane(just_past, 0), 0,
			"inside the band he is still in the middle")
	assert_eq(AIRoleRushLane.carrier_lane(EDGE_X - AIRoleRushLane.CARRIER_LANE_HYSTERESIS_M * 0.5, 1),
			1, "and coming back, still on the wing")
	assert_eq(AIRoleRushLane.carrier_lane(EDGE_X + AIRoleRushLane.CARRIER_LANE_HYSTERESIS_M * 1.5, 0),
			1, "clear of the band he has changed lanes")


func test_the_brain_reads_our_carriers_lane_into_the_view() -> void:
	var snap := WorldSnapshot.new()
	var team_map: Dictionary = {}
	for pid: int in [1, 2, 3, 4, 5]:
		var s := SkaterNetworkState.new()
		s.position = Vector3(float(pid) * 2.0 - 6.0, 0.0, 4.0)
		snap.skater_states[pid] = s
		team_map[pid] = TEAM_ID
	snap.skater_states[2].position = Vector3(-LANE_X, 0.0, -2.0)
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 2
	puck.position = snap.skater_states[2].position
	snap.puck_state = puck
	var brain := TeamBrain.new(TEAM_ID, team_map, {}, 5, {1: 0, 2: 1, 3: 2, 4: 3, 5: 4})
	brain.force_retick()
	brain.tick(0.01, snap)
	brain.build_view()
	assert_eq(brain.get_view().carrier_lane(), -1, "the carrier up the −x wall")
