extends GutTest

# AIRoleNeutralZone — the set neutral-zone shape's high "1", middle "1" and weak
# back lane. Team 0 defends +Z; peer 1 is the bot under test, peer 10 the
# opposing carrier.

const TEAM_ID: int = 0
const OUR_NET_Z: float = GameRules.GOAL_LINE_Z


func _ctx(self_pos: Vector3, skaters: Array, carrier_pid: int) -> RoleContext:
	var snap := WorldSnapshot.new()
	var s := SkaterNetworkState.new()
	s.position = self_pos
	snap.skater_states[1] = s
	var team_map: Dictionary = {1: TEAM_ID}
	for e: Array in skaters:
		var sk := SkaterNetworkState.new()
		sk.position = e[2]
		sk.velocity = e[3] if e.size() > 3 else Vector3.ZERO
		snap.skater_states[e[0]] = sk
		team_map[e[0]] = e[1]
	var puck := PuckNetworkState.new()
	puck.carrier_peer_id = carrier_pid
	puck.position = snap.skater_states[carrier_pid].position
	snap.puck_state = puck
	var ctx := RoleContext.new()
	ctx.snapshot = snap
	ctx.self_pos = self_pos
	ctx.team_id = TEAM_ID
	ctx.peer_id = 1
	ctx.attacking_goal_pos = Vector3(0.0, 0.0, -OUR_NET_Z)
	ctx.defending_goal_pos = Vector3(0.0, 0.0, OUR_NET_Z)
	ctx.own_goal_dir = 1.0
	ctx.team_id_by_peer = team_map
	ctx.team_size = 5
	ctx.strong_x = 1.0
	var read := AIRushRead.new()
	read.fill(snap, TEAM_ID, OUR_NET_Z, team_map, {}, {})
	ctx.rush_read = read
	return ctx


func _depth(p: Vector3) -> float:
	return OUR_NET_Z - p.z


# ── NZ_F1 ────────────────────────────────────────────────────────────────────

func test_f1_steers_from_in_front_of_a_carrier_in_their_half() -> void:
	var carrier := Vector3(4.0, 0.0, -14.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, -6.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 3.0)]], 10)
	var d: RoleDecision = AIRoleNeutralZone.decide(ctx, AIRoleSlots.Slot.NZ_F1)
	assert_gt(d.target_position.z, carrier.z, "he stands goal-side of him")
	assert_lt(d.target_position.x, carrier.x, "angled to the inside, giving him the wall")
	assert_true(d.has_aim_override, "stick on the puck")


func test_f1_does_not_dive_into_a_forecheck_we_declined() -> void:
	# Carrier behind his own net: F1 waits at their circle tops, not on him.
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, -12.0),
			[[10, 1, Vector3(0.0, 0.0, -28.0)]], 10)
	var d: RoleDecision = AIRoleNeutralZone.decide(ctx, AIRoleSlots.Slot.NZ_F1)
	var their_depth: float = OUR_NET_Z + d.target_position.z
	assert_almost_eq(their_depth, AIZoneCoverage.HOUSE_TOP_DEPTH_M, 0.05,
			"held at their circle tops; got %s" % d.target_position)


func test_f1_runs_him_down_once_he_is_past() -> void:
	var carrier := Vector3(0.0, 0.0, -4.0)
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, -10.0),
			[[10, 1, carrier, Vector3(0.0, 0.0, 7.0)]], 10)
	var d: RoleDecision = AIRoleNeutralZone.decide(ctx, AIRoleSlots.Slot.NZ_F1)
	assert_almost_eq(d.target_position.distance_to(carrier),
			AIRoleTrack.HIP_GOAL_SIDE_M, 0.1, "the backcheck's hip")


# ── NZ_MID ───────────────────────────────────────────────────────────────────

func test_mid_holds_the_middle_up_the_ice_from_our_line() -> void:
	var ctx: RoleContext = _ctx(Vector3(0.0, 0.0, 2.0),
			[[10, 1, Vector3(8.0, 0.0, -20.0)]], 10)
	var d: RoleDecision = AIRoleNeutralZone.decide(ctx, AIRoleSlots.Slot.NZ_MID)
	assert_lte(absf(d.target_position.x), AIRoleNeutralZone.NZ_MID_HALF_WIDTH_M + 0.01,
			"in the middle lane; got %s" % d.target_position)
	assert_gte(_depth(d.target_position),
			AIRoleNeutralZone.line_depth_m() + AIRoleNeutralZone.NZ_MID_LAYER_M - 0.01,
			"a layer up from our line, not on it; got %s" % d.target_position)


func test_mid_comes_back_through_the_middle_once_he_is_past() -> void:
	var ctx: RoleContext = _ctx(Vector3(-6.0, 0.0, -8.0),
			[[10, 1, Vector3(0.0, 0.0, 2.0), Vector3(0.0, 0.0, 7.0)]], 10)
	var d: RoleDecision = AIRoleNeutralZone.decide(ctx, AIRoleSlots.Slot.NZ_MID)
	assert_true(d.arrive_at_speed, "a recovery, at pace")
	assert_lt(absf(d.target_position.x), 2.0, "through the middle; got %s" % d.target_position)


# ── BACK_WEAK ────────────────────────────────────────────────────────────────

func test_back_weak_holds_the_weak_lane_on_our_line() -> void:
	var ctx: RoleContext = _ctx(Vector3(-5.0, 0.0, 8.0),
			[[10, 1, Vector3(6.0, 0.0, -12.0)]], 10)
	var d: RoleDecision = AIRoleNeutralZone.decide(ctx, AIRoleSlots.Slot.BACK_WEAK)
	assert_almost_eq(_depth(d.target_position), AIRoleNeutralZone.line_depth_m(), 0.05,
			"on our line; got %s" % d.target_position)
	assert_lt(d.target_position.x, 0.0, "on the weak side; got %s" % d.target_position)


func test_the_back_line_sags_only_as_far_as_the_house_gate() -> void:
	var ctx: RoleContext = _ctx(Vector3(-5.0, 0.0, 14.0),
			[[10, 1, Vector3(6.0, 0.0, 20.0), Vector3(0.0, 0.0, 3.0)]], 10)
	var ap: AICarrierApproach = AICarrierApproach.new()
	AIDefensiveVerbs.read_carrier_approach(ctx, ap)
	assert_almost_eq(AIRoleNeutralZone.back_line_depth_m(ctx, ap),
			AIZoneCoverage.HOUSE_TOP_DEPTH_M, 0.01, "never deeper than the circle tops")


func test_back_weak_picks_up_a_man_arriving_in_his_lane() -> void:
	var man := Vector3(-7.0, 0.0, 12.5)
	var ctx: RoleContext = _ctx(Vector3(-5.0, 0.0, 12.0), [
		[10, 1, Vector3(6.0, 0.0, 6.0), Vector3(0.0, 0.0, 6.0)],
		[11, 1, man, Vector3(0.0, 0.0, 6.0)],
	], 10)
	var d: RoleDecision = AIRoleNeutralZone.decide(ctx, AIRoleSlots.Slot.BACK_WEAK)
	assert_lt(d.target_position.distance_to(man), 4.0,
			"covers the man in his lane; got %s" % d.target_position)
	assert_gt(d.target_position.z, man.z, "goal-side of him")
