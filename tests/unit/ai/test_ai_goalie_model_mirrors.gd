extends GutTest

# The bots plan against a MODEL of the keeper, not the keeper. When the two
# disagree the bots aim at a net that isn't there — and nothing fails, because
# both halves are individually consistent. Every shot decision in the game is
# quietly wrong and the only symptom is that the bots look bad.
#
# So every number AIGoalieModel holds of him is held here against his own code
# (Scripts/domain/ai/CLAUDE.md, "the skater AI's goalie model is a MIRROR, not
# a second tier"): his read per tier, his push, his rise, the post he holds and
# the depth he takes.

const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)


func after_each() -> void:
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())


# A puck in the rink, in the keeper's net frame (x across, −z out in front).
func _in_net(puck: Vector3) -> Vector2:
	return Vector2(puck.x - GOAL.x, -(puck.z - GOAL.z) * -signf(GOAL.z))


func test_the_bots_read_his_legs_at_every_tier() -> void:
	assert_almost_eq(AIGoalieModel.goalie_leg_delay_s, KeeperShotRead.new().leg_delay_s, 1e-6,
			"unsynced, the bots read the Hard keeper's legs")
	for tier: GoalieSkillProfile in [GoalieSkillProfile.easy(), GoalieSkillProfile.normal(),
			GoalieSkillProfile.hard()]:
		AIGoalieModel.set_goalie_profile(tier)
		assert_almost_eq(AIGoalieModel.goalie_leg_delay_s, tier.reaction_delay_s, 1e-6,
				"the bots' leg read is the tier's, which the keeper reads with")


func test_the_bots_push_him_across_as_his_footwork_does() -> void:
	var skates := KeeperFootwork.new()
	assert_almost_eq(AIGoalieModel.GOALIE_MAX_LATERAL_SPEED_MPS, skates.t_push_speed, 1e-6,
			"his T-push's top speed")
	assert_almost_eq(AIGoalieModel.GOALIE_LATERAL_ACCEL_M_S2, skates.accel, 1e-6,
			"his push's ramp — it decides whether a cross-crease look is reachable")


func test_the_bots_know_how_long_he_takes_to_stand_up() -> void:
	assert_almost_eq(AIGoalieModel.GOALIE_RECOVERY_S, KeeperDrop.new().rise_s, 1e-6,
			"the window the carrier prices a down keeper's stance over is his rise")


func test_the_bots_hold_the_post_where_he_does() -> void:
	# His sharp angle, read by his own brain from a standing start.
	for x: float in [0.5, 1.5, 2.5, 4.0, 6.0, 9.0]:
		for out: float in [0.3, 1.0, 2.0, 3.5, 5.0, 7.0]:
			var puck := Vector3(x, 0.0, GOAL.z + out)
			var brain := KeeperPositioning.new()
			brain.decide(_in_net(puck), Vector2.ZERO, KeeperMotor.new())
			assert_eq(AIGoalieModel.in_post_seal_zone(puck, GOAL),
					brain.zone == KeeperPositioning.Zone.SHARP,
					"the bots' sharp angle is his at (%.1f, %.1f)" % [x, out])


func test_the_bots_put_him_at_his_own_depth_against_a_carrier() -> void:
	# A carrier of theirs coming at the net, centrally enough that no post race
	# or plant takes him: the depth his brain sets his skates at.
	for x: float in [0.0, 0.6]:
		for out: float in [3.5, 5.0, 8.0, 12.0, 20.0, 26.0]:
			for closing: float in [0.0, 3.0, 8.0]:
				var puck := Vector3(x, 0.0, GOAL.z + out)
				var at: Vector2 = _in_net(puck)
				var brain := KeeperPositioning.new()
				var play := KeeperPlayRead.new()
				play.theirs = true
				play.loose = false
				play.carrier_at = at
				brain.play = play
				var motor := KeeperMotor.new()
				brain.decide(at, -at.normalized() * closing, motor)
				assert_almost_eq(AIGoalieModel.keeper_depth(GOAL, puck, closing), -motor.route.spot.y, 1e-3,
						"his depth for a carrier at (%.1f, %.1f) closing at %.0f m/s" % [x, out, closing])


func test_the_bots_measure_his_stance_on_his_gear() -> void:
	var pose := KeeperPose.new()
	KeeperPoses.ready(pose)
	var skel := KeeperSkeleton.new()
	skel.pose(pose)
	assert_almost_eq(AIGoalieModel.standing_pad_reach_m, KeeperGear.post_contact(skel, 1.0).x, 0.02,
			"his ready stance's pads reach out past his centre this far")
