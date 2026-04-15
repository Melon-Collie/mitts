extends Node

# PackedScene constants moved to ActorSpawner. This file now owns only game
# orchestration: state machine ownership, player registry, network event
# routing, signal emission.

# ── Signals ───────────────────────────────────────────────────────────────────
signal goal_scored(scoring_team: Team)
signal score_changed(score_0: int, score_1: int)
signal phase_changed(new_phase: GamePhase.Phase)
signal period_changed(new_period: int)
signal clock_updated(time_remaining: float)
signal game_over()

# ── Domain state ──────────────────────────────────────────────────────────────
# GameStateMachine owns phase/timer, scores, player slot registry, icing state,
# and ghost computation. Exists on both host and client; host drives it via
# tick(), clients sync it via apply_remote_state().
var _state_machine: GameStateMachine = null
var _last_emitted_clock_secs: int = -1

# ── Infrastructure ────────────────────────────────────────────────────────────
var _spawner: ActorSpawner = null
var teams: Array[Team] = []
var puck: Puck = null
var goals: Array[HockeyGoal] = []
var goalies: Array = []
var goalie_controllers: Array[GoalieController] = []
var players: Dictionary = {}  # peer_id -> PlayerRecord (with Skater/Controller refs)
var puck_controller: PuckController = null

func _ready() -> void:
	pass

# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not NetworkManager.is_host or _state_machine == null:
		return
	if _state_machine.tick(delta):
		_handle_phase_entered()
	if _state_machine.current_phase == GamePhase.Phase.PLAYING:
		var secs: int = int(_state_machine.time_remaining)
		if secs != _last_emitted_clock_secs:
			_last_emitted_clock_secs = secs
			clock_updated.emit(_state_machine.time_remaining)

# ── Ghost State (Host) ────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not NetworkManager.is_host or puck == null or _state_machine == null:
		return
	_update_host_puck_tracking()
	_apply_ghost_state()

func _update_host_puck_tracking() -> void:
	if puck.carrier != null:
		var carrier_team: Team = get_skater_team(puck.carrier)
		if carrier_team != null:
			_state_machine.notify_puck_carried(carrier_team.team_id, puck.carrier.global_position.z)
	elif _state_machine.current_phase == GamePhase.Phase.PLAYING:
		var positions: Dictionary = {}
		for peer_id: int in players:
			positions[peer_id] = players[peer_id].skater.global_position
		_state_machine.check_icing_for_loose_puck(puck.global_position.z, positions)

func _apply_ghost_state() -> void:
	var positions: Dictionary = {}
	var carrier_peer_id: int = -1
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		positions[peer_id] = record.skater.global_position
		if puck.carrier != null and record.skater == puck.carrier:
			carrier_peer_id = peer_id
	var ghosts: Dictionary = _state_machine.compute_ghost_state(
			positions, carrier_peer_id, puck.global_position)
	for peer_id in ghosts:
		if players.has(peer_id):
			players[peer_id].skater.set_ghost(ghosts[peer_id])

# ── Network Callbacks ─────────────────────────────────────────────────────────
func on_host_started() -> void:
	_spawn_world()
	var assignment: Dictionary = _state_machine.register_host(1)
	var team: Team = teams[assignment.team_id]
	var colors: Dictionary = _generate_player_colors(team.team_id)
	_spawn_local_player(1, assignment.slot, team, colors.primary, colors.secondary)

func on_connected_to_server() -> void:
	pass

func on_slot_assigned(slot: int, team_id: int, primary_color: Color, secondary_color: Color) -> void:
	_spawn_world()
	var peer_id: int = multiplayer.get_unique_id()
	_state_machine.register_remote_assigned_player(peer_id, slot, team_id)
	_spawn_local_player(peer_id, slot, teams[team_id], primary_color, secondary_color)

func on_player_connected(peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	var assignment: Dictionary = _state_machine.on_player_connected(peer_id)
	var team: Team = teams[assignment.team_id]
	var colors: Dictionary = _generate_player_colors(team.team_id)

	NetworkManager.send_slot_assignment(peer_id, assignment.slot, team.team_id, colors.primary, colors.secondary)

	var existing: Array = []
	for existing_peer_id in players:
		var r: PlayerRecord = players[existing_peer_id]
		existing.append([existing_peer_id, r.slot, r.team.team_id, r.color, r.secondary_color])
	NetworkManager.send_sync_existing_players(peer_id, existing)

	NetworkManager.send_spawn_remote_skater(peer_id, assignment.slot, team.team_id, colors.primary, colors.secondary)

	_spawn_remote_player(peer_id, assignment.slot, team, colors.primary, colors.secondary)

func on_player_disconnected(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var record: PlayerRecord = players[peer_id]
	# Drop the puck before freeing the controller so puck_released fires while the
	# record is still intact (puck_controller._on_puck_released checks players dict).
	if NetworkManager.is_host and puck != null and puck.carrier == record.skater:
		puck.drop()
	players.erase(peer_id)
	if _state_machine != null:
		_state_machine.on_player_disconnected(peer_id)
	NetworkManager.unregister_remote_controller(peer_id)
	if record.controller:
		record.controller.queue_free()
	if record.skater:
		record.skater.queue_free()

func sync_existing_players(player_data: Array) -> void:
	for entry in player_data:
		var peer_id: int = entry[0]
		var slot: int = entry[1]
		var team_id: int = entry[2]
		var primary_color: Color = entry[3]
		var secondary_color: Color = entry[4]
		_state_machine.register_remote_assigned_player(peer_id, slot, team_id)
		_spawn_remote_player(peer_id, slot, teams[team_id], primary_color, secondary_color)

func spawn_remote_skater(peer_id: int, slot: int, team_id: int, primary_color: Color, secondary_color: Color) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	_state_machine.register_remote_assigned_player(peer_id, slot, team_id)
	_spawn_remote_player(peer_id, slot, teams[team_id], primary_color, secondary_color)

# ── Goal Event (called on all peers via RPC) ─────────────────────────────────
func on_goal_scored(scoring_team_id: int, score0: int, score1: int) -> void:
	_state_machine.apply_remote_goal(scoring_team_id, score0, score1)
	var scoring_team: Team = teams[scoring_team_id]
	puck.pickup_locked = true
	goal_scored.emit(scoring_team)
	score_changed.emit(_state_machine.scores[0], _state_machine.scores[1])
	phase_changed.emit(_state_machine.current_phase)

func on_carrier_puck_dropped() -> void:
	var local_record := get_local_player()
	if local_record != null:
		local_record.controller.on_puck_released_network()
		puck_controller.notify_local_puck_dropped()

func on_faceoff_positions(positions: Array) -> void:
	var local_peer_id: int = multiplayer.get_unique_id()
	var i: int = 0
	while i < positions.size():
		var peer_id: int = positions[i]
		var pos := Vector3(positions[i + 1], positions[i + 2], positions[i + 3])
		i += 4
		if peer_id == local_peer_id and players.has(peer_id):
			players[peer_id].controller.teleport_to(pos)

# ── World Spawn ───────────────────────────────────────────────────────────────
func _spawn_world() -> void:
	_state_machine = GameStateMachine.new()
	_spawner = ActorSpawner.new()
	_spawner.setup(get_tree().current_scene)
	_create_teams()
	goals = _spawner.find_goals()
	_assign_goals_to_teams()
	_spawn_puck()
	_spawn_goalies()
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

func _connect_goal_signals() -> void:
	for team: Team in teams:
		team.defended_goal.goal_scored.connect(func(): _on_goal_scored_into(team))

func _spawn_puck() -> void:
	var result: Dictionary = _spawner.spawn_puck_with_controller(NetworkManager.is_host)
	puck = result.puck
	puck_controller = result.controller
	# Wire resolvers and server signals — game-orchestration concerns.
	puck.set_team_resolver(_resolve_skater_team_id)
	puck_controller.set_peer_id_resolver(_resolve_skater_peer_id)
	puck_controller.puck_picked_up_by.connect(_on_server_puck_picked_up_by)
	puck_controller.puck_released_by_carrier.connect(_on_server_puck_released_by_carrier)
	puck_controller.puck_stripped_from.connect(_on_server_puck_stripped_from)
	puck_controller.puck_touched_while_loose.connect(_on_server_puck_touched_while_loose)

func _spawn_goalies() -> void:
	var result: Dictionary = _spawner.spawn_goalie_pair(puck, NetworkManager.is_host)
	goalies = [result.top_goalie, result.bottom_goalie]
	goalie_controllers = [result.top_controller, result.bottom_controller]
	# top goalie (negative-Z) defends Team 1's end; bottom (positive-Z) defends Team 0's.
	teams[1].goalie_controller = result.top_controller
	teams[0].goalie_controller = result.bottom_controller

func _spawn_local_player(peer_id: int, slot: int, team: Team, primary_color: Color, secondary_color: Color) -> void:
	var record := PlayerRecord.new(peer_id, slot, true, team)
	record.color = primary_color
	record.secondary_color = secondary_color
	var faceoff_pos: Vector3 = PlayerRules.faceoff_position_for_slot(slot)
	record.faceoff_position = faceoff_pos
	var spawned: Dictionary = _spawner.spawn_local_player(faceoff_pos, primary_color, secondary_color, puck, self, team.team_id)
	record.skater = spawned.skater
	record.controller = spawned.controller
	spawned.controller.puck_release_requested.connect(_on_puck_release_requested)
	players[peer_id] = record
	NetworkManager.register_local_controller(spawned.controller)

func _spawn_remote_player(peer_id: int, slot: int, team: Team, primary_color: Color, secondary_color: Color) -> void:
	var record := PlayerRecord.new(peer_id, slot, false, team)
	record.color = primary_color
	record.secondary_color = secondary_color
	var faceoff_pos: Vector3 = PlayerRules.faceoff_position_for_slot(slot)
	record.faceoff_position = faceoff_pos
	var spawned: Dictionary = _spawner.spawn_remote_player(faceoff_pos, primary_color, secondary_color, puck, self)
	record.skater = spawned.skater
	record.controller = spawned.controller
	players[peer_id] = record
	NetworkManager.register_remote_controller(peer_id, spawned.controller)

# ── Resolvers (injected into Puck / PuckController) ──────────────────────────
func _resolve_skater_team_id(skater: Skater) -> int:
	var team: Team = get_skater_team(skater)
	return team.team_id if team != null else -1

func _resolve_skater_peer_id(skater: Skater) -> int:
	for peer_id: int in players:
		if players[peer_id].skater == skater:
			return peer_id
	return -1

# ── PuckController server-signal handlers (host only — clients never wire these)
func _on_server_puck_picked_up_by(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var record: PlayerRecord = players[peer_id]
	record.controller.on_puck_picked_up_network()
	if not record.is_local:
		NetworkManager.send_puck_picked_up(peer_id)

func _on_server_puck_released_by_carrier(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	players[peer_id].controller.on_puck_released_network()

func _on_server_puck_stripped_from(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	_state_machine.notify_icing_contact()
	if not players[peer_id].is_local:
		NetworkManager.send_puck_stolen(peer_id)

func _on_server_puck_touched_while_loose() -> void:
	_state_machine.notify_icing_contact()

# ── Goal Scoring (host) ───────────────────────────────────────────────────────
func _on_goal_scored_into(defending_team: Team) -> void:
	# Drop a carried puck immediately so carrier state and puck physics are clean
	# before the pause. Without this, puck._physics_process (240Hz) would keep
	# pinning the puck to the blade while the FSM waits for the pause to end.
	var carrier_peer_id: int = -1
	if puck.carrier != null:
		carrier_peer_id = _resolve_skater_peer_id(puck.carrier)
		puck.drop()
	var scoring_team_id: int = _state_machine.on_goal_scored(defending_team.team_id)
	if scoring_team_id == -1:
		return  # wrong phase, ignored
	puck.pickup_locked = true
	goal_scored.emit(teams[scoring_team_id])
	score_changed.emit(_state_machine.scores[0], _state_machine.scores[1])
	phase_changed.emit(_state_machine.current_phase)
	NetworkManager.notify_goal_to_all(
			scoring_team_id, _state_machine.scores[0], _state_machine.scores[1])
	if carrier_peer_id != -1 and multiplayer.get_peers().has(carrier_peer_id):
		NetworkManager.notify_puck_dropped_to_carrier(carrier_peer_id)

# ── Phase Entry (host, after tick transition) ─────────────────────────────────
func _handle_phase_entered() -> void:
	match _state_machine.current_phase:
		GamePhase.Phase.FACEOFF_PREP:
			period_changed.emit(_state_machine.current_period)
			_last_emitted_clock_secs = -1
			clock_updated.emit(_state_machine.time_remaining)
			_enter_faceoff_prep()
		GamePhase.Phase.FACEOFF:
			_enter_faceoff()
		GamePhase.Phase.PLAYING:
			# Transition from FACEOFF timeout — unlock puck
			puck.pickup_locked = false
		GamePhase.Phase.END_OF_PERIOD:
			puck.pickup_locked = true
		GamePhase.Phase.GAME_OVER:
			puck.pickup_locked = true
			game_over.emit()
	phase_changed.emit(_state_machine.current_phase)

func _enter_faceoff_prep() -> void:
	puck.reset()
	puck.pickup_locked = true
	for gc: GoalieController in goalie_controllers:
		gc.reset_to_crease()
	var positions: Array = []
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		var pos: Vector3 = PlayerRules.faceoff_position_for_slot(record.slot)
		record.faceoff_position = pos
		record.controller.teleport_to(pos)
		positions.append_array([peer_id, pos.x, pos.y, pos.z])
	NetworkManager.send_faceoff_positions(positions)

func _enter_faceoff() -> void:
	puck.pickup_locked = false
	if not puck.puck_picked_up.is_connected(_on_faceoff_puck_picked_up):
		puck.puck_picked_up.connect(_on_faceoff_puck_picked_up, CONNECT_ONE_SHOT)

func _on_faceoff_puck_picked_up(_carrier: Skater) -> void:
	if _state_machine.on_faceoff_puck_picked_up():
		phase_changed.emit(_state_machine.current_phase)

# ── Reset ─────────────────────────────────────────────────────────────────────
func reset_game() -> void:
	_state_machine.reset_all()
	_last_emitted_clock_secs = -1
	score_changed.emit(0, 0)
	period_changed.emit(1)
	clock_updated.emit(GameRules.PERIOD_DURATION)
	NetworkManager.notify_reset_to_all()
	# begin_faceoff_prep() transitions the state machine; _handle_phase_entered()
	# dispatches to _enter_faceoff_prep() and emits phase_changed.
	_state_machine.begin_faceoff_prep()
	_handle_phase_entered()

func on_game_reset() -> void:
	_state_machine.reset_all()
	score_changed.emit(0, 0)
	period_changed.emit(1)
	clock_updated.emit(GameRules.PERIOD_DURATION)

# ── Helpers ───────────────────────────────────────────────────────────────────
func _generate_player_colors(team_id: int) -> Dictionary:
	var existing: int = 0
	for pid: int in players:
		if players[pid].team.team_id == team_id:
			existing += 1
	var jitter: float = randf_range(-1.0, 1.0)
	return {
		"primary": PlayerRules.generate_primary_color(team_id, existing, jitter),
		"secondary": PlayerRules.generate_secondary_color(team_id, existing, jitter),
	}

# ── World State ───────────────────────────────────────────────────────────────
func get_world_state() -> Array:
	var state: Array = []
	for peer_id in players:
		var record: PlayerRecord = players[peer_id]
		state.append(peer_id)
		state.append(record.controller.get_network_state())
	state.append_array(puck_controller.get_state())
	for gc: GoalieController in goalie_controllers:
		state.append_array(gc.get_state())
	state.append(_state_machine.scores[0])
	state.append(_state_machine.scores[1])
	state.append(_state_machine.current_phase)
	state.append(_state_machine.current_period)
	state.append(int(ceil(_state_machine.time_remaining)))
	return state

func apply_world_state(state: Array) -> void:
	const GOALIE_STATE_SIZE: int = 5
	const PUCK_STATE_SIZE: int = 3
	const GAME_STATE_SIZE: int = 5  # score0, score1, phase, period, time_remaining
	var game_state_offset: int = state.size() - GAME_STATE_SIZE
	var goalie_offset: int = game_state_offset - goalie_controllers.size() * GOALIE_STATE_SIZE
	var puck_offset: int = goalie_offset - PUCK_STATE_SIZE
	_apply_skater_states(state, puck_offset)
	_apply_puck_state(state, puck_offset)
	_apply_goalie_states(state, goalie_offset, GOALIE_STATE_SIZE)
	_apply_game_state(state, game_state_offset)

func _apply_skater_states(state: Array, end: int) -> void:
	var i: int = 0
	while i < end:
		var peer_id: int = state[i]
		var skater_state: Array = state[i + 1]
		i += 2
		if not players.has(peer_id):
			continue
		var record: PlayerRecord = players[peer_id]
		var skater_network_state := SkaterNetworkState.from_array(skater_state)
		if record.is_local:
			(record.controller as LocalController).reconcile(skater_network_state)
		else:
			record.controller.apply_network_state(skater_network_state)

func _apply_puck_state(state: Array, offset: int) -> void:
	if puck_controller == null:
		return
	var puck_state := PuckNetworkState.from_array(state.slice(offset, offset + 3))
	puck_controller.apply_state(puck_state)

func _apply_goalie_states(state: Array, offset: int, stride: int) -> void:
	for gi: int in range(goalie_controllers.size()):
		var start: int = offset + gi * stride
		var goalie_net_state := GoalieNetworkState.from_array(state.slice(start, start + stride))
		goalie_controllers[gi].apply_state(goalie_net_state)

func _apply_game_state(state: Array, offset: int) -> void:
	var score0: int                = state[offset]
	var score1: int                = state[offset + 1]
	var new_phase: GamePhase.Phase = state[offset + 2] as GamePhase.Phase
	var period: int                = state[offset + 3]
	var t_remaining: float         = float(state[offset + 4])
	var phase_changed_this_tick: bool = _state_machine.apply_remote_state(
			score0, score1, new_phase, period, t_remaining)
	if phase_changed_this_tick:
		puck.pickup_locked = PhaseRules.is_dead_puck_phase(new_phase)
		phase_changed.emit(new_phase)
	period_changed.emit(period)
	clock_updated.emit(t_remaining)

# Instance methods consumed by controllers via setup() injection. Controllers
# take `game_state: Node` (expected to be this GameManager) and call these
# directly — no more static reach-ins.
func is_host() -> bool:
	return NetworkManager.is_host

func is_movement_locked() -> bool:
	if _state_machine == null:
		return false
	return _state_machine.is_movement_locked()

func get_skater_team(skater: Skater) -> Team:
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		if record.skater == skater:
			return record.team
	return null

# ── Accessors ─────────────────────────────────────────────────────────────────
func get_puck() -> Puck:
	return puck

func get_local_player() -> PlayerRecord:
	for peer_id in players:
		if players[peer_id].is_local:
			return players[peer_id]
	return null

func on_local_player_picked_up_puck() -> void:
	var record := get_local_player()
	if record != null:
		record.controller.on_puck_picked_up_network()
		puck_controller.notify_local_pickup(record.skater)

func on_local_player_puck_stolen() -> void:
	var local_record := get_local_player()
	if local_record != null:
		local_record.controller.on_puck_released_network()
		puck_controller.notify_local_puck_dropped()

func _on_puck_release_requested(direction: Vector3, power: float) -> void:
	if NetworkManager.is_host:
		puck.release(direction, power)
	else:
		var record := get_local_player()
		if record != null:
			record.controller.on_puck_released_network()
		puck_controller.notify_local_release(direction, power)
		NetworkManager.send_puck_release(direction, power)
