extends GutTest

# Constants the bot code copies from somewhere else it cannot read: the
# controller's slapper zone, blade speed and pickup radius and the puck's deflect
# threshold (scene nodes the domain must not reach), the duel harness's copy of
# the puck's catch, and the pairs two bot modules keep equal so their reads
# agree. Each was a "must match" comment; this is the check.

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


func test_the_one_timer_zone_is_the_controllers() -> void:
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_eq(SkaterAgentOneTimer.BOT_ONE_TIMER_ZONE_OFFSET_X_M, ctrl.slapper_zone_offset_x,
			"the settle puts the controller's zone on the feed line")
	assert_eq(SkaterAgentOneTimer.BOT_ONE_TIMER_ZONE_OFFSET_Z_M, ctrl.slapper_zone_offset_z)
	assert_lt(SkaterAgentOneTimer.ONE_TIMER_RELEASE_RADIUS_M, ctrl.slapper_zone_radius,
			"a clean feed attaches before the salvage release can fire")
	ctrl.free()


func test_a_bot_aims_its_cross_check_through_the_controllers_twist() -> void:
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_almost_eq(AIBotMechanics.UPPER_BODY_MAX_TWIST_RAD,
			deg_to_rad(ctrl.upper_body_max_twist_deg), 1e-6)
	ctrl.free()


func test_the_puck_thresholds_the_bots_price() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AIActionScoring.TIP_DEFLECT_MIN_SPEED_M_S, puck.deflect_min_speed,
			"a tip is priced only above the pace a blade deflects at")
	# Every clean bot feed arrives at PASS_TARGET_CLOSING_M_S; only a hotter
	# arrival, still short of a deflection, makes the receiver give with it.
	assert_gt(SkaterAgentReception.RECEIVE_GIVE_CEILING_M_S, AIPuckLane.PASS_TARGET_CLOSING_M_S)
	assert_lt(SkaterAgentReception.RECEIVE_GIVE_CEILING_M_S, puck.deflect_min_speed)
	puck.free()


func test_the_settle_a_feed_is_priced_at_is_the_pucks() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AIPuckLane.RECEIVE_ANY_ANGLE_CEILING_M_S, puck.deflect_min_speed)
	assert_eq(AIPuckLane.SETTLE_CLEAN_LOAD, puck.settle_clean_load)
	assert_eq(AIPuckLane.SETTLE_MAX_S, puck.settle_max_s)
	assert_eq(AIPuckLane.BOBBLE_LOAD, puck.bobble_load)
	assert_eq(AIPuckLane.BOBBLE_EDGE_SHARE, puck.bobble_edge_share)
	puck.free()


func test_the_harness_catches_as_the_puck_does() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(DuelHarness.PICKUP_MAX_REL_SPEED, puck.pickup_max_speed)
	assert_eq(DuelHarness.DEFLECT_MIN_REL_SPEED, puck.deflect_min_speed)
	assert_eq(DuelHarness.RECEIVE_ALIGNMENT_BONUS, puck.alignment_receive_bonus)
	assert_eq(DuelHarness.BOBBLE_LOAD, puck.bobble_load)
	assert_eq(DuelHarness.BOBBLE_EDGE_SHARE, puck.bobble_edge_share)
	assert_eq(DuelHarness.BOBBLE_EXIT_MIN_M_S, puck.bobble_exit_min)
	assert_eq(DuelHarness.BOBBLE_EXIT_MAX_M_S, puck.bobble_exit_max)
	assert_eq(DuelHarness.BOBBLE_GRACE_TICKS, roundi(puck.settle_max_s * Constants.PHYSICS_TICK))
	puck.free()


func test_a_lane_reads_the_stick_the_body_holds() -> void:
	assert_eq(AIPuckLane.LANE_BLADE_CATCH_M, PuckController.PICKUP_RADIUS,
			"a pass passing a blade inside the pickup radius is his")
	var ctrl: SkaterController = SkaterControllerScript.new()
	assert_eq(AISkaterCaps.LEAGUE_BLADE_SPEED_M_S, ctrl.max_blade_speed,
			"a defender's hands traverse at the league blade speed")
	ctrl.free()
