extends GutTest

# Constants the bot code copies from somewhere else it cannot read: the
# controller's slapper zone and the puck's deflect threshold (scene nodes the
# domain must not reach), and the pairs two bot modules keep equal so their
# reads agree. Each was a "must match" comment; this is the check.

const SkaterControllerScript := preload("res://Scripts/controllers/skater_controller.gd")
const PuckScript := preload("res://Scripts/actors/puck.gd")


func test_the_two_defensive_leads_agree() -> void:
	# The rush read and the coverage roles lead the same attackers.
	assert_eq(AIRushRead.ANTICIPATION_S, AIRoleReads.DEFENSIVE_ANTICIPATION_S)
	assert_eq(AIRushRead.ANTICIPATION_MAX_M, AIRoleReads.DEFENSIVE_ANTICIPATION_MAX_M)


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


func test_the_puck_thresholds_the_bots_price() -> void:
	var puck: Puck = PuckScript.new()
	assert_eq(AIActionScoring.TIP_DEFLECT_MIN_SPEED_M_S, puck.deflect_min_speed,
			"a tip is priced only above the pace a blade deflects at")
	# Every clean bot feed arrives at PASS_TARGET_CLOSING_M_S; only a hotter
	# arrival, still short of a deflection, makes the receiver give with it.
	assert_gt(SkaterAgentReception.RECEIVE_GIVE_CEILING_M_S, AIPuckLane.PASS_TARGET_CLOSING_M_S)
	assert_lt(SkaterAgentReception.RECEIVE_GIVE_CEILING_M_S, puck.deflect_min_speed)
	puck.free()
