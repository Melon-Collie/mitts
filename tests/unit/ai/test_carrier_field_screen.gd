extends GutTest

# AICarrierField's screen read: who it counts as a body in front of their keeper.
# Team 0 attacks -Z; peer 1 carries.

const NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)


func _ctx(carrier: Vector3, mates: Array[Vector3]) -> RoleContext:
	var snap := WorldSnapshot.new()
	var team: Dictionary = {1: 0}
	var bodies: Array = [[1, carrier]]
	for i: int in mates.size():
		bodies.append([2 + i, mates[i]])
		team[2 + i] = 0
	for e: Array in bodies:
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
	ctx.team_id_by_peer = team
	return ctx


const AT_THE_NET := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z + 3.5)
const ELSEWHERE := Vector3(10.0, 0.0, -GameRules.GOAL_LINE_Z + 20.0)


# A feed from the wall to the slot's top, its receiver standing now at
# `receiver_now`, with `others` of ours on the ice too.
func _feed(receiver_now: Vector3, others: Array[Vector3] = []) -> float:
	var carrier := Vector3(-8.0, 0.0, NET.z + 9.5)
	var mates: Array[Vector3] = [receiver_now]
	mates.append_array(others)
	var ctx: RoleContext = _ctx(carrier, mates)
	var field := AICarrierField.new()
	field.fill(ctx)
	var none: Array[Vector3] = []
	return field.feed_value_at(ctx, carrier, Vector3(0.0, 0.0, NET.z + 9.5), 15.0, true,
			carrier, none, 0.0, Vector3.ZERO, receiver_now)


# The receiver skating out from the net front to the feed stands, now, on the
# line from where he will shoot it: that is no screen on his own shot.
func test_the_receiver_does_not_screen_his_own_feed() -> void:
	assert_almost_eq(_feed(AT_THE_NET), _feed(ELSEWHERE), 1e-6)


# A teammate of his standing there is: the screen and the shot off the feed.
func test_a_teammate_in_front_screens_the_feed() -> void:
	var screener: Array[Vector3] = [AT_THE_NET]
	assert_gt(_feed(ELSEWHERE, screener), _feed(ELSEWHERE))
