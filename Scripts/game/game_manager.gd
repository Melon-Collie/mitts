extends Node

# PackedScene constants moved to ActorSpawner. This file now owns only game
# orchestration: state machine ownership, player registry, network event
# routing, signal emission.

# ── Signals ───────────────────────────────────────────────────────────────────
signal goal_scored(scoring_team: Team, scorer_name: String)
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
# GameStateMachine owns phase/timer, scores, player slot registry, icing state,
# and ghost computation. Exists on both host and client; host drives it via
# tick(), clients sync it via apply_remote_state().
var _state_machine: GameStateMachine = null
var _last_emitted_clock_secs: int = -1
var _input_blocked: bool = false

# ── Infrastructure ────────────────────────────────────────────────────────────
var _spawner: ActorSpawner = null
var teams: Array[Team] = []
var puck: Puck = null
var goals: Array[HockeyGoal] = []
var goalies: Array = []
var goalie_controllers: Array[GoalieController] = []
var players: Dictionary = {}  # peer_id -> PlayerRecord (with Skater/Controller refs)
var puck_controller: PuckController = null

# ── Shot-on-goal tracking (host only) ────────────────────────────────────────
var _recent_carriers: Array[int] = []
var _shooter_peer_id: int = -1
var _shot_pending_time: float = -1.0
var _shot_on_goal_counted: bool = false
const SHOT_ON_GOAL_TIMEOUT: float = 5.0

func _ready() -> void:
	randomize()

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
	if _shot_pending_time >= 0.0:
		if Time.get_ticks_msec() / 1000.0 - _shot_pending_time > SHOT_ON_GOAL_TIMEOUT:
			_clear_pending_shot()

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
	_spawn_local_player(1, assignment.team_slot, team, colors.jersey, colors.helmet, colors.pants, NetworkManager.local_is_left_handed, NetworkManager.local_player_name)

func on_connected_to_server() -> void:
	pass

func on_slot_assigned(team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color) -> void:
	_spawn_world()
	var peer_id: int = multiplayer.get_unique_id()
	_state_machine.register_remote_assigned_player(peer_id, team_slot, team_id)
	_spawn_local_player(peer_id, team_slot, teams[team_id], jersey_color, helmet_color, pants_color, NetworkManager.local_is_left_handed, NetworkManager.local_player_name)

func on_player_connected(peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	var assignment: Dictionary = _state_machine.on_player_connected(peer_id)
	var team: Team = teams[assignment.team_id]
	var colors: Dictionary = _generate_player_colors(team.team_id)
	var is_left: bool = NetworkManager.get_peer_handedness(peer_id)
	var peer_name: String = NetworkManager.get_peer_name(peer_id)

	NetworkManager.send_slot_assignment(peer_id, assignment.team_slot, team.team_id, colors.jersey, colors.helmet, colors.pants)

	var existing: Array[Array] = []
	for existing_peer_id in players:
		var r: PlayerRecord = players[existing_peer_id]
		existing.append([existing_peer_id, r.team_slot, r.team.team_id, r.jersey_color, r.helmet_color, r.pants_color, r.is_left_handed, r.player_name])
	NetworkManager.send_sync_existing_players(peer_id, existing)

	NetworkManager.send_spawn_remote_skater(peer_id, assignment.team_slot, team.team_id, colors.jersey, colors.helmet, colors.pants, is_left, peer_name)

	_spawn_remote_player(peer_id, assignment.team_slot, team, colors.jersey, colors.helmet, colors.pants, is_left, peer_name)

func on_player_disconnected(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var record: PlayerRecord = players[peer_id]
	player_left.emit(record.player_name, PlayerRules.generate_primary_color(record.team.team_id))
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
		var team_slot: int = entry[1]
		var team_id: int = entry[2]
		var jersey_color: Color = entry[3]
		var helmet_color: Color = entry[4]
		var pants_color: Color = entry[5]
		var is_left: bool = entry[6] if entry.size() > 6 else true
		var p_name: String = entry[7] if entry.size() > 7 else "Player"
		_state_machine.register_remote_assigned_player(peer_id, team_slot, team_id)
		_spawn_remote_player(peer_id, team_slot, teams[team_id], jersey_color, helmet_color, pants_color, is_left, p_name)

func spawn_remote_skater(peer_id: int, team_slot: int, team_id: int, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	_state_machine.register_remote_assigned_player(peer_id, team_slot, team_id)
	_spawn_remote_player(peer_id, team_slot, teams[team_id], jersey_color, helmet_color, pants_color, is_left_handed, player_name)

# ── Goal Event (called on all peers via RPC) ─────────────────────────────────
func on_goal_scored(scoring_team_id: int, score0: int, score1: int, scorer_name: String) -> void:
	_state_machine.apply_remote_goal(scoring_team_id, score0, score1)
	var scoring_team: Team = teams[scoring_team_id]
	puck.pickup_locked = true
	goal_scored.emit(scoring_team, scorer_name)
	var defended_goal: HockeyGoal = teams[1 - scoring_team_id].defended_goal
	if defended_goal != null and defended_goal.vfx != null:
		defended_goal.vfx.celebrate()
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
		goal.defending_team_id = defending_team_id

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
	puck_controller.puck_touched_by_goalie.connect(_on_puck_touched_by_goalie)

func _spawn_goalies() -> void:
	var result: Dictionary = _spawner.spawn_goalie_pair(puck, NetworkManager.is_host)
	goalies = [result.top_goalie, result.bottom_goalie]
	goalie_controllers = [result.top_controller, result.bottom_controller]
	# top goalie (negative-Z) defends Team 1's end; bottom (positive-Z) defends Team 0's.
	teams[1].goalie_controller = result.top_controller
	teams[0].goalie_controller = result.bottom_controller

func _spawn_local_player(peer_id: int, team_slot: int, team: Team, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String) -> void:
	var record := PlayerRecord.new(peer_id, team_slot, true, team)
	record.jersey_color = jersey_color
	record.helmet_color = helmet_color
	record.pants_color = pants_color
	record.is_left_handed = is_left_handed
	record.player_name = player_name
	var faceoff_pos: Vector3 = PlayerRules.faceoff_position(team.team_id, team_slot)
	record.faceoff_position = faceoff_pos
	var spawned: Dictionary = _spawner.spawn_local_player(faceoff_pos, jersey_color, helmet_color, pants_color, is_left_handed, puck, self, team.team_id)
	record.skater = spawned.skater
	record.controller = spawned.controller
	spawned.skater.set_ring_color(PlayerRules.slot_color(team.team_id, team_slot))
	spawned.controller.set_goal_context(teams[0].defended_goal, teams[1].defended_goal, _resolve_skater_team_id)
	spawned.controller.puck_release_requested.connect(_on_puck_release_requested)
	spawned.controller.one_timer_release_requested.connect(
			_on_one_timer_release_requested.bind(spawned.skater))
	var cpid_local := peer_id
	spawned.skater.body_checked_player.connect(
		func(v: Skater, _f: float, _d: Vector3): _on_hit_landed(cpid_local, v)
	)
	players[peer_id] = record
	NetworkManager.register_local_controller(spawned.controller)
	stats_updated.emit()

func _spawn_remote_player(peer_id: int, team_slot: int, team: Team, jersey_color: Color, helmet_color: Color, pants_color: Color, is_left_handed: bool, player_name: String) -> void:
	var record := PlayerRecord.new(peer_id, team_slot, false, team)
	record.jersey_color = jersey_color
	record.helmet_color = helmet_color
	record.pants_color = pants_color
	record.is_left_handed = is_left_handed
	record.player_name = player_name
	var faceoff_pos: Vector3 = PlayerRules.faceoff_position(team.team_id, team_slot)
	record.faceoff_position = faceoff_pos
	var spawned: Dictionary = _spawner.spawn_remote_player(faceoff_pos, jersey_color, helmet_color, pants_color, is_left_handed, puck, self)
	record.skater = spawned.skater
	record.controller = spawned.controller
	spawned.skater.set_ring_color(PlayerRules.slot_color(team.team_id, team_slot))
	spawned.controller.one_timer_release_requested.connect(
			_on_one_timer_release_requested.bind(spawned.skater))
	var cpid_remote := peer_id
	spawned.skater.body_checked_player.connect(
		func(v: Skater, _f: float, _d: Vector3): _on_hit_landed(cpid_remote, v)
	)
	players[peer_id] = record
	player_joined.emit(player_name, PlayerRules.generate_primary_color(team.team_id))
	NetworkManager.register_remote_controller(peer_id, spawned.controller)
	if NetworkManager.is_host:
		_sync_stats_to_clients()

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
	_clear_pending_shot()
	if _recent_carriers.is_empty() or _recent_carriers[0] != peer_id:
		_recent_carriers.push_front(peer_id)
		if _recent_carriers.size() > 3:
			_recent_carriers.resize(3)
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
	_clear_pending_shot()

# ── Goal Scoring (host) ───────────────────────────────────────────────────────
func _on_goal_scored_into(defending_team: Team) -> void:
	var carrier_peer_id: int = _drop_puck_if_carried()
	var scoring_team_id: int = _state_machine.on_goal_scored(defending_team.team_id)
	if scoring_team_id == -1:
		return  # wrong phase, ignored
	var scorer_name: String = ""
	if NetworkManager.is_host:
		var raw_scorer_id: int = carrier_peer_id if carrier_peer_id != -1 else _shooter_peer_id
		var is_own_goal: bool = raw_scorer_id != -1 and players.has(raw_scorer_id) \
				and players[raw_scorer_id].team.team_id == defending_team.team_id
		var scorer_id: int = raw_scorer_id
		if is_own_goal:
			scorer_id = -1
			for pid: int in _recent_carriers:
				if players.has(pid) and players[pid].team.team_id == scoring_team_id:
					scorer_id = pid
					break
		if scorer_id != -1 and players.has(scorer_id):
			players[scorer_id].stats.goals += 1
			_credit_assists(scorer_id)
			if not is_own_goal:
				_confirm_shot_on_goal(scorer_id)
			var r: PlayerRecord = players[scorer_id]
			scorer_name = r.player_name if not r.player_name.is_empty() else "P%d" % (r.team_slot + 1)
		_clear_pending_shot()
		_sync_stats_to_clients()
	puck.pickup_locked = true
	if defending_team.defended_goal != null and defending_team.defended_goal.vfx != null:
		defending_team.defended_goal.vfx.celebrate()
	goal_scored.emit(teams[scoring_team_id], scorer_name)
	score_changed.emit(_state_machine.scores[0], _state_machine.scores[1])
	phase_changed.emit(_state_machine.current_phase)
	NetworkManager.notify_goal_to_all(
			scoring_team_id, _state_machine.scores[0], _state_machine.scores[1], scorer_name)

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
			_drop_puck_if_carried()
			puck.pickup_locked = true
		GamePhase.Phase.GAME_OVER:
			_drop_puck_if_carried()
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
		var pos: Vector3 = PlayerRules.faceoff_position(record.team.team_id, record.team_slot)
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

# ── Scene Exit ────────────────────────────────────────────────────────────────
func on_scene_exit() -> void:
	set_input_blocked(false)
	_state_machine = null
	_spawner = null
	teams.clear()
	puck = null
	goals.clear()
	goalies.clear()
	goalie_controllers.clear()
	players.clear()
	puck_controller = null
	_recent_carriers.clear()
	_shooter_peer_id = -1
	_shot_pending_time = -1.0
	_shot_on_goal_counted = false
	_last_emitted_clock_secs = -1

# ── Reset ─────────────────────────────────────────────────────────────────────
func reset_game() -> void:
	_drop_puck_if_carried()
	_apply_reset()
	NetworkManager.notify_reset_to_all()
	_state_machine.begin_faceoff_prep()
	_handle_phase_entered()
	game_reset.emit()

func on_game_reset() -> void:
	_apply_reset()
	# Clear client-side carry state so PuckController stops pinning puck to blade.
	var local_record := get_local_player()
	if local_record != null and local_record.controller.has_puck:
		local_record.controller.on_puck_released_network()
		puck_controller.notify_local_puck_dropped()
	game_reset.emit()

# ── Helpers ───────────────────────────────────────────────────────────────────

# Drops a carried puck, notifies the remote carrier, and returns the carrier
# peer_id (-1 if no carrier). Safe to call when puck is already loose.
func _drop_puck_if_carried() -> int:
	if puck == null or puck.carrier == null:
		return -1
	var carrier_peer_id: int = _resolve_skater_peer_id(puck.carrier)
	puck.drop()
	if carrier_peer_id != -1 and multiplayer.get_peers().has(carrier_peer_id):
		NetworkManager.notify_puck_dropped_to_carrier(carrier_peer_id)
	return carrier_peer_id

# Shared reset logic applied on both host (reset_game) and client (on_game_reset).
func _apply_reset() -> void:
	_state_machine.reset_all()
	_last_emitted_clock_secs = -1
	score_changed.emit(0, 0)
	period_changed.emit(1)
	clock_updated.emit(GameRules.PERIOD_DURATION)
	_reset_stats()

func _generate_player_colors(team_id: int) -> Dictionary:
	return {
		"jersey": PlayerRules.generate_jersey_color(team_id),
		"helmet": PlayerRules.generate_helmet_color(team_id),
		"pants": PlayerRules.generate_pants_color(team_id),
	}

# ── World State ───────────────────────────────────────────────────────────────
# Assembles the flat Array that the RPC layer transmits. Controllers return
# typed network state objects; serialization via to_array() happens here, at
# the RPC boundary.
func get_world_state() -> Array:
	var state: Array = []
	for peer_id in players:
		var record: PlayerRecord = players[peer_id]
		state.append(peer_id)
		state.append(record.controller.get_network_state().to_array())
	state.append_array(puck_controller.get_state().to_array())
	for gc: GoalieController in goalie_controllers:
		state.append_array(gc.get_state().to_array())
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
		if new_phase == GamePhase.Phase.GAME_OVER:
			game_over.emit()
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

func is_input_blocked() -> bool:
	return _input_blocked

func set_input_blocked(blocked: bool) -> void:
	_input_blocked = blocked

func get_skater_team(skater: Skater) -> Team:
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		if record.skater == skater:
			return record.team
	return null

# ── Accessors ─────────────────────────────────────────────────────────────────
func get_puck() -> Puck:
	return puck

func get_goalie_world_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for goalie: Node3D in goalies:
		positions.append(goalie.global_position)
	return positions

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
		_start_pending_shot()
		puck.release(direction, power)
	else:
		var record := get_local_player()
		if record != null:
			record.controller.on_puck_released_network()
		puck_controller.notify_local_release(direction, power)
		NetworkManager.send_puck_release(direction, power)

# One-timer leniency: player released slap just before the puck arrived.
# Acquire the puck onto the skater and immediately fire — host only.
func _on_one_timer_release_requested(direction: Vector3, power: float, skater: Skater) -> void:
	if NetworkManager.is_host:
		var pid := _resolve_skater_peer_id(skater)
		if pid != -1:
			_shooter_peer_id = pid
			_shot_pending_time = Time.get_ticks_msec() / 1000.0
		puck.set_carrier(skater)
		puck.release(direction, power)

# Called by NetworkManager when a remote client's puck release RPC arrives.
func on_remote_puck_release(direction: Vector3, power: float) -> void:
	if NetworkManager.is_host:
		_start_pending_shot()
	puck.release(direction, power)

# ── Stats (host-authoritative, synced to clients via reliable RPC) ────────────

func _start_pending_shot() -> void:
	if puck.carrier == null:
		return
	var pid: int = _resolve_skater_peer_id(puck.carrier)
	if pid == -1:
		return
	_shooter_peer_id = pid
	_shot_pending_time = Time.get_ticks_msec() / 1000.0

func _clear_pending_shot() -> void:
	_shooter_peer_id = -1
	_shot_pending_time = -1.0
	_shot_on_goal_counted = false

func _confirm_shot_on_goal(peer_id: int) -> void:
	if _shot_on_goal_counted:
		return
	if not players.has(peer_id):
		return
	_shot_on_goal_counted = true
	var record: PlayerRecord = players[peer_id]
	record.stats.shots_on_goal += 1
	_state_machine.team_shots[record.team.team_id] += 1
	shots_on_goal_changed.emit(_state_machine.team_shots[0], _state_machine.team_shots[1])

func _on_puck_touched_by_goalie(goalie: Goalie) -> void:
	if not NetworkManager.is_host:
		return
	if _shooter_peer_id == -1:
		return
	var defending_team_id: int = _get_goalie_defending_team_id(goalie)
	if defending_team_id != -1 and players.has(_shooter_peer_id):
		if players[_shooter_peer_id].team.team_id == defending_team_id:
			return  # shooter is on the defending team — own-goal attempt, no SOG
	_confirm_shot_on_goal(_shooter_peer_id)
	_shot_pending_time = -1.0  # stop timeout; keep _shooter_peer_id for goal attribution
	_sync_stats_to_clients()

func _get_goalie_defending_team_id(goalie: Goalie) -> int:
	for team: Team in teams:
		if team.goalie_controller != null and team.goalie_controller.goalie == goalie:
			return team.team_id
	return -1

func _on_hit_landed(hitter_peer_id: int, _victim: Skater) -> void:
	if not NetworkManager.is_host:
		return
	if not players.has(hitter_peer_id):
		return
	players[hitter_peer_id].stats.hits += 1
	_sync_stats_to_clients()

func _credit_assists(scorer_peer_id: int) -> void:
	var scorer_team_id: int = players[scorer_peer_id].team.team_id
	var credited: int = 0
	for i: int in range(1, _recent_carriers.size()):
		var pid: int = _recent_carriers[i]
		if not players.has(pid):
			continue
		if players[pid].team.team_id != scorer_team_id:
			break
		players[pid].stats.assists += 1
		credited += 1
		if credited >= 2:
			break

func _reset_stats() -> void:
	_recent_carriers.clear()
	_clear_pending_shot()
	for pid: int in players:
		players[pid].stats = PlayerStats.new()
	_state_machine.team_shots[0] = 0
	_state_machine.team_shots[1] = 0
	shots_on_goal_changed.emit(0, 0)
	stats_updated.emit()

func _sync_stats_to_clients() -> void:
	stats_updated.emit()
	if not NetworkManager.is_host:
		return
	var data: Array = []
	for pid: int in players:
		data.append(pid)
		data.append_array(players[pid].stats.to_array())
	data.append(_state_machine.team_shots[0])
	data.append(_state_machine.team_shots[1])
	for team_id: int in 2:
		data.append_array(_state_machine.period_scores[team_id])
	NetworkManager.send_stats_to_all(data)

func get_period_scores() -> Array:
	if _state_machine == null:
		return [[0, 0, 0], [0, 0, 0]]
	return _state_machine.period_scores

func apply_stats(data: Array) -> void:
	var i: int = 0
	while i + 4 < data.size():
		var pid: int = data[i]
		if players.has(pid):
			players[pid].stats = PlayerStats.from_array(data.slice(i + 1, i + 5))
		i += 5
	if i + 1 < data.size():
		_state_machine.team_shots[0] = data[i]
		_state_machine.team_shots[1] = data[i + 1]
		i += 2
	if i + 5 < data.size():
		for team_id: int in 2:
			for p: int in 3:
				_state_machine.period_scores[team_id][p] = data[i]
				i += 1
	shots_on_goal_changed.emit(_state_machine.team_shots[0], _state_machine.team_shots[1])
	stats_updated.emit()
