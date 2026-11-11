extends GutTest

# PhaseRules — pure static functions classifying game phases. Dead-puck phases
# are ones nobody can play the puck in; most of them freeze movement too.

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

func test_goal_celebration_is_not_dead_puck() -> void:
	# Celebration is the post-goal beat where players still skate around.
	assert_false(PhaseRules.is_dead_puck_phase(GamePhase.Phase.GOAL_CELEBRATION))

func test_movement_locked_matches_dead_puck_but_for_goal_scored() -> void:
	for phase in [
		GamePhase.Phase.PLAYING,
		GamePhase.Phase.FACEOFF_PREP,
		GamePhase.Phase.FACEOFF,
		GamePhase.Phase.END_OF_PERIOD,
		GamePhase.Phase.GAME_OVER,
		GamePhase.Phase.GOAL_CELEBRATION,
	]:
		assert_eq(
			PhaseRules.is_movement_locked(phase),
			PhaseRules.is_dead_puck_phase(phase),
			"is_movement_locked should match is_dead_puck_phase for phase %d" % phase)


func test_goal_scored_skates_on_under_the_replays_incoming_wipe() -> void:
	# The replay parks the world itself at full cover; a lock here would stop
	# every skater dead in sight of the band.
	assert_false(PhaseRules.is_movement_locked(GamePhase.Phase.GOAL_SCORED))

# ── is_puck_pickup_locked_phase ─────────────────────────────────────────────
# Superset of is_dead_puck_phase that adds GOAL_CELEBRATION. The puck sits in
# the net during celebration with pickup_locked = true even though players are
# still free to skate; the codec uses this to decide pickup_locked on clients.

func test_pickup_locked_includes_all_dead_puck_phases() -> void:
	for phase in [
		GamePhase.Phase.GOAL_SCORED,
		GamePhase.Phase.FACEOFF_PREP,
		GamePhase.Phase.END_OF_PERIOD,
		GamePhase.Phase.GAME_OVER,
	]:
		assert_true(PhaseRules.is_puck_pickup_locked_phase(phase),
			"dead-puck phase %d should also be pickup-locked" % phase)

func test_pickup_locked_includes_goal_celebration() -> void:
	assert_true(PhaseRules.is_puck_pickup_locked_phase(GamePhase.Phase.GOAL_CELEBRATION))

func test_pickup_unlocked_during_active_play() -> void:
	assert_false(PhaseRules.is_puck_pickup_locked_phase(GamePhase.Phase.PLAYING))
	assert_false(PhaseRules.is_puck_pickup_locked_phase(GamePhase.Phase.FACEOFF))

# ── allows_blade_aim_during_lock ────────────────────────────────────────────
# Stick aim stays live only during FACEOFF_PREP so centers can pre-angle the
# draw during the countdown. Every other locked phase keeps sticks frozen.

func test_faceoff_prep_allows_blade_aim() -> void:
	assert_true(PhaseRules.allows_blade_aim_during_lock(GamePhase.Phase.FACEOFF_PREP))

func test_goal_scored_does_not_allow_blade_aim() -> void:
	assert_false(PhaseRules.allows_blade_aim_during_lock(GamePhase.Phase.GOAL_SCORED))

func test_end_of_period_does_not_allow_blade_aim() -> void:
	assert_false(PhaseRules.allows_blade_aim_during_lock(GamePhase.Phase.END_OF_PERIOD))

func test_game_over_does_not_allow_blade_aim() -> void:
	assert_false(PhaseRules.allows_blade_aim_during_lock(GamePhase.Phase.GAME_OVER))

# ── is_after_goal ───────────────────────────────────────────────────────────
# A replay asks it of recorded frames: the goal-moment frame and its tail are
# stamped GOAL_CELEBRATION, the live replay window GOAL_SCORED.

func test_after_goal_is_the_celebration_and_the_replay() -> void:
	assert_true(PhaseRules.is_after_goal(GamePhase.Phase.GOAL_CELEBRATION))
	assert_true(PhaseRules.is_after_goal(GamePhase.Phase.GOAL_SCORED))

func test_after_goal_excludes_every_other_phase() -> void:
	for phase: int in [
		GamePhase.Phase.PLAYING,
		GamePhase.Phase.FACEOFF_PREP,
		GamePhase.Phase.FACEOFF,
		GamePhase.Phase.END_OF_PERIOD,
		GamePhase.Phase.GAME_OVER,
	]:
		assert_false(PhaseRules.is_after_goal(phase), "phase %d is not after a goal" % phase)
