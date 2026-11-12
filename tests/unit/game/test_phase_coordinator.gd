extends GutTest

# PhaseCoordinator — phase-entry dispatch + goal-scoring pipeline.
#
# The coordinator's node-side effects (puck pickup-lock, goalie reset, skater
# teleports, goal VFX, replay cinematic) need live scene actors, so those are
# exercised via an empty registry + null puck (the getters
# resolve to null/empty) — what's covered here is the *decision* logic: which
# signals fire per phase, the carrier/own-goal scorer attribution, the
# host-vs-client goal paths, and the client faceoff-prep guard.

var coord: PhaseCoordinator
var sm: GameStateMachine
var registry: PlayerRegistry
var tracker: ShotOnGoalTracker
var teams: Array[Team]
var _drop_calls: int
var _drop_return: int


# Records the skate-in it was handed instead of gliding a body.
class StubController extends SkaterController:
	var durations: Array[float] = []
	var targets: Array[Vector3] = []

	func begin_approach(_start: Vector3, target: Vector3, _settle_facing: Vector2,
			duration: float, _initial_velocity: Vector3 = Vector3.ZERO) -> void:
		durations.append(duration)
		targets.append(target)

	func faceoff_center_distance() -> float:
		return 1.0


func before_each() -> void:
	sm = GameStateMachine.new()
	registry = PlayerRegistry.new()
	tracker = ShotOnGoalTracker.new()
	tracker.setup(registry, sm)
	teams = [_make_team(0), _make_team(1)]
	_drop_calls = 0
	_drop_return = -1
	NetworkManager.is_tutorial_mode = false
	coord = PhaseCoordinator.new()
	coord.setup(
			sm, registry, teams,
			Callable(),                        # puck_getter invalid → null puck
			Callable(self, "_empty_goalies"),  # goalie_controllers_getter
			tracker,
			Callable(self, "_fake_drop"),      # puck_drop_requester
			null, null, null,                  # recorder, goal_replay_driver, codec
			null,                              # scene_tree
			false,                             # is_host
			Callable())                        # force_record_goal_frame
	watch_signals(coord)


func _make_team(team_id: int) -> Team:
	var t := Team.new()
	t.team_id = team_id
	return t


func _empty_goalies() -> Array:
	return []


func _fake_drop() -> int:
	_drop_calls += 1
	return _drop_return


func _add_player(peer_id: int, team_id: int, is_local: bool = false) -> PlayerRecord:
	var record := PlayerRecord.new(peer_id, 0, is_local, teams[team_id])
	record.stats = PlayerStats.new()
	registry._players[peer_id] = record
	return record


# ── handle_phase_entered: per-phase signal dispatch ──────────────────────────

func test_phase_entered_playing_emits_phase_changed() -> void:
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.handle_phase_entered()
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.PLAYING])


func test_phase_entered_faceoff_emits_phase_changed() -> void:
	sm.current_phase = GamePhase.Phase.FACEOFF
	coord.handle_phase_entered()
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.FACEOFF])


func test_phase_entered_end_of_period_drops_puck_and_zeroes_clock() -> void:
	sm.current_phase = GamePhase.Phase.END_OF_PERIOD
	coord.handle_phase_entered()
	assert_eq(_drop_calls, 1, "end of period requests a puck drop")
	assert_signal_emitted_with_parameters(coord, "clock_updated", [0.0])
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.END_OF_PERIOD])


func test_phase_entered_game_over_emits_game_over() -> void:
	sm.current_phase = GamePhase.Phase.GAME_OVER
	coord.handle_phase_entered()
	assert_eq(_drop_calls, 1)
	assert_signal_emitted(coord, "game_over")
	assert_signal_emitted_with_parameters(coord, "clock_updated", [0.0])
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.GAME_OVER])


func test_phase_entered_faceoff_prep_syncs_period_clock_and_announces() -> void:
	sm.current_phase = GamePhase.Phase.FACEOFF_PREP
	sm.current_period = 2
	sm.time_remaining = 300.0
	coord.handle_phase_entered()
	assert_signal_emitted_with_parameters(coord, "period_synced", [2])
	assert_signal_emitted_with_parameters(coord, "clock_updated", [300.0])
	assert_signal_emitted(coord, "stats_need_sync")
	assert_signal_emitted(coord, "faceoff_positions_ready")
	assert_signal_emitted(coord, "faceoff_prep_announced")
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.FACEOFF_PREP])


# ── on_pickup: faceoff → playing transition ──────────────────────────────────

func test_on_pickup_during_faceoff_transitions_to_playing() -> void:
	sm.current_phase = GamePhase.Phase.FACEOFF
	coord.on_pickup(10)
	assert_eq(sm.current_phase, GamePhase.Phase.PLAYING)
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.PLAYING])


func test_on_pickup_outside_faceoff_is_noop() -> void:
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_pickup(10)
	assert_signal_not_emitted(coord, "phase_changed")


# ── on_goal_scored_into: host goal pipeline ──────────────────────────────────

func test_goal_credits_carrier_and_updates_score() -> void:
	_add_player(10, 0)        # scorer on team 0
	_drop_return = 10         # puck carrier is peer 10
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_goal_scored_into(teams[1])  # defending team 1 → scoring team 0
	assert_eq(registry._players[10].stats.goals, 1, "carrier credited the goal")
	assert_eq(sm.scores[0], 1)
	# team_slot 0 → display name "P1"; no prior carriers → no assists.
	assert_signal_emitted_with_parameters(coord, "goal_scored", [teams[0], "P1", "", ""])
	assert_signal_emitted_with_parameters(coord, "score_changed", [1, 0])
	assert_signal_emitted(coord, "goal_broadcast_needed")
	assert_signal_emitted(coord, "stats_need_sync")
	assert_eq(sm.current_phase, GamePhase.Phase.GOAL_CELEBRATION)


func test_own_goal_does_not_credit_the_own_goaler() -> void:
	_add_player(10, 1)        # carrier is on the DEFENDING team → own goal
	_drop_return = 10
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_goal_scored_into(teams[1])  # defending 1, scoring 0
	assert_eq(registry._players[10].stats.goals, 0, "own-goaler is not credited")
	assert_eq(sm.scores[0], 1, "goal still counts for the scoring team")
	# No team-0 toucher to redirect credit to → scorer name blank.
	assert_signal_emitted_with_parameters(coord, "goal_scored", [teams[0], "", "", ""])


func test_goal_in_wrong_phase_is_ignored() -> void:
	_add_player(10, 0)
	_drop_return = 10
	sm.current_phase = GamePhase.Phase.FACEOFF  # not PLAYING
	coord.on_goal_scored_into(teams[1])
	assert_eq(_drop_calls, 1, "puck drop fires before the phase gate")
	assert_eq(sm.scores[0], 0, "no goal registered out of PLAYING")
	assert_eq(registry._players[10].stats.goals, 0)
	assert_signal_not_emitted(coord, "goal_scored")
	assert_signal_not_emitted(coord, "phase_changed")


func test_tutorial_mode_short_circuits_goal() -> void:
	NetworkManager.is_tutorial_mode = true
	_add_player(10, 0)
	_drop_return = 10
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_goal_scored_into(teams[1])
	NetworkManager.is_tutorial_mode = false
	assert_eq(_drop_calls, 0, "tutorial returns before any side effect")
	assert_eq(sm.scores[0], 0)
	assert_signal_not_emitted(coord, "goal_scored")


# ── on_goal_received: client applies authoritative goal ──────────────────────

func test_on_goal_received_applies_score_and_emits() -> void:
	_add_player(10, 0)
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_goal_received(0, 3, 2, "Scorer", "A1", "")
	assert_eq(sm.scores[0], 3)
	assert_eq(sm.scores[1], 2)
	assert_signal_emitted_with_parameters(coord, "goal_scored", [teams[0], "Scorer", "A1", ""])
	assert_signal_emitted_with_parameters(coord, "score_changed", [3, 2])
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.GOAL_CELEBRATION])


# ── on_faceoff_positions: client faceoff-prep entry + guard ──────────────────

func test_on_faceoff_positions_advances_phase_and_announces() -> void:
	sm.current_phase = GamePhase.Phase.GOAL_CELEBRATION
	coord.on_faceoff_positions([], 0.0)
	assert_eq(sm.current_phase, GamePhase.Phase.FACEOFF_PREP)
	assert_signal_emitted_with_parameters(coord, "phase_changed", [GamePhase.Phase.FACEOFF_PREP])
	assert_signal_emitted(coord, "faceoff_prep_announced")


func test_on_faceoff_positions_when_already_in_faceoff_only_announces() -> void:
	sm.current_phase = GamePhase.Phase.FACEOFF
	coord.on_faceoff_positions([], 0.0)
	assert_signal_not_emitted(coord, "phase_changed")
	assert_signal_emitted(coord, "faceoff_prep_announced")


# ── The countdown waits for the last skater ──────────────────────────────────

func _add_skating_player(peer_id: int, team_id: int, is_local: bool = false) -> StubController:
	var record: PlayerRecord = _add_player(peer_id, team_id, is_local)
	var c := StubController.new()
	autofree(c)
	record.controller = c
	return c


func _assert_prep_holds_until_last_arrival(controllers: Array[StubController]) -> void:
	var last: float = 0.0
	for c: StubController in controllers:
		assert_eq(c.durations.size(), 1, "every skater skates in")
		last = maxf(last, c.durations[0])
	assert_almost_eq(coord.last_prep_preroll, last + GameRules.FACEOFF_SET_BEAT, 0.0001,
			"the countdown starts once the last skater is set")
	assert_almost_eq(sm.faceoff_prep_time_until_drop(),
			coord.last_prep_preroll + GameRules.FACEOFF_PREP_DURATION, 0.0001,
			"the drop is a full countdown after that")
	assert_signal_emitted_with_parameters(coord, "faceoff_positions_ready",
			[get_signal_parameters(coord, "faceoff_positions_ready")[0], coord.last_prep_preroll])


func test_stoppage_prep_holds_the_countdown_until_the_last_arrival() -> void:
	var cs: Array[StubController] = [_add_skating_player(10, 0), _add_skating_player(11, 1)]
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	_assert_prep_holds_until_last_arrival(cs)


func test_post_goal_prep_holds_the_countdown_until_the_slowest_arrival() -> void:
	var cs: Array[StubController] = [
			_add_skating_player(10, 0), _add_skating_player(11, 0),
			_add_skating_player(12, 1), _add_skating_player(13, 1)]
	coord._staged_faceoff_pending = true
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	var spread: bool = false
	for c: StubController in cs:
		spread = spread or not is_equal_approx(c.durations[0], cs[0].durations[0])
	assert_true(spread, "staggered arrivals, so the hold is the slowest one, not any one")
	_assert_prep_holds_until_last_arrival(cs)


func test_client_takes_the_hosts_hold() -> void:
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_faceoff_positions([], 2.75)
	assert_eq(coord.last_prep_preroll, 2.75)


func test_client_skate_in_never_outlasts_the_hosts_hold() -> void:
	# The local start is the predicted body, which can sit further out than the
	# host measured from; the glide is clipped so the "2" still finds it set.
	var c: StubController = _add_skating_player(10, 0, true)
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_faceoff_positions([10, 0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.5], 0.5)
	assert_eq(c.durations.size(), 1)
	assert_lte(c.durations[0], 0.5 - GameRules.FACEOFF_SET_BEAT + 0.0001)


# ── A team short at the faceoff (FaceoffFormation) ───────────────────────────

func _add_seated_player(peer_id: int, team_id: int, team_slot: int) -> PlayerRecord:
	var record: PlayerRecord = _add_player(peer_id, team_id)
	record.team_slot = team_slot
	var c := StubController.new()
	autofree(c)
	record.controller = c
	return record


func _placed_position(peer_id: int) -> Vector3:
	var positions: Array = get_signal_parameters(coord, "faceoff_positions_ready")[0]
	for at: int in range(0, positions.size(), 4):
		if int(positions[at]) == peer_id:
			return Vector3(positions[at + 1], positions[at + 2], positions[at + 3])
	return Vector3.INF


func test_with_no_centre_a_winger_is_placed_on_the_dot_and_his_defenseman_on_the_wing() -> void:
	sm.team_size = 5
	_add_seated_player(11, 0, 1)  # LW
	_add_seated_player(12, 0, 2)  # RW
	_add_seated_player(13, 0, 3)  # LD
	_add_seated_player(14, 0, 4)  # RD
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	var dot: Vector2 = GameRules.CENTER_ICE_DOT
	var reach: float = 1.0  # StubController.faceoff_center_distance
	assert_eq(_placed_position(11), PlayerRules.faceoff_position(0, 0, dot, reach, 5),
			"the left wing takes the draw, at his own reach from the dot")
	assert_eq(_placed_position(13), PlayerRules.faceoff_position(0, 1, dot, -1.0, 5),
			"the left defenseman steps up to the wing")
	assert_eq(_placed_position(12), PlayerRules.faceoff_position(0, 2, dot, -1.0, 5))
	assert_eq(_placed_position(14), PlayerRules.faceoff_position(0, 4, dot, -1.0, 5))


func test_a_full_team_is_placed_seat_for_seat() -> void:
	sm.team_size = 5
	for seat: int in PlayerRules.MAX_PER_TEAM:
		_add_seated_player(10 + seat, 1, seat)
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	for seat: int in PlayerRules.MAX_PER_TEAM:
		var reach: float = 1.0 if seat == 0 else -1.0
		assert_eq(_placed_position(10 + seat),
				PlayerRules.faceoff_position(1, seat, GameRules.CENTER_ICE_DOT, reach, 5),
				"seat %d" % seat)


func test_a_client_reads_the_draw_taker_off_who_the_host_placed() -> void:
	var wing: PlayerRecord = _add_seated_player(11, 0, 1)
	var defender: PlayerRecord = _add_seated_player(13, 0, 3)
	var centre: PlayerRecord = _add_seated_player(20, 1, 0)
	for record: PlayerRecord in [wing, defender, centre]:
		record.skater = Skater.new()
		autofree(record.skater)
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_faceoff_positions([
			11, 0.0, 1.0, 1.0,
			13, -4.7, 1.0, 0.9,
			20, 0.0, 1.0, -1.0], 0.0)
	assert_true(wing.skater.is_faceoff_center, "his team placed no centre")
	assert_false(defender.skater.is_faceoff_center)
	assert_true(centre.skater.is_faceoff_center)


# ── A skater in the penalty box ──────────────────────────────────────────────

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")


func _box(record: PlayerRecord) -> void:
	record.skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(record.skater)
	record.skater.set_physics_process(false)
	record.skater.set_process(false)
	record.skater.in_box = true


func test_a_boxed_skater_is_skated_to_his_door_and_the_rest_fill_in() -> void:
	sm.team_size = 5
	var centre: PlayerRecord = _add_seated_player(10, 0, 0)
	_box(centre)
	_add_seated_player(11, 0, 1)  # LW
	_add_seated_player(12, 0, 2)  # RW
	_add_seated_player(13, 0, 3)  # LD
	_add_seated_player(14, 0, 4)  # RD
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	var door: Vector3 = PlayerRules.penalty_box_position(0)
	assert_eq((centre.controller as StubController).targets, [door] as Array[Vector3])
	assert_eq(_placed_position(10), door, "his own client skates him there too")
	var dot: Vector2 = GameRules.CENTER_ICE_DOT
	assert_eq(_placed_position(11), PlayerRules.faceoff_position(0, 0, dot, 1.0, 5),
			"the left wing takes the draw he left")
	assert_eq(_placed_position(13), PlayerRules.faceoff_position(0, 1, dot, -1.0, 5),
			"and the left defenseman the wing")


func test_the_placement_is_announced_before_anyone_is_placed() -> void:
	_add_seated_player(10, 0, 0)
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	assert_signal_emitted(coord, "faceoff_placement_starting")


func test_a_boxed_skater_does_not_skate_off_for_the_period_break() -> void:
	var boxed: PlayerRecord = _add_seated_player(10, 0, 0)
	_box(boxed)
	var free: PlayerRecord = _add_seated_player(11, 0, 1)
	free.skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(free.skater)
	free.skater.set_physics_process(false)
	free.skater.set_process(false)
	coord._is_host = true
	coord.on_period_break_entered()
	assert_eq((boxed.controller as StubController).targets.size(), 0)
	assert_eq((free.controller as StubController).targets.size(), 1)


# ── A penalty shot set up in the faceoff's place ─────────────────────────────

func _with_skater(record: PlayerRecord) -> PlayerRecord:
	record.skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(record.skater)
	record.skater.set_physics_process(false)
	record.skater.set_process(false)
	return record


func test_a_penalty_shot_puts_the_shooter_at_centre_and_the_rest_at_their_benches() -> void:
	var shooter: PlayerRecord = _with_skater(_add_seated_player(10, 0, 1))
	shooter.skater.takes_penalty_shot = true
	var mate: PlayerRecord = _with_skater(_add_seated_player(11, 0, 0))
	mate.skater.sidelined = true
	var opponent: PlayerRecord = _with_skater(_add_seated_player(20, 1, 0))
	opponent.skater.sidelined = true
	sm.begin_faceoff_prep(Vector2(6.7, 21.0))
	coord.handle_phase_entered()
	assert_eq(_placed_position(10), PlayerRules.penalty_shot_start())
	assert_eq(_placed_position(11), PlayerRules.bench_start_position(0, 0))
	assert_eq(_placed_position(20), PlayerRules.bench_start_position(1, 0))
	for record: PlayerRecord in [shooter, mate, opponent]:
		assert_false(record.skater.is_faceoff_center, "nobody takes a draw")
		assert_eq((record.controller as StubController).targets.size(), 1)
	assert_gt(sm.faceoff_prep_time_until_drop(), GameRules.FACEOFF_PREP_DURATION,
			"the countdown waits for everyone to be set")


func test_a_client_takes_no_draw_through_a_penalty_shot() -> void:
	var shooter: PlayerRecord = _with_skater(_add_seated_player(10, 0, 0))
	shooter.skater.takes_penalty_shot = true
	var opponent: PlayerRecord = _with_skater(_add_seated_player(20, 1, 0))
	opponent.skater.sidelined = true
	sm.current_phase = GamePhase.Phase.PLAYING
	coord.on_faceoff_positions([10, 0.0, 1.0, 0.0, 20, 11.5, 1.0, -4.4], 1.0)
	assert_false(shooter.skater.is_faceoff_center)
	assert_false(opponent.skater.is_faceoff_center)


# ── Period break → period-start bench intro ──────────────────────────────────

func test_end_of_period_emits_period_break_and_stashes_next_period() -> void:
	sm.current_period = 1
	sm.current_phase = GamePhase.Phase.END_OF_PERIOD
	coord.handle_phase_entered()
	assert_signal_emitted_with_parameters(
			coord, "period_break_started", [GameRules.INTERMISSION_DURATION])
	assert_eq(coord.period_after_break, 2, "break leads into the next period")


func test_period_break_entry_is_idempotent() -> void:
	sm.current_phase = GamePhase.Phase.END_OF_PERIOD
	coord.on_period_break_entered()
	coord.on_period_break_entered()
	assert_signal_emit_count(coord, "period_break_started", 1,
			"a duplicate phase echo must not restart the skate-off")


func test_prep_after_break_is_period_intro_with_extended_prep() -> void:
	sm.current_phase = GamePhase.Phase.END_OF_PERIOD
	coord.handle_phase_entered()
	sm.begin_faceoff_prep()  # _advance_period's prep entry (0 extra at entry)
	coord.handle_phase_entered()
	assert_true(coord.last_prep_was_period_intro)
	assert_eq(coord.last_prep_preroll, 0.0,
			"period intro rides its own signal, not the skate-in pre-roll")
	assert_almost_eq(sm.faceoff_prep_time_until_drop(),
			GameRules.FACEOFF_PREP_DURATION + GameRules.PERIOD_INTRO_DURATION, 0.001,
			"placement extends the prep window to the period-intro hold")


func test_prep_without_break_is_not_period_intro() -> void:
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	assert_false(coord.last_prep_was_period_intro)
	assert_eq(coord.last_prep_preroll, GameRules.FACEOFF_SET_BEAT,
			"a plain stoppage faceoff with nobody to skate in holds just the set beat")


func test_period_break_flag_is_consumed_by_one_prep() -> void:
	coord.on_period_break_entered()
	sm.begin_faceoff_prep()
	coord.handle_phase_entered()
	assert_true(coord.last_prep_was_period_intro)
	coord.handle_phase_entered()
	assert_false(coord.last_prep_was_period_intro,
			"a second placement without a new break is a normal faceoff")


func test_pregame_intro_overrides_period_break() -> void:
	var intro_coord := PhaseCoordinator.new()
	intro_coord.setup(
			sm, registry, teams,
			Callable(),
			Callable(self, "_empty_goalies"),
			tracker,
			Callable(self, "_fake_drop"),
			null, null, null,
			null,
			false,
			Callable(),
			Callable(self, "_intro_true"))
	watch_signals(intro_coord)
	intro_coord.on_period_break_entered()
	sm.begin_faceoff_prep()
	intro_coord.handle_phase_entered()
	assert_false(intro_coord.last_prep_was_period_intro,
			"a rematch reset mid-break runs the opening bench intro instead")


func _intro_true() -> bool:
	return true
