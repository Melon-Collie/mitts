extends GutTest

# AIBackLineRunners — the pace a back-line D keeps for the men still at speed
# beside the carrier he is playing. Team 0 defends +Z; peer 1 is the D under
# test, peer 10 the carrier (slowed at centre), peers 11 and 12 wingers. A rush
# at us travels in +Z.

const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z
const NET := Vector3(0.0, 0.0, OUR_NET_Z)
const SELF_POS := Vector3(0.0, 0.0, 5.0)
const CARRIER := [10, 1, Vector3(3.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)]
# A winger on the left wall, 4 m up-ice of the D, at 8.5 m/s down it.
const LEFT_RUNNER := [11, 1, Vector3(-8.0, 0.0, 1.0), Vector3(0.0, 0.0, 8.5)]
const RIGHT_RUNNER := [12, 1, Vector3(8.0, 0.0, 1.0), Vector3(0.0, 0.0, 8.5)]


# `skaters`: [peer, team, position, velocity] rows.
func _ctx(skaters: Array, self_vel: Vector3 = Vector3.ZERO,
		self_pos: Vector3 = SELF_POS) -> RoleContext:
	var snap := WorldSnapshot.new()
	var me := SkaterNetworkState.new()
	me.position = self_pos
	me.velocity = self_vel
	snap.skater_states[1] = me
	var team_map: Dictionary = {1: TEAM_ID}
	for e: Array in skaters:
		var sk := SkaterNetworkState.new()
		sk.position = e[2]
		sk.velocity = e[3]
		snap.skater_states[e[0]] = sk
		team_map[e[0]] = e[1]
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 10
	puck.position = CARRIER[2]
	snap.puck_state = puck
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.self_velocity = self_vel
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = NET
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	ctx.team_size = 5
	var read := AIRushRead.new()
	read.fill(snap, TEAM_ID, OUR_NET_Z, team_map, {}, {})
	ctx.rush_read = read
	return ctx


func _pace(ctx: RoleContext, ride: Vector3 = Vector3.ZERO) -> float:
	return AIBackLineRunners.floor_pace(ctx, ride,
			AIRoleReads.xz_distance(ctx.self_pos, NET), AIRoleRushD.retreat_max_speed(ctx, true))


func test_a_winger_at_speed_nobody_holds_sets_the_pace_of_a_standing_d() -> void:
	var ctx: RoleContext = _ctx([CARRIER, LEFT_RUNNER])
	assert_true(ctx.rush_read.attackers.has(11), "fixture: the winger is on the rush")
	var pace: float = _pace(ctx)
	assert_gt(pace, AIRoleRushD.GAP_UP_CLOSING_M_S, "he keeps a runner's pace")
	assert_lte(pace, AIRoleRushD.retreat_max_speed(ctx, true), "never more than he can skate")


func test_the_carrier_alone_asks_nothing() -> void:
	var fast_carrier: Array = [10, 1, Vector3(3.0, 0.0, 0.0), Vector3(0.0, 0.0, 8.5)]
	assert_eq(_pace(_ctx([fast_carrier])), 0.0,
			"the carrier's own pace is the ladder's, not this read's")


func test_a_winger_who_is_not_coming_asks_nothing() -> void:
	var drifting: Array = [11, 1, Vector3(-8.0, 0.0, 1.0), Vector3(2.5, 0.0, 1.0)]
	assert_eq(_pace(_ctx([CARRIER, drifting])), 0.0)


func test_a_runner_a_teammate_is_goal_side_of_asks_nothing() -> void:
	var partner: Array = [2, TEAM_ID, Vector3(-6.0, 0.0, 9.0), Vector3(0.0, 0.0, 5.0)]
	assert_eq(_pace(_ctx([CARRIER, LEFT_RUNNER, partner])), 0.0, "the partner has him")


func test_one_teammate_holds_one_runner() -> void:
	var partner: Array = [2, TEAM_ID, Vector3(-6.0, 0.0, 9.0), Vector3(0.0, 0.0, 5.0)]
	assert_gt(_pace(_ctx([CARRIER, LEFT_RUNNER, RIGHT_RUNNER, partner])), 0.0,
			"the far winger is still nobody's")


func test_a_teammate_the_runner_has_already_beaten_does_not_hold_him() -> void:
	# Level with the winger and standing: on the race clock he is behind him.
	var beaten: Array = [2, TEAM_ID, Vector3(-6.0, 0.0, 1.5), Vector3.ZERO]
	assert_gt(_pace(_ctx([CARRIER, LEFT_RUNNER, beaten])), 0.0)


func test_a_d_already_riding_back_with_depth_in_hand_is_not_bound() -> void:
	var riding := Vector3(0.0, 0.0, 8.0)
	var deep := Vector3(0.0, 0.0, 12.0)
	assert_eq(_pace(_ctx([CARRIER, LEFT_RUNNER], riding, deep), riding), 0.0,
			"at his pace and 11 m goal-side, the runner gains nothing on him")


func test_the_pace_he_would_settle_to_is_what_is_priced() -> void:
	# Retreating at pace now, 6 m goal-side of the runner: bound only when his
	# route would brake him to a stop for the slowed carrier.
	var retreating := Vector3(0.0, 0.0, 7.5)
	var at := Vector3(0.0, 0.0, 7.0)
	var ctx: RoleContext = _ctx([CARRIER, LEFT_RUNNER], retreating, at)
	assert_eq(_pace(ctx, retreating), 0.0, "riding on at his pace, nothing binds")
	assert_gt(_pace(ctx, Vector3.ZERO), 0.0, "settling to a stand for the carrier, he is beaten")


func test_hold_depth_bounds_the_route_and_leaves_the_stand() -> void:
	var ctx: RoleContext = _ctx([CARRIER, LEFT_RUNNER])
	var d := RoleDecision.new()
	d.target_position = Vector3(2.0, 0.0, 3.0)
	d.target_velocity = Vector3(0.0, 0.0, 1.0)
	AIBackLineRunners.hold_depth(ctx, d)
	assert_eq(d.target_position, Vector3(2.0, 0.0, 3.0), "the stand keeps its place")
	assert_eq(d.target_velocity, Vector3(0.0, 0.0, 1.0), "and its ride")
	assert_almost_eq(d.advance_cap_m_s, -_pace(ctx, Vector3(0.0, 0.0, 1.0)), 0.001,
			"the route commands at least the runner's pace toward our net")
	assert_eq(d.retreat_floor_center, NET)
	assert_eq(d.retreat_floor_radius_m, AIZoneCoverage.HOUSE_TOP_DEPTH_M,
			"down to the house gate and no further")


func test_hold_depth_keeps_a_floor_and_a_harder_retreat_the_route_already_has() -> void:
	var ctx: RoleContext = _ctx([CARRIER, LEFT_RUNNER])
	var d := RoleDecision.new()
	d.target_velocity = Vector3(0.0, 0.0, 1.0)
	d.retreat_floor_center = NET
	d.retreat_floor_radius_m = AIRoleRushD.RETREAT_FINISH_M
	d.advance_cap_m_s = -50.0
	AIBackLineRunners.hold_depth(ctx, d)
	assert_eq(d.retreat_floor_radius_m, AIRoleRushD.RETREAT_FINISH_M)
	assert_eq(d.advance_cap_m_s, -50.0)


func test_a_stand_with_no_ride_rides_back_at_the_runners_pace() -> void:
	var ctx: RoleContext = _ctx([CARRIER, LEFT_RUNNER])
	var d := RoleDecision.new()
	d.target_position = Vector3(2.0, 0.0, 3.0)
	AIBackLineRunners.hold_depth(ctx, d)
	assert_almost_eq(d.target_velocity.length(), _pace(ctx), 0.001)
	assert_gt(d.target_velocity.dot(NET - SELF_POS), 0.0, "toward our net")


func test_nothing_binds_inside_the_house_gate() -> void:
	var in_house := Vector3(0.0, 0.0, OUR_NET_Z - AIZoneCoverage.HOUSE_TOP_DEPTH_M + 1.0)
	var close_runner: Array = [11, 1, in_house + Vector3(-6.0, 0.0, -4.0), Vector3(0.0, 0.0, 8.5)]
	var ctx: RoleContext = _ctx([CARRIER, close_runner], Vector3.ZERO, in_house)
	var d := RoleDecision.new()
	AIBackLineRunners.hold_depth(ctx, d)
	assert_eq(d.advance_cap_m_s, INF)
	assert_eq(d.target_velocity, Vector3.ZERO)


func test_no_runner_leaves_the_decision_alone() -> void:
	var d := RoleDecision.new()
	AIBackLineRunners.hold_depth(_ctx([CARRIER]), d)
	assert_eq(d.advance_cap_m_s, INF)
	assert_eq(d.retreat_floor_radius_m, 0.0)
