extends GutTest

# AICarrierDumpSearch — the dump-in priced as the race for where it is played.
# Team 0 attacks -Z; their zone is z < -BLUE_LINE_Z. Peer 1 carries.

const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z


# skaters: [peer, team, position, velocity?]
func _ctx(self_pos: Vector3, self_vel: Vector3, skaters: Array) -> RoleContext:
	var snap := WorldSnapshot.new()
	var team_map: Dictionary = {1: TEAM_ID}
	var me := SkaterNetworkState.new()
	me.position = self_pos
	me.velocity = self_vel
	me.facing = Vector2(0.0, -1.0)
	snap.skater_states[1] = me
	for e: Array in skaters:
		var s := SkaterNetworkState.new()
		s.position = e[2]
		s.velocity = e[3] if e.size() > 3 else Vector3.ZERO
		s.facing = Vector2(0.0, -1.0)
		snap.skater_states[e[0]] = s
		team_map[e[0]] = e[1]
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = 1
	puck.position = self_pos
	snap.puck_state = puck
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.self_velocity = self_vel
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	return ctx


func _best(ctx: RoleContext) -> float:
	var field := AICarrierField.new()
	field.fill(ctx)
	field.fill_receivers(ctx, ctx.self_pos)
	var dump := AICarrierDumpSearch.new(field)
	dump.search(ctx)
	return dump.best_score


# Carrying up the middle at their line with a winger driving the far lane; their
# D at `d_z` (their pair, inside the dots), their forwards behind the play.
func _rush(d_z: float) -> RoleContext:
	return _ctx(Vector3(0.0, 0.0, -4.0), Vector3(0.0, 0.0, -6.0), [
		[2, TEAM_ID, Vector3(9.0, 0.0, -4.0), Vector3(0.0, 0.0, -8.0)],
		[10, 1, Vector3(-3.0, 0.0, d_z)],
		[11, 1, Vector3(3.0, 0.0, d_z)],
		[12, 1, Vector3(-2.0, 0.0, 6.0), Vector3(0.0, 0.0, -6.0)],
	])


func test_a_dump_our_winger_wins_is_worth_something() -> void:
	# Their D stood up at their line, our winger flying wide: he gets to the
	# corner first.
	assert_gt(_best(_rush(-9.0)), 0.0, "a corner we win is ours to play")


func test_a_dump_into_their_d_is_worth_less() -> void:
	# The same dump with their D already back by the corners: they win the race.
	assert_gt(_best(_rush(-9.0)), _best(_rush(-24.0)),
			"the race to the spot decides what the dump is worth")


func test_no_dump_from_their_zone_or_ours() -> void:
	var inside: RoleContext = _ctx(Vector3(0.0, 0.0, -12.0), Vector3.ZERO,
			[[10, 1, Vector3(0.0, 0.0, -20.0)]])
	assert_eq(_best(inside), -INF, "in their zone it is a carry or a pass")
	var home: RoleContext = _ctx(Vector3(0.0, 0.0, 14.0), Vector3.ZERO,
			[[10, 1, Vector3(0.0, 0.0, -20.0)]])
	assert_eq(_best(home), -INF, "from our zone it would be a clear, which is not one")


func test_no_dump_with_a_teammate_owing_a_tag_up() -> void:
	var ctx: RoleContext = _rush(-9.0)
	ctx.zone_entry_blocked = true
	assert_eq(_best(ctx), -INF)


func test_an_iced_dump_their_side_wins_is_a_loss() -> void:
	# From our half, with their man nearer the end-zone dots than ours: under NHL
	# rules a dump that reaches their goal line untouched is an icing.
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, -6.0), [
		[2, TEAM_ID, Vector3(9.0, 0.0, -2.0), Vector3(0.0, 0.0, -8.0)],
		[10, 1, Vector3(-4.0, 0.0, -14.0)],
		[11, 1, Vector3(4.0, 0.0, -14.0)],
	])
	var free: float = _best(ctx)
	assert_gt(free, -INF, "without icing there is a dump to make")
	ctx.icing_enforced = true
	assert_lt(_best(ctx), free, "icing costs a dump that crosses untouched")


func test_the_launch_scratch_holds_every_launch() -> void:
	assert_eq(AICarrierDumpSearch._MAX_LAUNCHES,
			AICarrierDumpSearch.AIM_POINTS.size() * AICarrierDumpSearch.PACE_FRACS.size())


# Three across their line a stride in front of a carrier at speed, a winger
# flying wide and a trailer: `with_support` false leaves the carrier alone.
func _stand_up_line(with_support: bool) -> RoleContext:
	var skaters: Array = [
		[10, 1, Vector3(-4.0, 0.0, -7.0), Vector3(0.0, 0.0, -2.0)],
		[11, 1, Vector3(0.5, 0.0, -6.5), Vector3(0.0, 0.0, -2.0)],
		[12, 1, Vector3(5.0, 0.0, -7.0), Vector3(0.0, 0.0, -2.0)],
	]
	if with_support:
		skaters.append([2, TEAM_ID, Vector3(9.5, 0.0, -2.0), Vector3(0.0, 0.0, -8.5)])
		skaters.append([3, TEAM_ID, Vector3(-6.0, 0.0, 2.0), Vector3(0.0, 0.0, -7.0)])
	return _ctx(Vector3(0.0, 0.0, -3.5), Vector3(0.0, 0.0, -7.0), skaters)


func test_a_won_dump_is_worth_the_support_that_arrives_with_it() -> void:
	# Behind their goal line one man has no shot; what the puck won there is worth
	# is the feed to the men coming in behind it.
	assert_gt(_best(_stand_up_line(true)), _best(_stand_up_line(false)))


func test_against_a_stand_up_line_the_carrier_dumps_it_in() -> void:
	var ctx: RoleContext = _stand_up_line(true)
	var c := AIRoleCarrier.new()
	c.decide(ctx)
	assert_eq(c.intended_action, AIRoleCarrier.INTENT_DUMP, "walled off at the line, he dumps it")
	assert_eq(c.pass_target_peer_id, -1, "to the ice, not to a receiver")
	assert_true(c.dump_target.is_finite())
