extends GutTest

# AIRoleBreakoutCenter (BREAKOUT_C): the center's low swing, goal-side of the
# carrier in whichever of the mid lane and the carrier's-side circle lane he has
# the cleaner pass to. The lane model itself is test_ai_action_scoring's.

const TEAM_ID: int = 0
const OPP_ID: int = 200
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z   # Team 0 defends +Z, attacks -Z


func _make_ctx(self_pos: Vector3, carrier_pos: Vector3,
		opponents: Array[Vector3] = []) -> RoleContext:
	var snap := WorldSnapshot.new()
	var team_map: Dictionary = {1: TEAM_ID, 100: TEAM_ID}
	var me := SkaterNetworkState.new()
	me.position = self_pos
	snap.skater_states[1] = me
	var carrier := SkaterNetworkState.new()
	carrier.position = carrier_pos
	snap.skater_states[100] = carrier
	for i: int in opponents.size():
		var opp := SkaterNetworkState.new()
		opp.position = opponents[i]
		snap.skater_states[OPP_ID + i] = opp
		team_map[OPP_ID + i] = 1
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 100
	puck.position = carrier_pos
	snap.puck_state = puck

	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.own_goal_dir = 1.0
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.team_id_by_peer = team_map
	return ctx


func _mid_lane(carrier: Vector3) -> Vector3:
	return Vector3(carrier.x * AIRoleBreakoutCenter.MID_LANE_FRACTION, 0.0,
			carrier.z + AIRoleBreakoutCenter.SWING_BELOW_M)


func _circle_lane(carrier: Vector3) -> Vector3:
	return Vector3(signf(carrier.x) * AIRoleBreakoutCenter.CIRCLE_LANE_X_M, 0.0,
			carrier.z + AIRoleBreakoutCenter.SWING_BELOW_M)


# The carrier's feed to `to`, as the station reads it (AIRoleReads.feed_lane).
func _lane(carrier: Vector3, to: Vector3, opponents: Array[Vector3]) -> float:
	var ctx := _make_ctx(Vector3(0, 0, 20), carrier, opponents)
	AIRoleReads.collect_feed_defence(ctx)
	var origin: Vector3 = AIRoleReads.feed_origin(ctx, carrier)
	return AIRoleReads.feed_lane(ctx, origin, to, AIRoleReads.feed_speed(ctx, origin, to))


func test_no_puck_stands_still() -> void:
	var self_pos := Vector3(0, 0, 20)
	var ctx := _make_ctx(self_pos, Vector3(4, 0, 16))
	ctx.snapshot.puck_state = null
	var d: RoleDecision = AIRoleBreakoutCenter.decide(ctx)
	assert_eq(d.target_position, self_pos, "no breakout to swing under")


func test_on_open_ice_he_swings_low_through_the_middle() -> void:
	var carrier := Vector3(4, 0, 16)
	var d: RoleDecision = AIRoleBreakoutCenter.decide(_make_ctx(Vector3(0, 0, 20), carrier))
	assert_almost_eq(d.target_position.distance_to(_mid_lane(carrier)), 0.0, 1e-4,
			"both lanes clean: the middle")
	assert_gt(d.target_position.z, carrier.z, "goal-side of the carrier, under the puck")
	assert_true(d.arrive_at_speed, "the swing paces the retrieval")


func test_a_blocked_middle_sends_him_to_the_circle_lane() -> void:
	var carrier := Vector3(1, 0, 14)
	var mid: Vector3 = _mid_lane(carrier)
	# In the middle lane past a stick of the release: a man on the release
	# kills every feed alike.
	var blocker: Array[Vector3] = [carrier.lerp(mid, 0.85)]
	assert_lt(_lane(carrier, mid, blocker), _lane(carrier, _circle_lane(carrier), blocker),
			"fixture: the defender stands in the middle lane, not the circle lane")
	var d: RoleDecision = AIRoleBreakoutCenter.decide(
			_make_ctx(Vector3(0, 0, 20), carrier, blocker))
	assert_almost_eq(d.target_position.distance_to(_circle_lane(carrier)), 0.0, 1e-4)


func test_the_circle_lane_is_on_the_carriers_side() -> void:
	var carrier := Vector3(-1, 0, 14)
	var mid: Vector3 = _mid_lane(carrier)
	var blocker: Array[Vector3] = [carrier.lerp(mid, 0.85)]
	var d: RoleDecision = AIRoleBreakoutCenter.decide(
			_make_ctx(Vector3(0, 0, 20), carrier, blocker))
	assert_almost_eq(d.target_position.x, -AIRoleBreakoutCenter.CIRCLE_LANE_X_M, 1e-4)


func test_he_never_swings_behind_his_own_goal_line() -> void:
	var carrier := Vector3(4, 0, OUR_NET_Z - 1.0)
	var d: RoleDecision = AIRoleBreakoutCenter.decide(_make_ctx(Vector3(0, 0, 20), carrier))
	assert_almost_eq(d.target_position.z, OUR_NET_Z - AIRoleBreakoutCenter.GOAL_LINE_PAD_M,
			1e-4, "capped a pad in front of the goal line")
