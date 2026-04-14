extends Node

# ── Scenes ────────────────────────────────────────────────────────────────────
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const GOALIE_SCENE: PackedScene = preload("res://Scenes/Goalie.tscn")
const LOCAL_CONTROLLER_SCENE: PackedScene = preload("res://Scenes/LocalController.tscn")
const REMOTE_CONTROLLER_SCENE: PackedScene = preload("res://Scenes/RemoteController.tscn")

# ── Game Phase ────────────────────────────────────────────────────────────────
# Enum now lives in Scripts/domain/state/game_phase.gd as GamePhase.Phase.

signal goal_scored(scoring_team: Team)
signal score_changed(team: Team)
signal phase_changed(new_phase: GamePhase.Phase)

# ── Game State ────────────────────────────────────────────────────────────────
var teams: Array[Team] = []
var puck: Puck = null
var goals: Array[HockeyGoal] = []
var goalies: Array = []
var goalie_controllers: Array[GoalieController] = []
var players: Dictionary = {}  # peer_id -> PlayerRecord
var _next_slot: int = 1       # host is always slot 0
var _phase: GamePhase.Phase = GamePhase.Phase.PLAYING
var _phase_timer: float = 0.0

var puck_controller: PuckController = null

# ── Ghost / Offsides / Icing ─────────────────────────────────────────────
var _last_carrier_team_id: int = -1
var _last_carrier_z: float = 0.0
var _icing_team_id: int = -1
var _icing_timer: float = 0.0

func _ready() -> void:
	pass

# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not NetworkManager.is_host:
		return
	if _phase == GamePhase.Phase.PLAYING:
		return
	_phase_timer += delta
	match _phase:
		GamePhase.Phase.GOAL_SCORED:
			if _phase_timer >= GameRules.GOAL_PAUSE_DURATION:
				_begin_faceoff_prep()
		GamePhase.Phase.FACEOFF_PREP:
			if _phase_timer >= GameRules.FACEOFF_PREP_DURATION:
				_begin_faceoff()
		GamePhase.Phase.FACEOFF:
			if _phase_timer >= GameRules.FACEOFF_TIMEOUT:
				_set_phase(GamePhase.Phase.PLAYING)
				puck.pickup_locked = false

# ── Ghost State (Host) ────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not NetworkManager.is_host:
		return
	if puck == null:
		return
	_update_ghost_state(delta)

func _update_ghost_state(delta: float) -> void:
	# Track carrier info for icing detection
	if puck.carrier != null:
		var carrier_team: Team = get_skater_team(puck.carrier)
		if carrier_team != null:
			_last_carrier_team_id = carrier_team.team_id
			_last_carrier_z = puck.carrier.global_position.z
		# Any pickup clears active icing
		if _icing_team_id != -1:
			_icing_team_id = -1
			_icing_timer = 0.0

	# Check icing during play when puck is free
	if _phase == GamePhase.Phase.PLAYING and puck.carrier == null and _icing_team_id == -1:
		_check_icing()

	# Tick icing timer
	if _icing_team_id != -1:
		_icing_timer -= delta
		if _icing_timer <= 0.0:
			_icing_team_id = -1

	# Apply ghost state to all skaters
	var is_active_play: bool = _phase == GamePhase.Phase.PLAYING or _phase == GamePhase.Phase.FACEOFF
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		var should_ghost: bool = false
		if is_active_play:
			if check_offside(record.skater, record.team, puck):
				should_ghost = true
			elif _icing_team_id == record.team.team_id:
				should_ghost = true
		record.skater.set_ghost(should_ghost)

func _check_icing() -> void:
	if _last_carrier_team_id == -1:
		return
	var puck_z: float = puck.global_position.z
	var offender: int = InfractionRules.check_icing(_last_carrier_team_id, _last_carrier_z, puck_z)
	if offender != -1:
		_icing_team_id = offender
		_icing_timer = GameRules.ICING_GHOST_DURATION
		_last_carrier_team_id = -1

# Thin wrapper around InfractionRules.is_offside for callers that have Skater/Team/Puck refs.
# Controllers and GameManager call this; the pure rule lives in InfractionRules.
static func check_offside(skater: Skater, team: Team, p: Puck) -> bool:
	if p == null:
		return false
	return InfractionRules.is_offside(
			skater.global_position.z,
			team.team_id,
			p.global_position.z,
			p.carrier == skater)

# ── Network Callbacks ─────────────────────────────────────────────────────────
func on_host_started() -> void:
	_spawn_world()
	var team: Team = _assign_team()
	var color: Color = _generate_player_color(team.team_id)
	_spawn_local_player(1, 0, team, color)

func on_connected_to_server() -> void:
	pass

func on_slot_assigned(slot: int, team_id: int, color: Color) -> void:
	_spawn_world()
	_spawn_local_player(multiplayer.get_unique_id(), slot, teams[team_id], color)

func on_player_connected(peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	var slot: int = _next_slot
	_next_slot += 1
	var team: Team = _assign_team()
	var color: Color = _generate_player_color(team.team_id)

	NetworkManager.send_slot_assignment(peer_id, slot, team.team_id, color)

	var existing: Array = []
	for existing_peer_id in players:
		var r: PlayerRecord = players[existing_peer_id]
		existing.append([existing_peer_id, r.slot, r.team.team_id, r.color])
	NetworkManager.send_sync_existing_players(peer_id, existing)

	NetworkManager.send_spawn_remote_skater(peer_id, slot, team.team_id, color)

	_spawn_remote_player(peer_id, slot, team, color)

func on_player_disconnected(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var record: PlayerRecord = players[peer_id]
	# Drop the puck before freeing the controller so puck_released fires while the
	# record is still intact (puck_controller._on_puck_released checks players dict).
	if NetworkManager.is_host and puck != null and puck.carrier == record.skater:
		puck.drop()
	players.erase(peer_id)
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
		var color: Color = entry[3]
		_spawn_remote_player(peer_id, slot, teams[team_id], color)

func spawn_remote_skater(peer_id: int, slot: int, team_id: int, color: Color) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	_spawn_remote_player(peer_id, slot, teams[team_id], color)

# ── Goal Event (called on all peers) ─────────────────────────────────────────
func on_goal_scored(scoring_team_id: int, score0: int, score1: int) -> void:
	teams[0].score = score0
	teams[1].score = score1
	var scoring_team: Team = teams[scoring_team_id]
	_set_phase(GamePhase.Phase.GOAL_SCORED)
	puck.pickup_locked = true
	# If this client was carrying the puck, clear carrier state.
	# The host drops it via puck.drop(), but puck.puck_released is only connected
	# on the host — the scoring client never receives that signal.
	var local_record := get_local_player()
	if local_record != null:
		local_record.controller.on_puck_released_network()
		puck_controller.notify_local_puck_dropped()
	goal_scored.emit(scoring_team)
	score_changed.emit(scoring_team)

func on_faceoff_positions(positions: Array) -> void:
	var local_peer_id: int = multiplayer.get_unique_id()
	var i: int = 0
	while i < positions.size():
		var peer_id: int = positions[i]
		var pos := Vector3(positions[i + 1], positions[i + 2], positions[i + 3])
		i += 4
		if peer_id == local_peer_id and players.has(peer_id):
			players[peer_id].controller.teleport_to(pos)

# ── Spawning ──────────────────────────────────────────────────────────────────
func _spawn_world() -> void:
	_create_teams()
	_find_goals()
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

func _find_goals() -> void:
	goals.clear()
	for node in get_tree().current_scene.get_children():
		if node is HockeyGoal:
			goals.append(node)
	# Sort so goals[0] is facing=-1 (negative-Z, Team 1 defends)
	# and goals[1] is facing=+1 (positive-Z, Team 0 defends).
	goals.sort_custom(func(a: HockeyGoal, b: HockeyGoal) -> bool: return a.facing < b.facing)

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
	puck = PUCK_SCENE.instantiate()
	puck.position = GameRules.PUCK_START_POS
	get_tree().current_scene.add_child(puck)
	puck_controller = PuckController.new()
	get_tree().current_scene.add_child(puck_controller)
	puck_controller.setup(puck, NetworkManager.is_host)

func _spawn_goalies() -> void:
	var top: Goalie = GOALIE_SCENE.instantiate()
	var bottom: Goalie = GOALIE_SCENE.instantiate()
	get_tree().current_scene.add_child(top)
	get_tree().current_scene.add_child(bottom)

	var top_controller := GoalieController.new()
	var bottom_controller := GoalieController.new()
	get_tree().current_scene.add_child(top_controller)
	get_tree().current_scene.add_child(bottom_controller)
	top_controller.setup(top, puck, -GameRules.GOAL_LINE_Z, NetworkManager.is_host)
	bottom_controller.setup(bottom, puck, GameRules.GOAL_LINE_Z, NetworkManager.is_host)

	goalies.append(top)
	goalies.append(bottom)
	goalie_controllers.append(top_controller)
	goalie_controllers.append(bottom_controller)

	# top goalie (negative-Z) defends Team 1's end; bottom (positive-Z) defends Team 0's.
	teams[1].goalie_controller = top_controller
	teams[0].goalie_controller = bottom_controller

func _spawn_local_player(peer_id: int, slot: int, team: Team, color: Color) -> void:
	var record := PlayerRecord.new(peer_id, slot, true, team)
	record.color = color
	var faceoff_pos: Vector3 = PlayerRules.faceoff_position_for_slot(slot)
	record.faceoff_position = faceoff_pos

	var skater: Skater = SKATER_SCENE.instantiate()
	skater.position = faceoff_pos
	get_tree().current_scene.add_child(skater)
	skater.set_player_color(color)
	record.skater = skater

	var controller: LocalController = LOCAL_CONTROLLER_SCENE.instantiate()
	get_tree().current_scene.add_child(controller)
	controller.setup(skater, puck)
	record.controller = controller

	controller.puck_release_requested.connect(_on_puck_release_requested)

	players[peer_id] = record
	NetworkManager.register_local_controller(controller)

func _spawn_remote_player(peer_id: int, slot: int, team: Team, color: Color) -> void:
	var record := PlayerRecord.new(peer_id, slot, false, team)
	record.color = color
	var faceoff_pos: Vector3 = PlayerRules.faceoff_position_for_slot(slot)
	record.faceoff_position = faceoff_pos

	var skater: Skater = SKATER_SCENE.instantiate()
	skater.position = faceoff_pos
	get_tree().current_scene.add_child(skater)
	skater.set_player_color(color)
	record.skater = skater

	var controller: RemoteController = REMOTE_CONTROLLER_SCENE.instantiate()
	get_tree().current_scene.add_child(controller)
	controller.setup(skater, puck)
	record.controller = controller

	players[peer_id] = record
	NetworkManager.register_remote_controller(peer_id, controller)

# ── Goal Scoring ──────────────────────────────────────────────────────────────
func _on_goal_scored_into(defending_team: Team) -> void:
	if _phase != GamePhase.Phase.PLAYING:
		return
	# Drop a carried puck immediately so carrier state and puck physics are clean
	# before the 2-second pause. puck._physics_process runs at 240 Hz and would
	# keep pinning the puck to the blade if we leave carrier set.
	if puck.carrier != null:
		puck.drop()
	var scoring_team: Team = _other_team(defending_team)
	scoring_team.score += 1
	_set_phase(GamePhase.Phase.GOAL_SCORED)
	puck.pickup_locked = true
	goal_scored.emit(scoring_team)
	score_changed.emit(scoring_team)
	NetworkManager.notify_goal_to_all(scoring_team.team_id, teams[0].score, teams[1].score)

# ── Faceoff ───────────────────────────────────────────────────────────────────
func _begin_faceoff_prep() -> void:
	_set_phase(GamePhase.Phase.FACEOFF_PREP)
	_icing_team_id = -1
	_icing_timer = 0.0
	_last_carrier_team_id = -1
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

func _begin_faceoff() -> void:
	_set_phase(GamePhase.Phase.FACEOFF)
	puck.pickup_locked = false
	if not puck.puck_picked_up.is_connected(_on_faceoff_puck_picked_up):
		puck.puck_picked_up.connect(_on_faceoff_puck_picked_up, CONNECT_ONE_SHOT)

func _on_faceoff_puck_picked_up(_carrier: Skater) -> void:
	if _phase == GamePhase.Phase.FACEOFF:
		_set_phase(GamePhase.Phase.PLAYING)

# ── Reset ─────────────────────────────────────────────────────────────────────
func reset_game() -> void:
	teams[0].score = 0
	teams[1].score = 0
	score_changed.emit(teams[0])
	score_changed.emit(teams[1])
	NetworkManager.notify_reset_to_all()
	_begin_faceoff_prep()

func on_game_reset() -> void:
	teams[0].score = 0
	teams[1].score = 0
	score_changed.emit(teams[0])
	score_changed.emit(teams[1])

# ── Helpers ───────────────────────────────────────────────────────────────────
func _assign_team() -> Team:
	var t0_count: int = players.values().filter(func(r: PlayerRecord) -> bool: return r.team == teams[0]).size()
	var t1_count: int = players.values().filter(func(r: PlayerRecord) -> bool: return r.team == teams[1]).size()
	return teams[PlayerRules.assign_team(t0_count, t1_count)]

func _other_team(team: Team) -> Team:
	return teams[1] if team == teams[0] else teams[0]

func _generate_player_color(team_id: int) -> Color:
	var existing: int = 0
	for pid: int in players:
		if players[pid].team.team_id == team_id:
			existing += 1
	return PlayerRules.generate_player_color(team_id, existing, randf_range(-1.0, 1.0))

func _set_phase(new_phase: GamePhase.Phase) -> void:
	_phase = new_phase
	_phase_timer = 0.0
	phase_changed.emit(new_phase)

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
	state.append(teams[0].score)
	state.append(teams[1].score)
	state.append(_phase as int)
	return state

func apply_world_state(state: Array) -> void:
	const GOALIE_STATE_SIZE: int = 5
	const PUCK_STATE_SIZE: int = 3
	const GAME_STATE_SIZE: int = 3  # score0, score1, phase
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
	teams[0].score = state[offset]
	teams[1].score = state[offset + 1]
	var new_phase: GamePhase.Phase = state[offset + 2] as GamePhase.Phase
	if new_phase != _phase:
		_phase = new_phase
		_phase_timer = 0.0
		puck.pickup_locked = PhaseRules.is_dead_puck_phase(new_phase)
		phase_changed.emit(new_phase)

# Delegators kept for backward compatibility with existing controllers/UI. The
# actual rule lives in PhaseRules (domain layer). Controllers will be updated
# in a later phase to call PhaseRules directly (or receive a game-state provider
# via setup() injection).
static func is_dead_puck_phase(phase: GamePhase.Phase) -> bool:
	return PhaseRules.is_dead_puck_phase(phase)

static func movement_locked() -> bool:
	return PhaseRules.movement_locked(GameManager._phase)

static func get_skater_team(skater: Skater) -> Team:
	for peer_id: int in GameManager.players:
		var record: PlayerRecord = GameManager.players[peer_id]
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
	puck_controller.notify_local_pickup()

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
