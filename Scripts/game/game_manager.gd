extends Node

# Orchestrator. Owns the GameStateMachine and wires together six focused
# collaborators, each in its own file:
#
#   PlayerRegistry       — players dict, spawn/despawn, resolvers
#   WorldStateCodec      — RPC-wire serialization for world state + stats
#   ShotOnGoalTracker    — pending-shot state machine + assist crediting
#   HitTracker           — cross-team hit validation + stat crediting
#   PhaseCoordinator     — phase-entry side effects, goal pipeline
#   SlotSwapCoordinator  — mid-game slot swap request/confirm
#
# The public signals below are re-exposed from collaborators so HUD / Camera /
# Scoreboard / Controllers continue to receive the same events.

# ── Signals ───────────────────────────────────────────────────────────────────
signal goal_scored(scoring_team: Team, scorer_name: String, assist1_name: String, assist2_name: String)
signal score_changed(score_0: int, score_1: int)
signal phase_changed(new_phase: GamePhase.Phase)
signal period_changed(new_period: int)
signal clock_updated(time_remaining: float)
signal game_over()
signal game_reset()
signal player_joined(player_name: String, team_color: Color)
signal player_left(player_name: String, team_color: Color)
signal stats_updated
signal shots_on_goal_changed(sog_0: int, sog_1: int)

# ── Domain state ──────────────────────────────────────────────────────────────
var _state_machine: GameStateMachine = null
var _last_emitted_clock_secs: int = -1
var _input_blocked: bool = false

# ── Infrastructure ────────────────────────────────────────────────────────────
var _spawner: ActorSpawner = null
var teams: Array[Team] = []
var puck: Puck = null
var goals: Array[HockeyGoal] = []
var goalies: Array[Goalie] = []
var goalie_controllers: Array[GoalieController] = []
var puck_controller: PuckController = null

# ── Subsystems ────────────────────────────────────────────────────────────────
var _registry: PlayerRegistry = null
var _codec: WorldStateCodec = null
var _shot_tracker: ShotOnGoalTracker = null
var _hit_tracker: HitTracker = null
var _phase_coord: PhaseCoordinator = null
var _swap_coord: SlotSwapCoordinator = null


func _ready() -> void:
	randomize()
	_wire_network_signals()


func _wire_network_signals() -> void:
	NetworkManager.set_world_state_provider(get_world_state)
	NetworkManager.host_ready.connect(on_host_started)
	NetworkManager.client_connected.connect(on_connected_to_server)
	NetworkManager.disconnected_from_server.connect(on_scene_exit)
	NetworkManager.peer_joined.connect(on_player_connected)
	NetworkManager.peer_disconnected.connect(on_player_disconnected)
	NetworkManager.world_state_received.connect(_on_world_state_received)
	NetworkManager.slot_assigned.connect(on_slot_assigned)
	NetworkManager.remote_skater_spawn_requested.connect(spawn_remote_skater)
	NetworkManager.existing_players_synced.connect(sync_existing_players)
	NetworkManager.local_puck_pickup_confirmed.connect(on_local_player_picked_up_puck)
	NetworkManager.local_puck_stolen.connect(on_local_player_puck_stolen)
	NetworkManager.remote_puck_release_received.connect(on_remote_puck_release)
	NetworkManager.carrier_puck_dropped.connect(on_carrier_puck_dropped)
	NetworkManager.goal_received.connect(_on_goal_received)
	NetworkManager.faceoff_positions_received.connect(_on_faceoff_positions_received)
	NetworkManager.game_reset_received.connect(on_game_reset)
	NetworkManager.stats_received.connect(_on_stats_received)
	NetworkManager.slot_swap_requested.connect(_on_slot_swap_requested)
	NetworkManager.slot_swap_confirmed.connect(_on_slot_swap_confirmed)
	NetworkManager.return_to_lobby_received.connect(_on_return_to_lobby)


# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not NetworkManager.is_host or _state_machine == null:
		return
	if _state_machine.tick(delta):
		_phase_coord.handle_phase_entered()
	if _state_machine.current_phase == GamePhase.Phase.PLAYING:
		var secs: int = int(_state_machine.time_remaining)
		if secs != _last_emitted_clock_secs:
			_last_emitted_clock_secs = secs
			clock_updated.emit(_state_machine.time_remaining)


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_host or puck == null or _state_machine == null:
		return
	_update_host_puck_tracking()
	_apply_ghost_state()
	_shot_tracker.tick(delta)


func _update_host_puck_tracking() -> void:
	if puck.carrier != null:
		var carrier_team: Team = _registry.resolve_team(puck.carrier)
		if carrier_team != null:
			_state_machine.notify_puck_carried(carrier_team.team_id, puck.carrier.global_position.z)
	elif _state_machine.current_phase == GamePhase.Phase.PLAYING:
		_state_machine.check_icing_for_loose_puck(
				puck.global_position.z, _registry.positions_by_peer_id())


func _apply_ghost_state() -> void:
	var positions: Dictionary = {}
	var carrier_peer_id: int = -1
	for peer_id: int in _registry.all():
		var record: PlayerRecord = _registry.get_record(peer_id)
		positions[peer_id] = record.skater.global_position
		if puck.carrier != null and record.skater == puck.carrier:
			carrier_peer_id = peer_id
	var ghosts: Dictionary = _state_machine.compute_ghost_state(
			positions, carrier_peer_id, puck.global_position)
	for peer_id in ghosts:
		var r: PlayerRecord = _registry.get_record(peer_id)
		if r != null:
			r.skater.set_ghost(ghosts[peer_id])


# ── Network Callbacks ─────────────────────────────────────────────────────────
func on_host_started() -> void:
	_spawn_world()
	if not NetworkManager.pending_lobby_slots.is_empty():
		var my_slot: Dictionary = NetworkManager.pending_lobby_slots.get(1, {})
		var team_id: int = my_slot.get("team_id", 0)
		var team_slot: int = my_slot.get("team_slot", 0)
		_state_machine.register_remote_assigned_player(1, team_slot, team_id)
		_spawn_local(1, team_slot, teams[team_id])
		_push_lobby_assignments_to_clients()
	else:
		var assignment: Dictionary = _state_machine.register_host(1)
		_spawn_local(1, assignment.team_slot, teams[assignment.team_id])


func on_connected_to_server() -> void:
	pass


func on_slot_assigned(team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color) -> void:
	_spawn_world()
	var peer_id: int = multiplayer.get_unique_id()
	_state_machine.register_remote_assigned_player(peer_id, team_slot, team_id)
	_registry.spawn(peer_id, team_slot, teams[team_id],
			jersey_color, helmet_color, pants_color,
			NetworkManager.local_is_left_handed, NetworkManager.local_player_name, true,
			NetworkManager.local_jersey_number)


func on_player_connected(peer_id: int) -> void:
	if not NetworkManager.is_host or _state_machine == null:
		return
	var assignment: Dictionary = _state_machine.on_player_connected(peer_id)
	var team: Team = teams[assignment.team_id]
	var colors: Dictionary = PlayerRegistry.generate_colors(team.team_id)
	var is_left: bool = NetworkManager.get_peer_handedness(peer_id)
	var peer_name: String = NetworkManager.get_peer_name(peer_id)
	var peer_number: int = NetworkManager.get_peer_number(peer_id)

	var config: Dictionary = {
		"num_periods": _state_machine.num_periods,
		"period_duration": _state_machine.period_duration,
		"ot_enabled": _state_machine.ot_enabled,
		"ot_duration": _state_machine.ot_duration,
	}
	NetworkManager.send_join_in_progress(peer_id, config)
	NetworkManager.send_slot_assignment(peer_id, assignment.team_slot, team.team_id,
			colors.jersey, colors.helmet, colors.pants)
	NetworkManager.send_sync_existing_players(peer_id, _collect_existing_player_data())
	NetworkManager.send_spawn_remote_skater(peer_id, assignment.team_slot, team.team_id,
			colors.jersey, colors.helmet, colors.pants, is_left, peer_name, peer_number)
	_registry.spawn(peer_id, assignment.team_slot, team,
			colors.jersey, colors.helmet, colors.pants, is_left, peer_name, false, peer_number)


func on_player_disconnected(peer_id: int) -> void:
	var record: PlayerRecord = _registry.get_record(peer_id) if _registry != null else null
	if record == null:
		return
	# Drop the puck before freeing the controller so puck_released fires while
	# the record is still intact.
	if NetworkManager.is_host and puck != null and puck.carrier == record.skater:
		puck.drop()
	NetworkManager.unregister_remote_controller(peer_id)
	if puck != null:
		puck.remove_skater_cooldown(record.skater)
	_registry.remove(peer_id)


func sync_existing_players(player_data: Array) -> void:
	if _state_machine == null:
		return
	for entry: Array in player_data:
		var peer_id: int = entry[0]
		var team_slot: int = entry[1]
		var team_id: int = entry[2]
		var jersey_color: Color = entry[3]
		var helmet_color: Color = entry[4]
		var pants_color: Color = entry[5]
		var is_left: bool = entry[6] if entry.size() > 6 else true
		var p_name: String = entry[7] if entry.size() > 7 else "Player"
		var p_number: int = entry[8] if entry.size() > 8 else 10
		_state_machine.register_remote_assigned_player(peer_id, team_slot, team_id)
		_registry.spawn(peer_id, team_slot, teams[team_id],
				jersey_color, helmet_color, pants_color, is_left, p_name, false, p_number)


func spawn_remote_skater(peer_id: int, team_slot: int, team_id: int,
		jersey_color: Color, helmet_color: Color, pants_color: Color,
		is_left_handed: bool, player_name: String, jersey_number: int = 10) -> void:
	if peer_id == multiplayer.get_unique_id() or _state_machine == null:
		return
	_state_machine.register_remote_assigned_player(peer_id, team_slot, team_id)
	_registry.spawn(peer_id, team_slot, teams[team_id],
			jersey_color, helmet_color, pants_color,
			is_left_handed, player_name, false, jersey_number)


# ── World Spawn ───────────────────────────────────────────────────────────────
func _spawn_world() -> void:
	_state_machine = GameStateMachine.new()
	if not NetworkManager.pending_game_config.is_empty():
		var cfg: Dictionary = NetworkManager.pending_game_config
		_state_machine.apply_config(cfg.num_periods, cfg.period_duration, cfg.ot_enabled, cfg.ot_duration)
		NetworkManager.pending_game_config = {}
	_spawner = ActorSpawner.new()
	_spawner.setup(get_tree().current_scene)
	_create_teams()
	goals = _spawner.find_goals()
	_assign_goals_to_teams()
	_spawn_puck()
	_spawn_goalies()
	_wire_subsystems()
	if NetworkManager.is_host:
		_connect_goal_signals()


func _create_teams() -> void:
	var t0 := Team.new()
	t0.team_id = 0
	var t1 := Team.new()
	t1.team_id = 1
	teams = [t0, t1]


func _assign_goals_to_teams() -> void:
	for goal: HockeyGoal in goals:
		# facing=+1 → positive-Z end → Team 0 defends it
		# facing=-1 → negative-Z end → Team 1 defends it
		var defending_team_id: int = 0 if goal.facing == 1 else 1
		teams[defending_team_id].defended_goal = goal
		goal.defending_team_id = defending_team_id


func _connect_goal_signals() -> void:
	for team: Team in teams:
		team.defended_goal.goal_scored.connect(func() -> void: _phase_coord.on_goal_scored_into(team))


func _spawn_puck() -> void:
	var result: Dictionary = _spawner.spawn_puck_with_controller(NetworkManager.is_host)
	puck = result.puck
	puck_controller = result.controller
	puck.set_team_resolver(_resolve_skater_team_id)
	puck_controller.set_peer_id_resolver(_resolve_skater_peer_id)
	puck_controller.puck_picked_up_by.connect(_on_server_puck_picked_up_by)
	puck_controller.puck_released_by_carrier.connect(_on_server_puck_released_by_carrier)
	puck_controller.puck_stripped_from.connect(_on_server_puck_stripped_from)
	puck_controller.puck_touched_while_loose.connect(_on_server_puck_touched_while_loose)
	puck_controller.puck_touched_by_goalie.connect(_on_puck_touched_by_goalie)


func _spawn_goalies() -> void:
	var result: Dictionary = _spawner.spawn_goalie_pair(puck, NetworkManager.is_host)
	goalies = [result.top_goalie as Goalie, result.bottom_goalie as Goalie]
	goalie_controllers = [result.top_controller, result.bottom_controller]
	teams[1].goalie_controller = result.top_controller
	teams[0].goalie_controller = result.bottom_controller
	for team_id: int in [0, 1]:
		var goalie: Goalie = result.bottom_goalie if team_id == 0 else result.top_goalie
		goalie.set_goalie_color(
			PlayerRules.generate_jersey_color(team_id),
			PlayerRules.generate_helmet_color(team_id),
			PlayerRules.generate_pads_color(team_id)
		)


func _wire_subsystems() -> void:
	_registry = PlayerRegistry.new()
	_registry.setup(_spawner, _state_machine, teams,
			get_puck, self, _on_player_spawned)
	_registry.player_joined.connect(player_joined.emit)
	_registry.player_left.connect(player_left.emit)
	_registry.player_added.connect(_on_registry_player_added)

	_codec = WorldStateCodec.new()
	_codec.setup(_registry, _state_machine,
			get_puck, _get_puck_controller, _get_goalie_controllers)
	_codec.phase_changed.connect(_on_remote_phase_changed)
	_codec.game_over_triggered.connect(game_over.emit)
	_codec.period_changed.connect(period_changed.emit)
	_codec.clock_updated.connect(_on_clock_updated_externally)
	_codec.shots_on_goal_changed.connect(shots_on_goal_changed.emit)

	_shot_tracker = ShotOnGoalTracker.new()
	_shot_tracker.setup(_registry, _state_machine)
	_shot_tracker.shots_on_goal_changed.connect(shots_on_goal_changed.emit)

	_hit_tracker = HitTracker.new()
	_hit_tracker.setup(_registry)
	_hit_tracker.hit_credited.connect(_sync_stats_to_clients)

	_phase_coord = PhaseCoordinator.new()
	_phase_coord.setup(_state_machine, _registry, teams,
			get_puck, _get_goalie_controllers, _shot_tracker, _drop_puck_if_carried)
	_phase_coord.goal_scored.connect(goal_scored.emit)
	_phase_coord.score_changed.connect(score_changed.emit)
	_phase_coord.phase_changed.connect(phase_changed.emit)
	_phase_coord.period_changed.connect(period_changed.emit)
	_phase_coord.clock_updated.connect(_on_clock_updated_externally)
	_phase_coord.game_over.connect(game_over.emit)
	_phase_coord.stats_need_sync.connect(_sync_stats_to_clients)
	_phase_coord.faceoff_positions_ready.connect(NetworkManager.send_faceoff_positions)
	_phase_coord.goal_broadcast_needed.connect(NetworkManager.notify_goal_to_all)

	_swap_coord = SlotSwapCoordinator.new()
	_swap_coord.setup(_registry, _state_machine, teams)
	_swap_coord.stats_updated.connect(stats_updated.emit)
	_swap_coord.carrier_swap_needs_drop.connect(_drop_puck_if_carried)


func _spawn_local(peer_id: int, team_slot: int, team: Team) -> void:
	var colors: Dictionary = PlayerRegistry.generate_colors(team.team_id)
	_registry.spawn(peer_id, team_slot, team,
			colors.jersey, colors.helmet, colors.pants,
			NetworkManager.local_is_left_handed, NetworkManager.local_player_name, true,
			NetworkManager.local_jersey_number)


# ── Spawn wire-up (callback invoked by PlayerRegistry after spawn) ───────────
func _on_player_spawned(record: PlayerRecord) -> void:
	if record.is_local:
		var local_ctrl: LocalController = record.controller as LocalController
		local_ctrl.set_goal_context(
				teams[0].defended_goal, teams[1].defended_goal, _resolve_skater_team_id)
		local_ctrl.puck_release_requested.connect(_on_puck_release_requested)
		NetworkManager.register_local_controller(local_ctrl)
	else:
		NetworkManager.register_remote_controller(
				record.peer_id, record.controller as RemoteController)
	record.controller.one_timer_release_requested.connect(
			_on_one_timer_release_requested.bind(record.skater))
	var pid: int = record.peer_id
	record.skater.body_checked_player.connect(
		func(v: Skater, _f: float, _d: Vector3) -> void: _on_hit_landed(pid, v)
	)


func _on_registry_player_added(_record: PlayerRecord) -> void:
	stats_updated.emit()
	if NetworkManager.is_host:
		_sync_stats_to_clients()


# ── Puck / Puck controller signal handlers ───────────────────────────────────
func _resolve_skater_team_id(skater: Skater) -> int:
	return _registry.resolve_team_id(skater) if _registry != null else -1


func _resolve_skater_peer_id(skater: Skater) -> int:
	return _registry.resolve_peer_id(skater) if _registry != null else -1


func _on_server_puck_picked_up_by(peer_id: int) -> void:
	var record: PlayerRecord = _registry.get_record(peer_id)
	if record == null:
		return
	_shot_tracker.on_pickup(peer_id)
	record.controller.on_puck_picked_up_network()
	if not record.is_local:
		NetworkManager.send_puck_picked_up(peer_id)


func _on_server_puck_released_by_carrier(peer_id: int) -> void:
	var record: PlayerRecord = _registry.get_record(peer_id)
	if record == null:
		return
	record.controller.on_puck_released_network()


func _on_server_puck_stripped_from(peer_id: int) -> void:
	var record: PlayerRecord = _registry.get_record(peer_id)
	if record == null:
		return
	_state_machine.notify_icing_contact()
	if not record.is_local:
		NetworkManager.send_puck_stolen(peer_id)


func _on_server_puck_touched_while_loose(peer_id: int) -> void:
	_state_machine.notify_icing_contact()
	_shot_tracker.on_deflection(peer_id)


func _on_puck_touched_by_goalie(goalie: Goalie) -> void:
	if not NetworkManager.is_host:
		return
	var defending_team_id: int = _defending_team_id_for_goalie(goalie)
	_shot_tracker.on_goalie_touch(defending_team_id)
	_sync_stats_to_clients()


func _defending_team_id_for_goalie(goalie: Goalie) -> int:
	for team: Team in teams:
		if team.goalie_controller != null and team.goalie_controller.goalie == goalie:
			return team.team_id
	return -1


# ── Puck release / one-timer ─────────────────────────────────────────────────
func _on_puck_release_requested(direction: Vector3, power: float) -> void:
	if NetworkManager.is_host:
		_start_pending_shot_from_carrier()
		puck.release(direction, power)
	else:
		var record := _registry.get_local()
		if record != null:
			record.controller.on_puck_released_network()
		puck_controller.notify_local_release(direction, power)
		NetworkManager.send_puck_release(direction, power)


func _on_one_timer_release_requested(direction: Vector3, power: float, skater: Skater) -> void:
	if not NetworkManager.is_host:
		return
	var pid: int = _registry.resolve_peer_id(skater)
	_shot_tracker.on_shot_started(pid)
	puck.set_carrier(skater)
	puck.release(direction, power)


func on_remote_puck_release(direction: Vector3, power: float) -> void:
	if NetworkManager.is_host:
		_start_pending_shot_from_carrier()
	puck.release(direction, power)


func _start_pending_shot_from_carrier() -> void:
	if puck == null or puck.carrier == null:
		return
	_shot_tracker.on_shot_started(_registry.resolve_peer_id(puck.carrier))


# ── Puck network events ──────────────────────────────────────────────────────
func on_carrier_puck_dropped() -> void:
	var local_record := _registry.get_local() if _registry != null else null
	if local_record != null:
		local_record.controller.on_puck_released_network()
		puck_controller.notify_local_puck_dropped()


func on_local_player_picked_up_puck() -> void:
	var record := _registry.get_local() if _registry != null else null
	if record != null:
		record.controller.on_puck_picked_up_network()
		puck_controller.notify_local_pickup(record.skater)


func on_local_player_puck_stolen() -> void:
	var local_record := _registry.get_local() if _registry != null else null
	if local_record != null:
		local_record.controller.on_puck_released_network()
		puck_controller.notify_local_puck_dropped()


# ── Goal received (client-side RPC) ──────────────────────────────────────────
func _on_goal_received(scoring_team_id: int, score0: int, score1: int,
		scorer_name: String, assist1_name: String, assist2_name: String) -> void:
	if _phase_coord == null:
		return
	_phase_coord.on_goal_received(scoring_team_id, score0, score1,
			scorer_name, assist1_name, assist2_name)


func _on_faceoff_positions_received(positions: Array) -> void:
	if _phase_coord != null:
		_phase_coord.on_faceoff_positions(positions)


# ── World state & stats RPC forwarding ───────────────────────────────────────
func _on_world_state_received(state: Array) -> void:
	if _codec != null:
		_codec.decode_world_state(state)


func _on_stats_received(data: Array) -> void:
	if _codec != null:
		_codec.decode_stats(data)
	stats_updated.emit()


func _on_remote_phase_changed(new_phase: GamePhase.Phase) -> void:
	_last_emitted_clock_secs = -1
	phase_changed.emit(new_phase)


func _on_clock_updated_externally(t: float) -> void:
	_last_emitted_clock_secs = -1
	clock_updated.emit(t)


func _sync_stats_to_clients() -> void:
	stats_updated.emit()
	if not NetworkManager.is_host or _codec == null:
		return
	NetworkManager.send_stats_to_all(_codec.encode_stats())


# ── Slot swap ─────────────────────────────────────────────────────────────────
func _on_slot_swap_requested(peer_id: int, new_team_id: int, new_slot: int) -> void:
	if not NetworkManager.is_host or _swap_coord == null:
		return
	var carrier: Skater = puck.carrier if puck != null else null
	var confirmation: Dictionary = _swap_coord.request_swap(peer_id, new_team_id, new_slot, carrier)
	if confirmation.is_empty():
		return
	NetworkManager.send_confirm_slot_swap(peer_id,
			confirmation.old_team_id, confirmation.old_slot,
			confirmation.new_team_id, confirmation.new_slot,
			confirmation.jersey, confirmation.helmet, confirmation.pants)


func _on_slot_swap_confirmed(peer_id: int, old_team_id: int, old_slot: int,
		new_team_id: int, new_slot: int,
		jersey: Color, helmet: Color, pants: Color) -> void:
	if _swap_coord != null:
		_swap_coord.apply_confirmed_swap(peer_id, old_team_id, old_slot,
				new_team_id, new_slot, jersey, helmet, pants)


# ── Hit tracking ─────────────────────────────────────────────────────────────
func _on_hit_landed(hitter_peer_id: int, victim: Skater) -> void:
	if not NetworkManager.is_host:
		return
	_hit_tracker.on_hit(hitter_peer_id, _registry.resolve_team_id(victim))


# ── Scene exit & reset ───────────────────────────────────────────────────────
func on_scene_exit() -> void:
	set_input_blocked(false)
	if _shot_tracker != null:
		_shot_tracker.clear_state()
	if _registry != null:
		_registry.clear_state()
	_state_machine = null
	_spawner = null
	teams.clear()
	puck = null
	goals.clear()
	goalies.clear()
	goalie_controllers.clear()
	puck_controller = null
	_registry = null
	_codec = null
	_shot_tracker = null
	_phase_coord = null
	_swap_coord = null
	_last_emitted_clock_secs = -1


func reset_game() -> void:
	_drop_puck_if_carried()
	_apply_reset()
	NetworkManager.notify_reset_to_all()
	_state_machine.begin_faceoff_prep()
	_phase_coord.handle_phase_entered()
	game_reset.emit()


func on_game_reset() -> void:
	_apply_reset()
	# Clear client-side carry state so PuckController stops pinning to blade.
	var local_record := _registry.get_local() if _registry != null else null
	if local_record != null and local_record.controller.has_puck:
		local_record.controller.on_puck_released_network()
		puck_controller.notify_local_puck_dropped()
	game_reset.emit()


func _apply_reset() -> void:
	_state_machine.reset_all()
	_last_emitted_clock_secs = -1
	score_changed.emit(0, 0)
	period_changed.emit(1)
	clock_updated.emit(_state_machine.period_duration)
	_registry.reset_all_stats()
	_shot_tracker.reset_all()
	stats_updated.emit()


# ── Return to Lobby ──────────────────────────────────────────────────────────
func return_to_lobby() -> void:
	if not NetworkManager.is_host:
		return
	_drop_puck_if_carried()
	NetworkManager.send_return_to_lobby_to_all(_build_lobby_roster_array())


func _on_return_to_lobby(_roster: Array) -> void:
	on_scene_exit()
	get_tree().change_scene_to_file(Constants.SCENE_LOBBY)


func _build_lobby_roster_array() -> Array:
	var result: Array = []
	if _registry == null:
		return result
	for peer_id: int in _registry.all():
		var r: PlayerRecord = _registry.get_record(peer_id)
		var team_id: int = r.team.team_id if r.team != null else 0
		result.append([peer_id, team_id, r.team_slot, r.player_name,
				r.is_left_handed, r.jersey_number])
	return result


func exit_to_main_menu() -> void:
	on_scene_exit()
	NetworkManager.reset()
	get_tree().change_scene_to_file(Constants.SCENE_MAIN_MENU)


# ── Helpers ──────────────────────────────────────────────────────────────────
# Drops a carried puck and notifies the remote carrier. Returns the carrier
# peer_id (-1 if no carrier). Host-only — safe to call from dead phases.
func _drop_puck_if_carried() -> int:
	if puck == null or puck.carrier == null:
		return -1
	var carrier_peer_id: int = _resolve_skater_peer_id(puck.carrier)
	puck.drop()
	if carrier_peer_id != -1 and multiplayer.get_peers().has(carrier_peer_id):
		NetworkManager.notify_puck_dropped_to_carrier(carrier_peer_id)
	return carrier_peer_id


func _push_lobby_assignments_to_clients() -> void:
	var slots: Dictionary = NetworkManager.pending_lobby_slots
	var existing: Array[Array] = _collect_existing_player_data()
	for peer_id: int in slots:
		if peer_id == 1:
			continue
		var entry: Dictionary = slots[peer_id]
		var team_id: int = entry.team_id
		var team_slot: int = entry.team_slot
		_state_machine.register_remote_assigned_player(peer_id, team_slot, team_id)
		var team: Team = teams[team_id]
		var colors: Dictionary = PlayerRegistry.generate_colors(team_id)
		var is_left: bool = entry.get("is_left_handed", true)
		var p_name: String = entry.get("player_name", "Player")
		var p_number: int = entry.get("jersey_number", 10)
		NetworkManager.send_slot_assignment(peer_id, team_slot, team_id, colors.jersey, colors.helmet, colors.pants)
		NetworkManager.send_sync_existing_players(peer_id, existing)
		NetworkManager.send_spawn_remote_skater(peer_id, team_slot, team_id, colors.jersey, colors.helmet, colors.pants, is_left, p_name, p_number)
		_registry.spawn(peer_id, team_slot, team, colors.jersey, colors.helmet, colors.pants, is_left, p_name, false, p_number)
		existing.append([peer_id, team_slot, team_id, colors.jersey, colors.helmet, colors.pants, is_left, p_name, p_number])
	NetworkManager.pending_lobby_slots = {}


func _collect_existing_player_data() -> Array[Array]:
	var existing: Array[Array] = []
	for peer_id: int in _registry.all():
		var r: PlayerRecord = _registry.get_record(peer_id)
		existing.append([peer_id, r.team_slot, r.team.team_id,
				r.jersey_color, r.helmet_color, r.pants_color,
				r.is_left_handed, r.player_name, r.jersey_number])
	return existing


# ── Getters passed as Callables to collaborators ─────────────────────────────
func _get_puck_controller() -> PuckController:
	return puck_controller


func _get_goalie_controllers() -> Array:
	return goalie_controllers


# ── World state (NetworkManager provider callback) ───────────────────────────
func get_world_state() -> Array:
	return _codec.encode_world_state() if _codec != null else []


# ── Public API consumed by controllers, HUD, camera, scoreboard ──────────────
func is_host() -> bool:
	return NetworkManager.is_host


func is_movement_locked() -> bool:
	if _state_machine == null:
		return false
	return _state_machine.is_movement_locked()


func is_input_blocked() -> bool:
	return _input_blocked


func set_input_blocked(blocked: bool) -> void:
	_input_blocked = blocked


func get_skater_team(skater: Skater) -> Team:
	return _registry.resolve_team(skater) if _registry != null else null


func get_puck() -> Puck:
	return puck


func get_goalie_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for i: int in range(goalies.size()):
		data.append({
			"position": goalies[i].global_position,
			"rotation_y": goalies[i].get_goalie_rotation_y(),
			"is_butterfly": goalie_controllers[i].is_butterfly(),
		})
	return data


func get_slot_roster() -> Array[Dictionary]:
	return _registry.get_slot_roster() if _registry != null else []


func get_local_player() -> PlayerRecord:
	return _registry.get_local() if _registry != null else null


func get_players() -> Dictionary[int, PlayerRecord]:
	if _registry == null:
		var empty: Dictionary[int, PlayerRecord] = {}
		return empty
	return _registry.all()


func get_period_duration() -> float:
	return _state_machine.period_duration if _state_machine != null else GameRules.PERIOD_DURATION


func get_num_periods() -> int:
	return _state_machine.num_periods if _state_machine != null else GameRules.NUM_PERIODS


func get_period_scores() -> Array:
	if _state_machine == null:
		return GameStateMachine._make_period_scores(GameRules.NUM_PERIODS)
	return _state_machine.period_scores


func apply_stats(data: Array) -> void:
	_on_stats_received(data)
