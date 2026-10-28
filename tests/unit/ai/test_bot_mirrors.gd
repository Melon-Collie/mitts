extends GutTest

# Constants the bot code copies from somewhere else it cannot read: the
# controller's slapper zone radius, blade speed and pickup radius, the puck's deflect
# threshold and rest height, and the skater's body radius (scene nodes the
# domain must not reach), the duel harness's copy of the puck's catch, and the
# pairs two bot modules keep equal so their reads agree. Each was a "must
# match" comment; this is the check.

const SkaterControllerScript := preload("res://Scripts/controllers/skater_controller.gd")
const PuckScript := preload("res://Scripts/actors/puck.gd")
const DuelHarness := preload("res://tests/unit/ai/duel_harness.gd")


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


func test_the_one_timer_salvage_sits_inside_the_controllers_zone() -> void:
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_lt(SkaterAgentOneTimer.ONE_TIMER_RELEASE_RADIUS_M, ctrl.slapper_zone_radius,
			"a clean feed attaches before the salvage release can fire")
	ctrl.free()


func test_the_puck_thresholds_the_bots_price() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AIActionScoring.TIP_DEFLECT_MIN_SPEED_M_S, puck.deflect_min_speed,
			"a tip is priced only above the pace a blade deflects at")
	# Every clean bot feed arrives at PASS_TARGET_CLOSING_M_S; only a hotter
	# arrival, still short of a deflection, makes the receiver give with it.
	assert_almost_eq(SkaterAgentReception.RECEIVE_GIVE_CEILING_M_S,
			sqrt(puck.bobble_load) * puck.deflect_min_speed, 0.05,
			"a receiver gives from the bobble line at the blade's middle")
	puck.free()


func test_the_settle_a_feed_is_priced_at_is_the_pucks() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AIFeedReception.RECEIVE_ANY_ANGLE_CEILING_M_S, puck.deflect_min_speed)
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


func test_no_saucer_flies_into_a_torso() -> void:
	# The saucer lane reads nothing touching a flying saucer: the hardest LOW
	# release the strongest shooter fires peaks under the hips, where a standing
	# skater's body block starts.
	var skater := (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	add_child_autofree(skater)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	var hardest: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S \
			* PlayerAttributes.new(PlayerAttributes.HEIGHT_MAX).shot_power_mult()
	var vy: float = AIPuckLane.saucer_launch_vy(hardest)
	var peak: float = GameRules.PUCK_LOFT_SEAT_M + vy * vy / (2.0 * GameRules.GRAVITY_M_S2)
	assert_lt(peak, skater.get_body_block_y_range().x,
			"a %.1f m/s saucer peaks at %.2f m" % [hardest, peak])


func test_the_wheel_exits_at_the_top_of_the_low_battle_ice() -> void:
	assert_eq(AICarrierDestinations.WHEEL_EXIT_UP_ICE_M, AIZoneCoverage.LOW_ZONE_DEPTH_M)
