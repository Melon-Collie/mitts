extends GutTest

# GoalieSkillProfile is a pure deterministic value bundle (sibling of
# BotSkillProfile). Tests pin the tier factories, the difficulty dispatch +
# fallback, and the ladder: strictly monotonic (Easy softer than Normal softer
# than Hard) on every axis — laggier reads, slower arms, a slower drop.


func test_for_difficulty_dispatches_to_tiers() -> void:
	var easy: GoalieSkillProfile = GoalieSkillProfile.for_difficulty(GoalieSkillProfile.Difficulty.EASY)
	var normal: GoalieSkillProfile = GoalieSkillProfile.for_difficulty(GoalieSkillProfile.Difficulty.NORMAL)
	var hard: GoalieSkillProfile = GoalieSkillProfile.for_difficulty(GoalieSkillProfile.Difficulty.HARD)
	assert_eq(easy.arm_reaction_delay_s, GoalieSkillProfile.easy().arm_reaction_delay_s)
	assert_eq(normal.arm_reaction_delay_s, GoalieSkillProfile.normal().arm_reaction_delay_s)
	assert_eq(hard.arm_reaction_delay_s, GoalieSkillProfile.hard().arm_reaction_delay_s)


func test_unknown_difficulty_falls_back_to_hard() -> void:
	# Out-of-range index (stale pref / removed tier) must not crash — falls back
	# to the Hard ceiling.
	var profile: GoalieSkillProfile = GoalieSkillProfile.for_difficulty(99)
	assert_eq(profile.reaction_delay_s, GoalieSkillProfile.hard().reaction_delay_s)


func test_hard_reads_with_the_league_default_legs() -> void:
	assert_eq(GoalieSkillProfile.hard().reaction_delay_s, GameRules.DEFAULT_GOALIE_REACTION_DELAY_S)


func test_normal_is_strictly_softer_than_hard_on_every_axis() -> void:
	_assert_strictly_softer(GoalieSkillProfile.normal(), GoalieSkillProfile.hard(), "Normal", "Hard")


func test_easy_is_strictly_softer_than_normal_on_every_axis() -> void:
	_assert_strictly_softer(GoalieSkillProfile.easy(), GoalieSkillProfile.normal(), "Easy", "Normal")


# Shared monotonicity check: `softer` must be weaker than `tougher` on every axis,
# in the correct direction for each knob.
func _assert_strictly_softer(softer: GoalieSkillProfile, tougher: GoalieSkillProfile,
		soft_name: String, tough_name: String) -> void:
	# Higher = laggier = softer.
	assert_gt(softer.reaction_delay_s, tougher.reaction_delay_s,
			"%s's leg read starts later than %s's" % [soft_name, tough_name])
	assert_gt(softer.prearmed_reaction_delay_s, tougher.prearmed_reaction_delay_s,
			"%s's primed read is slower than %s's" % [soft_name, tough_name])
	assert_gt(softer.butterfly_drop_s, tougher.butterfly_drop_s,
			"%s's pads take longer to seal the ice than %s's" % [soft_name, tough_name])
	assert_gt(softer.arm_reaction_delay_s, tougher.arm_reaction_delay_s,
			"%s's arms start later than %s's" % [soft_name, tough_name])
	# Lower = weaker = softer.
	assert_lt(softer.glove_react_max_speed_mps, tougher.glove_react_max_speed_mps,
			"%s's glove reaches slower than %s's" % [soft_name, tough_name])
	assert_lt(softer.blocker_react_max_speed_mps, tougher.blocker_react_max_speed_mps,
			"%s's blocker reaches slower than %s's" % [soft_name, tough_name])


func test_set_goalie_profile_syncs_the_bots_model() -> void:
	# The bots predict the keeper's legs: the mirror must track the tier, or they
	# plan every shot against a Hard keeper. Restore Hard afterwards: the model
	# is static and other tests assume the baseline.
	var easy: GoalieSkillProfile = GoalieSkillProfile.easy()
	AIGoalieModel.set_goalie_profile(easy)
	assert_eq(AIGoalieModel.goalie_leg_delay_s, easy.reaction_delay_s)
	AIGoalieModel.set_goalie_profile(GoalieSkillProfile.hard())
	assert_eq(AIGoalieModel.goalie_leg_delay_s, GameRules.DEFAULT_GOALIE_REACTION_DELAY_S)


func test_all_values_stay_physical() -> void:
	for profile: GoalieSkillProfile in [GoalieSkillProfile.easy(), GoalieSkillProfile.normal(), GoalieSkillProfile.hard()]:
		assert_gt(profile.arm_reaction_delay_s, 0.0)
		assert_gt(profile.glove_react_max_speed_mps, 0.0)
		assert_gt(profile.blocker_react_max_speed_mps, 0.0)
		assert_gt(profile.reaction_delay_s, 0.0)
		assert_gt(profile.prearmed_reaction_delay_s, 0.0)
		assert_gt(profile.butterfly_drop_s, 0.0)
		# The primed read must stay a genuine shortcut below the cold read, and
		# the reflexive legs must never be slower than the arms — on every tier,
		# not just the defaults.
		assert_lt(profile.prearmed_reaction_delay_s, profile.reaction_delay_s,
				"a primed read beats a cold read on every tier")
		assert_true(profile.reaction_delay_s <= profile.arm_reaction_delay_s,
				"arms never beat the reflexive legs on any tier")
