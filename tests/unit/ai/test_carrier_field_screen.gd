extends GutTest

# AICarrierField's screen read: who it counts as a body in front of their keeper.
# Team 0 attacks -Z; peer 1 carries.

const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)


func _ctx(carrier: Vector3, mate: Vector3) -> RoleContext:
	var snap := WorldSnapshot.new()
	for e: Array in [[1, carrier], [2, mate]]:
		var s := SkaterNetworkState.new()
		s.position = e[1]
		s.facing = Vector2(0.0, -1.0)
		snap.skater_states[e[0]] = s
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 1
	puck.position = carrier
	snap.puck_state = puck
	var g := GoalieNetworkState.new()
	g.position_z = NET.z + 0.6
	snap.goalie_states[1] = g
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = carrier
	ctx.team_id = 0
	ctx.peer_id = 1
	ctx.attacking_goal_pos = NET
	ctx.defending_goal_pos = -NET
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = {1: 0, 2: 0}
	return ctx


func _feed(mate_now: Vector3) -> float:
	var carrier := Vector3(-8.0, 0.0, NET.z + 9.5)
	var ctx: RoleContext = _ctx(carrier, mate_now)
	var field := AICarrierField.new()
	field.fill(ctx)
	var none: Array[Vector3] = []
	return field.feed_value_at(ctx, carrier, Vector3(0.0, 0.0, NET.z + 9.5), 15.0, true,
			carrier, none)


# The receiver skating out from the net front to the feed stands, now, on the
# line from where he will shoot it: that is no screen on his own shot.
func test_the_receiver_does_not_screen_his_own_feed() -> void:
	var at_the_net := Vector3(0.0, 0.0, NET.z + 3.5)
	var elsewhere := Vector3(10.0, 0.0, NET.z + 20.0)
	assert_almost_eq(_feed(at_the_net), _feed(elsewhere), 1e-6)
