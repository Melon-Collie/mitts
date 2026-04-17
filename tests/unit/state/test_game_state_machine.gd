extends GutTest

# GameStateMachine — the domain-layer FSM. Tests cover phase transitions,
# scoring, player registry, icing + ghost computation, and remote sync.

var sm: GameStateMachine

func before_each() -> void:
	sm = GameStateMachine.new()

# ── Phase transitions ────────────────────────────────────────────────────────

func test_initial_phase_is_playing() -> void:
	assert_eq(sm.current_phase, GamePhase.Phase.PLAYING)

func test_goal_transitions_to_goal_scored() -> void:
	var scorer: int = sm.on_goal_scored(1)
	assert_eq(scorer, 0)
	assert_eq(sm.current_phase, GamePhase.Phase.GOAL_SCORED)
	assert_eq(sm.scores[0], 1)
	assert_eq(sm.scores[1], 0)

func test_goal_ignored_during_non_playing_phase() -> void:
	sm.on_goal_scored(1)   # → GOAL_SCORED, score 1-0
	var result: int = sm.on_goal_scored(1)
	assert_eq(result, -1, "second goal during GOAL_SCORED should be ignored")
	assert_eq(sm.scores[0], 1, "score unchanged")

func test_goal_pause_expires_to_faceoff_prep() -> void:
	sm.on_goal_scored(1)
	var changed: bool = sm.tick(GameRules.GOAL_PAUSE_DURATION + 0.01)
	assert_true(changed)
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF_PREP)

func test_partial_tick_does_not_transition() -> void:
	sm.on_goal_scored(1)
	var changed: bool = sm.tick(GameRules.GOAL_PAUSE_DURATION / 2)
	assert_false(changed)
	assert_eq(sm.current_phase, GamePhase.Phase.GOAL_SCORED)

func test_faceoff_prep_expires_to_faceoff() -> void:
	sm.begin_faceoff_prep()
	sm.tick(GameRules.FACEOFF_PREP_DURATION + 0.01)
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF)

func test_puck_pickup_during_faceoff_resumes_playing() -> void:
	sm.begin_faceoff_prep()
	sm.tick(GameRules.FACEOFF_PREP_DURATION + 0.01)  # → FACEOFF
	var resumed: bool = sm.on_faceoff_puck_picked_up()
	assert_true(resumed)
	assert_eq(sm.current_phase, GamePhase.Phase.PLAYING)

func test_puck_pickup_outside_faceoff_noop() -> void:
	var resumed: bool = sm.on_faceoff_puck_picked_up()  # still PLAYING
	assert_false(resumed)
	assert_eq(sm.current_phase, GamePhase.Phase.PLAYING)

func test_faceoff_timeout_resumes_playing() -> void:
	sm.begin_faceoff_prep()
	sm.tick(GameRules.FACEOFF_PREP_DURATION + 0.01)  # → FACEOFF
	sm.tick(GameRules.FACEOFF_TIMEOUT + 0.01)
	assert_eq(sm.current_phase, GamePhase.Phase.PLAYING)

func test_full_cycle_playing_to_playing() -> void:
	sm.on_goal_scored(1)
	sm.tick(GameRules.GOAL_PAUSE_DURATION + 0.01)         # → FACEOFF_PREP
	sm.tick(GameRules.FACEOFF_PREP_DURATION + 0.01)       # → FACEOFF
	sm.on_faceoff_puck_picked_up()                         # → PLAYING
	assert_eq(sm.current_phase, GamePhase.Phase.PLAYING)

func test_tick_during_playing_returns_false() -> void:
	assert_false(sm.tick(1.0))
	assert_eq(sm.current_phase, GamePhase.Phase.PLAYING)

# ── Movement locking ─────────────────────────────────────────────────────────

func test_movement_locked_during_goal_scored() -> void:
	sm.on_goal_scored(1)
	assert_true(sm.is_movement_locked())

func test_movement_unlocked_during_faceoff() -> void:
	sm.begin_faceoff_prep()
	sm.tick(GameRules.FACEOFF_PREP_DURATION + 0.01)
	assert_false(sm.is_movement_locked())

# ── Player registry ──────────────────────────────────────────────────────────

func test_host_registration_gets_slot_0() -> void:
	var r: Dictionary = sm.register_host(1)
	assert_eq(r.slot, 0)
	assert_eq(r.team_id, 0)

func test_first_connected_peer_gets_team_0_if_host_on_team_0() -> void:
	# If host didn't register, the first connected peer gets team 0
	var r: Dictionary = sm.on_player_connected(100)
	assert_eq(r.slot, 1)
	assert_eq(r.team_id, 0)

func test_second_connected_peer_balances_to_team_1() -> void:
	sm.register_host(1)           # team 0
	sm.on_player_connected(100)   # team 1
	var r: Dictionary = sm.on_player_connected(200)
	# host team 0, peer 100 team 1 → peer 200 should go team 0 (smaller)
	assert_eq(r.team_id, 0)
	assert_eq(r.slot, 2)

func test_disconnected_player_removed() -> void:
	sm.register_host(1)
	sm.on_player_connected(100)
	sm.on_player_disconnected(100)
	assert_false(sm.players.has(100))
	assert_true(sm.players.has(1))

# ── Icing ────────────────────────────────────────────────────────────────────

func test_icing_triggered_by_loose_puck_past_goal_line() -> void:
	sm.notify_puck_carried(0, 5.0)
	sm.check_icing_for_loose_puck(-30.0)
	assert_eq(sm.icing_team_id, 0)

func test_icing_expires_after_timer() -> void:
	sm.notify_puck_carried(0, 5.0)
	sm.check_icing_for_loose_puck(-30.0)
	assert_eq(sm.icing_team_id, 0)
	sm.tick(GameRules.ICING_GHOST_DURATION + 0.01)
	assert_eq(sm.icing_team_id, -1)

func test_icing_cleared_by_opponent_pickup() -> void:
	sm.notify_puck_carried(0, 5.0)
	sm.check_icing_for_loose_puck(-30.0)
	assert_eq(sm.icing_team_id, 0)
	sm.notify_puck_carried(1, -10.0)  # team 1 picks up
	assert_eq(sm.icing_team_id, -1)

func test_icing_not_triggered_during_dead_puck_phase() -> void:
	sm.on_goal_scored(1)  # → GOAL_SCORED
	sm.notify_puck_carried(0, 5.0)
	sm.check_icing_for_loose_puck(-30.0)
	assert_eq(sm.icing_team_id, -1, "icing only detects during PLAYING")

func test_icing_not_triggered_from_attacking_half() -> void:
	sm.notify_puck_carried(0, -5.0)  # already past center
	sm.check_icing_for_loose_puck(-30.0)
	assert_eq(sm.icing_team_id, -1)

# ── Hybrid icing race ────────────────────────────────────────────────────────

func test_icing_waved_off_when_icing_team_closer() -> void:
	sm.register_host(1)         # peer 1 → team 0
	sm.on_player_connected(100) # peer 100 → team 1
	sm.notify_puck_carried(0, 5.0)
	# Team 0 iced it: goal line at z = -26.6
	# Peer 1 (team 0, icing team) at z = -25 → 1.6 units away
	# Peer 100 (team 1, defending) at z = 0 → 26.6 units away
	sm.check_icing_for_loose_puck(-30.0, {1: Vector3(0, 1, -25.0), 100: Vector3(0, 1, 0.0)})
	assert_eq(sm.icing_team_id, -1, "icing team closer → waved off")

func test_icing_confirmed_when_defending_team_closer() -> void:
	sm.register_host(1)         # peer 1 → team 0
	sm.on_player_connected(100) # peer 100 → team 1
	sm.notify_puck_carried(0, 5.0)
	# Peer 1 (team 0, icing team) at z = 5 → 31.6 units from -26.6
	# Peer 100 (team 1, defending) at z = -24 → 2.6 units from -26.6
	sm.check_icing_for_loose_puck(-30.0, {1: Vector3(0, 1, 5.0), 100: Vector3(0, 1, -24.0)})
	assert_eq(sm.icing_team_id, 0, "defending team closer → icing confirmed")

func test_icing_confirmed_when_defending_team_slightly_closer() -> void:
	sm.register_host(1)
	sm.on_player_connected(100)
	sm.notify_puck_carried(0, 5.0)
	# Peer 1 (team 0, icing) at z = -22 → 4.6 from goal line -26.6
	# Peer 100 (team 1, defending) at z = -24 → 2.6 from goal line → closer
	sm.check_icing_for_loose_puck(-30.0, {1: Vector3(0, 1, -22.0), 100: Vector3(0, 1, -24.0)})
	assert_eq(sm.icing_team_id, 0, "defending team slightly closer → icing confirmed")

func test_icing_waved_off_team1_symmetric() -> void:
	sm.register_host(1)         # team 0
	sm.on_player_connected(100) # team 1
	sm.on_player_connected(200) # team 0
	sm.notify_puck_carried(1, -5.0)
	# Team 1 iced toward +Z: goal line at z = +26.6
	# Peer 100 (team 1, icing team) at z = 25 → 1.6 away
	# Peer 1 (team 0, defending) at z = 0 → 26.6 away
	sm.check_icing_for_loose_puck(30.0, {1: Vector3(0, 1, 0.0), 100: Vector3(0, 1, 25.0)})
	assert_eq(sm.icing_team_id, -1, "team 1 icing, waved off — attacker closer")

# ── Ghost computation ────────────────────────────────────────────────────────

func test_ghost_empty_when_no_players() -> void:
	var ghosts: Dictionary = sm.compute_ghost_state({}, -1, Vector3.ZERO)
	assert_eq(ghosts.size(), 0)

func test_offside_skater_ghosted_during_play() -> void:
	sm.register_host(1)  # team 0
	var ghosts: Dictionary = sm.compute_ghost_state(
		{1: Vector3(0, 1, -10)},  # team 0 attacking zone
		-1, Vector3(0, 0, 0))     # puck in neutral
	assert_true(ghosts[1])

func test_carrier_not_ghosted_by_offside() -> void:
	sm.register_host(1)
	var ghosts: Dictionary = sm.compute_ghost_state(
		{1: Vector3(0, 1, -10)},
		1,                          # peer 1 is the carrier
		Vector3(0, 0, 0))
	assert_false(ghosts[1])

func test_icing_team_all_ghosted() -> void:
	sm.register_host(1)  # team 0
	sm.notify_puck_carried(0, 5.0)
	sm.check_icing_for_loose_puck(-30.0)
	var ghosts: Dictionary = sm.compute_ghost_state(
		{1: Vector3(0, 1, 0)},      # position that wouldn't be offside
		-1, Vector3.ZERO)
	assert_true(ghosts[1])

func test_no_ghosts_during_dead_puck_phase() -> void:
	sm.register_host(1)
	sm.on_goal_scored(1)  # → GOAL_SCORED
	var ghosts: Dictionary = sm.compute_ghost_state(
		{1: Vector3(0, 1, -10)},    # would be offside during play
		-1, Vector3(0, 0, 0))
	assert_false(ghosts[1])

# ── Reset ────────────────────────────────────────────────────────────────────

func test_reset_scores_zeros_both_teams() -> void:
	sm.on_goal_scored(1)   # score 1-0
	sm.reset_scores()
	assert_eq(sm.scores[0], 0)
	assert_eq(sm.scores[1], 0)

func test_begin_faceoff_prep_clears_icing() -> void:
	sm.notify_puck_carried(0, 5.0)
	sm.check_icing_for_loose_puck(-30.0)
	assert_eq(sm.icing_team_id, 0)
	sm.begin_faceoff_prep()
	assert_eq(sm.icing_team_id, -1)
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF_PREP)

# ── Remote state application ────────────────────────────────────────────────

func test_apply_remote_state_updates_scores_and_phase() -> void:
	var changed: bool = sm.apply_remote_state(3, 2, GamePhase.Phase.FACEOFF, 1, 200.0)
	assert_true(changed)
	assert_eq(sm.scores[0], 3)
	assert_eq(sm.scores[1], 2)
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF)

func test_apply_remote_state_returns_false_if_phase_unchanged() -> void:
	sm.apply_remote_state(0, 0, GamePhase.Phase.PLAYING, 1, 240.0)
	var changed: bool = sm.apply_remote_state(1, 0, GamePhase.Phase.PLAYING, 1, 239.0)
	assert_false(changed, "same phase even though scores changed")

func test_apply_remote_goal_sets_phase_and_scores() -> void:
	sm.apply_remote_goal(0, 1, 0)
	assert_eq(sm.scores[0], 1)
	assert_eq(sm.last_scoring_team_id, 0)
	assert_eq(sm.current_phase, GamePhase.Phase.GOAL_SCORED)

# ── Faceoff positions ───────────────────────────────────────────────────────

func test_faceoff_positions_per_player_slot() -> void:
	var host_assignment: Dictionary = sm.register_host(1)
	var peer_assignment: Dictionary = sm.on_player_connected(100)
	var positions: Dictionary = sm.get_faceoff_positions()
	assert_eq(positions.size(), 2)
	assert_eq(positions[1],
			PlayerRules.faceoff_position(host_assignment.team_id, host_assignment.team_slot))
	assert_eq(positions[100],
			PlayerRules.faceoff_position(peer_assignment.team_id, peer_assignment.team_slot))

# ── Period / clock ───────────────────────────────────────────────────────────

func test_period_clock_expires_to_end_of_period() -> void:
	var changed: bool = sm.tick(GameRules.PERIOD_DURATION + 0.01)
	assert_true(changed)
	assert_eq(sm.current_phase, GamePhase.Phase.END_OF_PERIOD)
	assert_eq(sm.current_period, 1, "period should not have advanced yet")
	assert_eq(sm.time_remaining, 0.0)

func test_period_clock_expires_on_last_period_to_game_over() -> void:
	sm.current_period = GameRules.NUM_PERIODS
	sm.tick(GameRules.PERIOD_DURATION + 0.01)
	assert_eq(sm.current_phase, GamePhase.Phase.GAME_OVER)

func test_advance_period_increments_period_and_resets_clock() -> void:
	# Expire current period → END_OF_PERIOD
	sm.tick(GameRules.PERIOD_DURATION + 0.01)
	assert_eq(sm.current_phase, GamePhase.Phase.END_OF_PERIOD)
	# Wait out the end-of-period pause → FACEOFF_PREP (period 2)
	sm.tick(GameRules.END_OF_PERIOD_PAUSE + 0.01)
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF_PREP)
	assert_eq(sm.current_period, 2)
	assert_eq(sm.time_remaining, GameRules.PERIOD_DURATION)

func test_game_over_locks_phase_permanently() -> void:
	sm.current_period = GameRules.NUM_PERIODS
	sm.tick(GameRules.PERIOD_DURATION + 0.01)
	assert_eq(sm.current_phase, GamePhase.Phase.GAME_OVER)
	var changed: bool = sm.tick(999.0)
	assert_false(changed, "GAME_OVER should not tick out")
	assert_eq(sm.current_phase, GamePhase.Phase.GAME_OVER)

func test_reset_all_zeros_scores_and_resets_period() -> void:
	sm.on_goal_scored(1)   # score 1-0
	sm.current_period = 2
	sm.time_remaining = 60.0
	sm.reset_all()
	assert_eq(sm.scores[0], 0)
	assert_eq(sm.scores[1], 0)
	assert_eq(sm.current_period, 1)
	assert_eq(sm.time_remaining, GameRules.PERIOD_DURATION)

func test_clock_does_not_tick_during_dead_puck_phase() -> void:
	sm.on_goal_scored(1)  # → GOAL_SCORED
	var time_before: float = sm.time_remaining
	sm.tick(GameRules.GOAL_PAUSE_DURATION + 0.01)  # advances to FACEOFF_PREP
	assert_eq(sm.time_remaining, time_before, "clock must not tick during GOAL_SCORED")
