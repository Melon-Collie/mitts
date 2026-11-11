extends GutTest

# FightRules — who may challenge whom, the phases a fight can start in, and when
# a fight is over. docs/fighting-plan.md.


func test_fights_are_off_in_practice_and_in_the_off_set() -> void:
	assert_true(FightRules.allowed(GameRules.RuleSet.ARCADE, true, false))
	assert_true(FightRules.allowed(GameRules.RuleSet.NHL, true, false))
	assert_false(FightRules.allowed(GameRules.RuleSet.ARCADE, false, false),
			"the lobby toggle turns them off")
	assert_false(FightRules.allowed(GameRules.RuleSet.ARCADE, true, true),
			"never in free play, the tutorial or a drill")
	assert_false(FightRules.allowed(GameRules.RuleSet.OFF, true, false),
			"never where nothing is whistled")


func test_a_fight_starts_in_live_play_only() -> void:
	for phase: int in [GamePhase.Phase.PLAYING, GamePhase.Phase.FACEOFF]:
		assert_true(FightRules.phase_allows(phase), GamePhase.Phase.keys()[phase])
	for phase: int in [GamePhase.Phase.FACEOFF_PREP,
			GamePhase.Phase.GOAL_CELEBRATION, GamePhase.Phase.GOAL_SCORED,
			GamePhase.Phase.END_OF_PERIOD, GamePhase.Phase.GAME_OVER, GamePhase.Phase.FIGHT]:
		assert_false(FightRules.phase_allows(phase), GamePhase.Phase.keys()[phase])


func test_the_challenger_has_to_be_squared_up_and_close() -> void:
	var me := Vector2.ZERO
	var ahead := Vector2(0.0, 1.0)
	assert_true(FightRules.can_challenge(me, ahead, Vector2(0.0, 1.5)), "in front, in range")
	assert_true(FightRules.can_challenge(me, ahead, Vector2(1.0, 1.0)), "45° off: still squared up")
	assert_false(FightRules.can_challenge(me, ahead, Vector2(1.5, 0.0)), "beside him")
	assert_false(FightRules.can_challenge(me, ahead, Vector2(0.0, -1.5)), "behind him")
	assert_false(FightRules.can_challenge(me, ahead,
			Vector2(0.0, FightRules.CHALLENGE_RANGE_M + 0.1)), "out of range")


func test_bodies_on_top_of_each_other_can_always_be_challenged() -> void:
	assert_true(FightRules.can_challenge(Vector2.ZERO, Vector2(0.0, 1.0), Vector2.ZERO))
	assert_true(FightRules.can_challenge(Vector2.ZERO, Vector2.ZERO, Vector2(0.5, 0.0)),
			"no facing to judge by")


func test_the_answer_can_come_from_any_side_and_a_little_further() -> void:
	assert_gt(FightRules.ACCEPT_RANGE_M, FightRules.CHALLENGE_RANGE_M)
	assert_true(FightRules.can_accept(Vector2.ZERO, Vector2(-3.0, 0.0)))
	assert_false(FightRules.can_accept(Vector2.ZERO,
			Vector2(0.0, FightRules.ACCEPT_RANGE_M + 0.1)))


func test_apart_time_grows_only_while_apart_and_starts_over_on_closing() -> void:
	var far: float = FightRules.DISENGAGE_M + 0.5
	var near: float = FightRules.DISENGAGE_M - 0.5
	var apart: float = FightRules.step_apart(0.0, far, 0.5)
	apart = FightRules.step_apart(apart, far, 0.5)
	assert_almost_eq(apart, 1.0, 0.0001)
	assert_eq(FightRules.step_apart(apart, near, 0.5), 0.0)


func test_a_fight_ends_when_they_let_go_or_the_linesmen_come() -> void:
	assert_eq(FightRules.end_of(1.0, 0.0), FightRules.End.NONE)
	assert_eq(FightRules.end_of(1.0, FightRules.DISENGAGE_S), FightRules.End.DISENGAGED)
	assert_eq(FightRules.end_of(FightRules.FIGHT_MAX_S, 0.0), FightRules.End.LINESMEN)


func test_the_stoppage_locks_the_puck_and_suspends_contact_but_not_skating() -> void:
	var fight := GamePhase.Phase.FIGHT
	assert_true(PhaseRules.is_puck_pickup_locked_phase(fight))
	assert_true(PhaseRules.suspends_contact(fight))
	assert_false(PhaseRules.is_movement_locked(fight), "the fighters skate")
	assert_false(PhaseRules.is_dead_puck_phase(fight))
	assert_false(PhaseRules.suspends_contact(GamePhase.Phase.PLAYING))
	assert_true(PhaseRules.suspends_contact(GamePhase.Phase.FACEOFF_PREP),
			"every locked phase still passes bodies through each other")


func test_a_fight_whistles_play_dead_and_restarts_with_a_faceoff() -> void:
	var sm := GameStateMachine.new()
	var dot := Vector2(GameRules.END_ZONE_FACEOFF_DOT_X, GameRules.ICING_FACEOFF_DOT_Z)
	assert_true(sm.begin_fight(dot))
	assert_eq(sm.current_phase, GamePhase.Phase.FIGHT)
	var clock: float = sm.time_remaining
	sm.tick(5.0)
	assert_eq(sm.current_phase, GamePhase.Phase.FIGHT, "only the tracker ends a fight")
	assert_eq(sm.time_remaining, clock, "the clock is stopped")
	assert_false(sm.begin_fight(Vector2.ZERO), "no second whistle inside the stoppage")
	assert_true(sm.end_fight())
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF_PREP)
	assert_eq(sm.active_faceoff_dot, dot)
	assert_false(sm.end_fight(), "nothing to end outside a fight")


func test_no_fight_in_the_faceoff_set_up() -> void:
	var sm := GameStateMachine.new()
	sm.begin_faceoff_prep(Vector2(-GameRules.END_ZONE_FACEOFF_DOT_X, GameRules.ICING_FACEOFF_DOT_Z))
	assert_false(sm.begin_fight(Vector2.ZERO))
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF_PREP)


func test_no_fight_in_the_goal_celebration() -> void:
	var sm := GameStateMachine.new()
	sm.on_goal_scored(1)
	assert_false(sm.begin_fight(Vector2.ZERO))
	assert_eq(sm.current_phase, GamePhase.Phase.GOAL_CELEBRATION)
