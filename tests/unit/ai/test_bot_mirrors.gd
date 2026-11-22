extends GutTest

# Constants the bot code copies from somewhere else it cannot read: the
# controller's slapper zone radius, blade speed and pickup radius, the puck's deflect
# threshold and rest height, and the skater's body radius (scene nodes the
# domain must not reach), the duel harness's copy of the puck's catch, and the
# pairs two bot modules keep equal so their reads agree — constants, and the
# reads written twice (the agent's motion fallback against the host's tracker,
# the brain's goalie against the roles'). Each was a "must match" comment;
# this is the check.

const SkaterControllerScript := preload("res://Scripts/controllers/skater_controller.gd")
const PuckScript := preload("res://Scripts/actors/puck.gd")
const SkaterScript := preload("res://Scripts/actors/skater.gd")
const DuelHarness := preload("res://tests/unit/ai/duel_harness.gd")
const AgentScript := preload("res://Scripts/ai/skater_agent_state_machine.gd")


func test_the_bots_forehand_side_is_the_releases() -> void:
	# The reception's one-timer side and the wind-up's perp are both the side the
	# release classifier (WristerLoad, in the skater's frame: forward -Z, right
	# +X) loads a forehand from. Inverted, a bot winds up on the backhand and
	# pays its power for it.
	var forward := Vector3(0.0, 0.0, -1.0)
	var cfg := WristerLoad.Config.new()
	var hand := WristerLoad.Result.new()
	for left_handed: bool in [false, true]:
		var side: Vector3 = SkaterAgentReception.forehand_dir(forward, left_handed)
		WristerLoad.solve(hand, side * 0.9, forward, left_handed, cfg)
		assert_false(hand.is_backhand,
				"left-handed %s: a puck on the reception's forehand side is a forehand" % left_handed)
		WristerLoad.solve(hand, -side * 0.9, forward, left_handed, cfg)
		assert_true(hand.is_backhand, "left-handed %s: and one on the other side is not" % left_handed)
		var agent: SkaterAgentStateMachine = AgentScript.new()
		agent.setup(1, 0, TeamBrain.new(0, {1: 0}), {1: 0}, left_handed)
		assert_eq(Vector3(forward.z, 0.0, -forward.x) * agent._handedness_perp_sign, side,
				"left-handed %s: the wind-up's perp is on that side" % left_handed)


func test_the_two_defensive_leads_agree() -> void:
	# The rush read and the coverage roles lead the same attackers.
	assert_eq(AIRushRead.ANTICIPATION_S, AIRoleReads.DEFENSIVE_ANTICIPATION_S)
	assert_eq(AIRushRead.ANTICIPATION_MAX_M, AIRoleReads.DEFENSIVE_ANTICIPATION_MAX_M)


func test_a_feed_is_led_and_priced_over_one_horizon() -> void:
	assert_eq(AIRoleFinisher.FEED_FLIGHT_MAX_S, AICarrierPassSearch.PASS_LEAD_MAX_S)


func test_the_chase_and_slot_elections_share_their_stickiness() -> void:
	# They race the same bodies over the same ETA model; if their hysteresis
	# disagreed a bot could hold the chase while losing the slot that assumes it.
	assert_eq(AILoosePuckChase.HYSTERESIS_S, AIRoleSlots.HYSTERESIS_PENALTY_S)


func test_the_carry_floor_the_bots_read_is_the_controllers() -> void:
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_almost_eq(AISkaterCaps.LEAGUE_CARRY_REACH_MIN_M, ctrl.carry_reach_min_m, 0.0001)
	assert_almost_eq(AISkaterCaps.LEAGUE_CARRY_REACH_FOLD_M, ctrl.carry_reach_fold_m, 0.0001)
	ctrl.free()


func test_the_one_timer_salvage_sits_inside_the_controllers_zone() -> void:
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_lt(SkaterAgentOneTimer.ONE_TIMER_RELEASE_RADIUS_M, ctrl.slapper_zone_radius,
			"a clean feed attaches before the salvage release can fire")
	ctrl.free()


func test_the_puck_thresholds_the_bots_price() -> void:
	var puck: Puck = PuckScript.new()
	assert_almost_eq(AIRoleFinisher.TIP_MAX_TURN_RAD, deg_to_rad(puck.deflect_max_turn_deg), 0.0001,
			"the finisher aims his tip by the turn a tip has")
	# Every clean bot feed arrives at PASS_TARGET_CLOSING_M_S; only a hotter
	# arrival, still short of a deflection, makes the receiver give with it.
	assert_almost_eq(AIFeedReception.RECEIVE_HOLD_CEILING_M_S,
			sqrt(puck.bobble_load) * (puck.deflect_min_speed + puck.alignment_receive_bonus), 0.0001,
			"a receiver gives from the bobble line with the blade on the feed's line")
	puck.free()


func test_the_settle_a_feed_is_priced_at_is_the_pucks() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AIFeedReception.RECEIVE_DEFLECT_MIN_M_S, puck.deflect_min_speed)
	assert_eq(AIFeedReception.RECEIVE_ALIGNMENT_BONUS_M_S, puck.alignment_receive_bonus)
	assert_eq(AIFeedReception.SETTLE_CLEAN_LOAD, puck.settle_clean_load)
	assert_eq(AIFeedReception.SETTLE_MAX_S, puck.settle_max_s)
	assert_eq(AIFeedReception.BOBBLE_LOAD, puck.bobble_load)
	assert_eq(AIFeedReception.BOBBLE_EDGE_SHARE, puck.bobble_edge_share)
	assert_eq(AIFeedReception.DEFLECT_NORMAL_RESTITUTION, puck.deflect_normal_restitution)
	assert_eq(AIFeedReception.DEFLECT_NORMAL_RESTITUTION_MIN, puck.deflect_normal_restitution_min)
	assert_eq(AIFeedReception.DEFLECT_SPEED_REF_M_S, puck.deflect_speed_ref)
	assert_eq(AIFeedReception.BOBBLE_TANGENTIAL_RETAIN, puck.bobble_tangential_retain)
	assert_eq(AIFeedReception.BOBBLE_PACE_RETAIN, puck.bobble_pace_retain)
	puck.free()


func test_the_harness_catches_as_the_puck_does() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(DuelHarness.PICKUP_MAX_REL_SPEED, puck.pickup_max_speed)
	assert_eq(DuelHarness.DEFLECT_MIN_REL_SPEED, puck.deflect_min_speed)
	assert_eq(DuelHarness.RECEIVE_ALIGNMENT_BONUS, puck.alignment_receive_bonus)
	assert_eq(DuelHarness.BOBBLE_LOAD, puck.bobble_load)
	assert_eq(DuelHarness.BOBBLE_EDGE_SHARE, puck.bobble_edge_share)
	assert_eq(DuelHarness.BOBBLE_GRACE_TICKS, roundi(puck.settle_max_s * Constants.PHYSICS_TICK))
	puck.free()


func test_the_harness_swings_a_one_timer_as_the_controller_does() -> void:
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_eq(DuelHarness.SLAPPER_ZONE_RADIUS_M, ctrl.slapper_zone_radius)
	assert_eq(DuelHarness.ONE_TIMER_LENIENCY_S, ctrl.one_timer_leniency_time)
	assert_eq(DuelHarness.ONE_TIMER_RETENTION_TICKS,
			roundi(ctrl.one_timer_retention_time * Constants.PHYSICS_TICK))
	ctrl.free()


func test_the_harness_deflects_and_hops_as_the_puck_does() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AIFeedReception.DEFLECT_NORMAL_RESTITUTION, puck.deflect_normal_restitution)
	assert_eq(DuelHarness.DEFLECT_TANGENTIAL_RETAIN, puck.deflect_tangential_retain)
	assert_eq(DuelHarness.BOBBLE_SPEED_M_S, puck.bobble_speed_threshold)
	assert_eq(DuelHarness.BOBBLE_COOLDOWN_TICKS,
			roundi(puck.bobble_cooldown * Constants.PHYSICS_TICK))
	assert_eq(DuelHarness.DEFLECT_COOLDOWN_TICKS,
			roundi(puck.deflect_cooldown * Constants.PHYSICS_TICK))
	assert_eq(DuelHarness.BOBBLE_LIFT_THRESHOLD_M_S, puck.bobble_lift_threshold)
	assert_eq(DuelHarness.BOBBLE_LIFT_GAIN, puck.bobble_lift_gain)
	assert_eq(DuelHarness.BOBBLE_LIFT_MAX_M_S, puck.bobble_lift_max_speed)
	assert_eq(DuelHarness.PINCH_LIFT_THRESHOLD_M_S, puck.pinch_lift_threshold)
	assert_eq(DuelHarness.PINCH_LIFT_GAIN, puck.pinch_lift_gain)
	assert_eq(DuelHarness.PINCH_LIFT_MAX_M_S, puck.pinch_lift_max_speed)
	puck.free()


func test_the_harness_contests_a_pickup_as_the_puck_controller_does() -> void:
	var pc: PuckController = PuckController.new()
	assert_eq(DuelHarness.CONTEST_MIN_M_S, pc.contest_min_speed)
	assert_eq(DuelHarness.CONTEST_MAX_M_S, pc.contest_max_speed)
	assert_eq(DuelHarness.CONTEST_DEADLOCK_M_S, pc.contest_deadlock_speed)
	assert_eq(DuelHarness.CONTEST_DEADLOCK_THRESHOLD_M_S, pc.contest_deadlock_threshold)
	pc.free()


func test_the_harness_strips_as_the_puck_does() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(DuelHarness.POKE_STRIP_MIN_M_S, puck.poke_strip_min_speed)
	assert_eq(DuelHarness.POKE_STRIP_MAX_M_S, puck.poke_strip_max_speed)
	assert_eq(DuelHarness.POKE_CARRIER_VEL_BLEND, puck.poke_carrier_vel_blend)
	assert_eq(DuelHarness.STRIP_REATTACH_TICKS,
			roundi(puck.reattach_cooldown * Constants.PHYSICS_TICK))
	assert_eq(DuelHarness.RELEASE_GRACE_TICKS,
			roundi(puck.reattach_cooldown * Constants.PHYSICS_TICK))
	assert_eq(DuelHarness.STRIP_CHECKER_TICKS,
			roundi(puck.poke_checker_cooldown * Constants.PHYSICS_TICK))
	puck.free()


func test_a_lane_reads_the_stick_the_body_holds() -> void:
	assert_eq(AIPuckLane.LANE_BLADE_CATCH_M, PuckController.PICKUP_RADIUS,
			"a pass passing a blade inside the pickup radius is his")
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_eq(AISkaterCaps.LEAGUE_BLADE_SPEED_M_S, ctrl.max_blade_speed,
			"a defender's hands traverse at the league blade speed")
	ctrl.free()


func test_a_grounded_puck_rests_where_the_puck_does() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AITrajectory.PUCK_REST_HEIGHT_M, puck.ice_height,
			"a puck at rest must read as grounded, not airborne")
	# Vector3 holds 32-bit floats.
	assert_almost_eq(AITrajectory.PUCK_REST_HEIGHT_M, GameRules.PUCK_START_POS.y, 1e-7)
	puck.free()


func test_a_strip_connects_at_the_pickup_radius() -> void:
	assert_eq(AICarrySpace.POKE_CONTACT_RADIUS_M, PuckController.PICKUP_RADIUS,
			"the safety maps are measured around the blade's puck-contact radius")
	assert_eq(DuelHarness.PICKUP_RADIUS, PuckController.PICKUP_RADIUS)


func test_a_saucer_clears_the_body_a_skater_has() -> void:
	var skater: Skater = SkaterScript.new()
	assert_eq(AIPuckLane.LANE_DEFENDER_BODY_RADIUS_M, skater.body_collision_radius,
			"over a saucer a defender reaches with his body alone")
	skater.free()


func test_the_wheel_exits_at_the_top_of_the_low_battle_ice() -> void:
	assert_eq(AICarrierDestinations.WHEEL_EXIT_UP_ICE_M, AIZoneCoverage.LOW_ZONE_DEPTH_M)


func _moving(vel: Vector3) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	s.velocity = vel
	return s


func test_a_bot_without_the_hosts_cache_reads_motion_as_the_host_does() -> void:
	# The agent's local fallback and the host's shared tracker over the same
	# frames: a man cutting at 2 rad/s, one snapped by a collision past the
	# clamp, one drifting under the heading floor who leaves and comes back.
	var dt: float = 1.0 / Constants.PHYSICS_TICK
	var tracker := AIAccelerationTracker.new()
	var sm := SkaterAgentStateMachine.new()
	for tick: int in 90:
		var snap := WorldSnapshot.new()
		var a: float = 2.0 * dt * tick
		snap.skater_states[1] = _moving(Vector3(6.0 * cos(a), 0.0, 6.0 * sin(a)))
		snap.skater_states[2] = _moving(Vector3(0.0, 0.0, 30.0 if tick == 20 else 5.0))
		if tick < 40 or tick >= 50:
			snap.skater_states[3] = _moving(Vector3(0.4 * cos(float(tick)), 0.0, 0.4))
		tracker.update(snap.skater_states, dt)
		sm._update_acceleration_cache(snap, dt)
		for pid: int in [1, 2, 3]:
			assert_eq(sm._accel_by_peer.has(pid), tracker.accel_by_peer.has(pid),
					"peer %d tracked alike at tick %d" % [pid, tick])
			if not tracker.accel_by_peer.has(pid):
				continue
			assert_almost_eq(sm._accel_by_peer[pid], tracker.accel_by_peer[pid],
					Vector3.ONE * 1e-5, "peer %d's accel at tick %d" % [pid, tick])
			assert_almost_eq(sm._heading_omega_by_peer[pid], tracker.heading_omega_by_peer[pid],
					1e-5, "peer %d's turn rate at tick %d" % [pid, tick])


func test_the_brain_and_the_roles_find_our_goalie_alike() -> void:
	for team: int in [0, 1]:
		var team_map: Dictionary = {1: team}
		var brain := TeamBrain.new(team, team_map)
		var sm := SkaterAgentStateMachine.new()
		sm.setup(1, team, brain, team_map, false)
		var snap := WorldSnapshot.new()
		snap.skater_states[1] = SkaterNetworkState.new()
		var ctx: RoleContext = sm._build_role_context(snap, Vector3.ZERO, snap.skater_states[1])
		assert_eq(brain._resolve_our_goalie_pos(snap), AIRoleReads.resolve_our_goalie_pos(ctx),
				"team %d with no goalie yet: the goal mouth" % team)
		var goalie := GoalieNetworkState.new()
		goalie.position_x = 0.7
		goalie.position_z = 25.0 if team == 0 else -25.0
		snap.goalie_states[team] = goalie
		assert_eq(brain._resolve_our_goalie_pos(snap), AIRoleReads.resolve_our_goalie_pos(ctx),
				"team %d's goalie where he stands" % team)
