extends GutTest

# PhaseRules — pure static functions classifying game phases. Dead-puck phases
# are ones where player movement should be frozen (score pause, faceoff prep).

func test_playing_is_not_dead_puck() -> void:
	assert_false(PhaseRules.is_dead_puck_phase(GamePhase.Phase.PLAYING))

func test_faceoff_is_not_dead_puck() -> void:
	assert_false(PhaseRules.is_dead_puck_phase(GamePhase.Phase.FACEOFF))

func test_goal_scored_is_dead_puck() -> void:
	assert_true(PhaseRules.is_dead_puck_phase(GamePhase.Phase.GOAL_SCORED))

func test_faceoff_prep_is_dead_puck() -> void:
	assert_true(PhaseRules.is_dead_puck_phase(GamePhase.Phase.FACEOFF_PREP))

func test_end_of_period_is_dead_puck() -> void:
	assert_true(PhaseRules.is_dead_puck_phase(GamePhase.Phase.END_OF_PERIOD))

func test_game_over_is_dead_puck() -> void:
	assert_true(PhaseRules.is_dead_puck_phase(GamePhase.Phase.GAME_OVER))

func test_movement_locked_matches_dead_puck() -> void:
	for phase in [
		GamePhase.Phase.PLAYING,
		GamePhase.Phase.GOAL_SCORED,
		GamePhase.Phase.FACEOFF_PREP,
		GamePhase.Phase.FACEOFF,
		GamePhase.Phase.END_OF_PERIOD,
		GamePhase.Phase.GAME_OVER,
	]:
		assert_eq(
			PhaseRules.is_movement_locked(phase),
			PhaseRules.is_dead_puck_phase(phase),
			"is_movement_locked should match is_dead_puck_phase for phase %d" % phase)
