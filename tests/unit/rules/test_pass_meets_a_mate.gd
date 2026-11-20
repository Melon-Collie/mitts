extends GutTest

# A feed meets our own men on its way: the pickup takes whoever's blade the path
# crosses, meant for him or not, so the carrier reads each mate on the lane as
# he reads a defender (AICarrierPassSearch._mate_take, on AILaneReach's arrival
# clock) and prices what a mate takes as that mate's feed, at his reception and
# his worth, never as the receiver's.

const TEAM_ID: int = 0
const PASSER := Vector3(4.0, 0.0, 20.0)       # our D, deep in our zone
const RECEIVER := Vector3(4.0, 0.0, 2.0)      # 18 m straight up the wall
const ON_THE_LANE := Vector3(4.0, 0.0, 11.0)  # standing on it, halfway


# Our D with the puck, his receiver up the wall, and `mates` (peer → [spot,
# ghost]) beside them.
func _ctx(mates: Dictionary) -> RoleContext:
	var snap := WorldSnapshot.new()
	var team_map: Dictionary = {}
	var spots: Dictionary = {1: [PASSER, false], 2: [RECEIVER, false]}
	spots.merge(mates)
	for pid: int in spots:
		var s := SkaterNetworkState.new()
		s.position = spots[pid][0]
		s.is_ghost = spots[pid][1]
		s.facing = Vector2(0.0, -1.0)
		snap.skater_states[pid] = s
		team_map[pid] = TEAM_ID
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 1
	puck.position = PASSER
	snap.puck_state = puck
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = PASSER
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	return ctx


# What our men take of a 20 m/s feed to the receiver on its way.
func _take(mates: Dictionary, saucer: bool = false) -> Vector3:
	var field := AICarrierField.new()
	field.fill(_ctx(mates))
	return AICarrierPassSearch.new(field)._mate_take(PASSER, RECEIVER, 20.0, RECEIVER, saucer)


func test_a_mate_standing_on_the_lane_takes_the_feed() -> void:
	var read: Vector3 = _take({3: [ON_THE_LANE, false]})
	assert_eq(read.x, 1.0, "his body is within a blade of the path: it is his")
	assert_almost_eq(read.y, PASSER.distance_to(ON_THE_LANE), 0.01, "where he stands")
	assert_gt(read.z, 0.0, "and the flight gets there first")


func test_the_receiver_is_not_in_his_own_lane() -> void:
	assert_eq(_take({}).x, 0.0, "the receiver's own stick is where the read ends")


func test_a_mate_clear_of_the_lane_takes_none_of_it() -> void:
	assert_eq(_take({3: [Vector3(-8.0, 0.0, 11.0), false]}).x, 0.0,
			"12 m off the line, he cannot skate to it before the puck passes")


func test_the_nearer_the_lane_the_more_he_takes() -> void:
	var prev: float = 1.0
	for off: float in [0.0, 2.0, 3.0, 4.0, 6.0]:
		var take: float = _take({3: [ON_THE_LANE + Vector3(off, 0.0, 0.0), false]}).x
		assert_true(take <= prev, "%.1f m off the line takes no more than nearer it" % off)
		prev = take


func test_a_mate_who_may_not_touch_it_takes_none() -> void:
	assert_eq(_take({3: [ON_THE_LANE, true]}).x, 0.0, "a ghost is no blade in its way")


func test_every_mate_must_be_passed() -> void:
	var one: float = _take({3: [ON_THE_LANE + Vector3(2.5, 0.0, 0.0), false]}).x
	var two: float = _take({3: [ON_THE_LANE + Vector3(2.5, 0.0, 0.0), false],
			4: [ON_THE_LANE + Vector3(-2.5, 0.0, 4.0), false]}).x
	assert_between(one, 0.0001, 0.9999, "precondition: a man off the line takes some of it")
	assert_gt(two, one, "a second man beside the lane takes more of it")


func test_a_saucer_flies_over_a_mate_and_lands_before_the_receiver() -> void:
	var u0: float = AIPuckLane.saucer_airborne_distance_m(20.0)
	var under := PASSER + Vector3(0.0, 0.0, -u0 * 0.5)
	assert_gt(u0 * 0.5 - AILaneReach.defender_reach(null), 1.0,
			"precondition: he stands well short of where it lands")
	assert_eq(_take({3: [under, false]}).x, 1.0, "flat, the feed runs into him")
	assert_eq(_take({3: [under, false]}, true).x, 0.0, "the flip is over his stick")
	assert_eq(_take({3: [ON_THE_LANE, false]}, true).x, 1.0, "landed, it is his again")


# Each teammate's feed as the search prices it, peer → [its EV, his spot's worth].
func _feed(mates: Dictionary) -> Dictionary:
	var c := AIRoleCarrier.new()
	c._pass.trace = AICarrierPassTrace.new()
	c.decide(_ctx(mates))
	var out: Dictionary = {}
	var trace: AICarrierPassTrace = c._pass.trace
	for i: int in trace.peer.size():
		out[trace.peer[i]] = [trace.ev[i], trace.worth[i]]
	return out


func test_a_feed_through_a_mate_is_priced_at_his_worth_not_the_receivers() -> void:
	var clear: Dictionary = _feed({3: [Vector3(-8.0, 0.0, 11.0), false]})
	var through: Dictionary = _feed({3: [ON_THE_LANE, false]})
	assert_gt(clear[2][1], through[3][1],
			"precondition: up the wall is worth more than halfway there")
	assert_gt(clear[2][0], 0.0, "precondition: the clear feed is on")
	assert_lt(through[2][0], clear[2][0],
			"the feed he takes on the way is his, at what his spot is worth")
	assert_gt(through[2][0], 0.0, "and it is still ours: not a turnover")
