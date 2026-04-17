class_name WorldStateCodec
extends RefCounted

# Handles the flat Array serialization format that `NetworkManager` ferries
# between host and clients. Pulled out of GameManager so the wire format lives
# in one place and the application layer speaks in typed network-state objects.
#
# Two wire formats are defined here:
#
# 1. World state  (20 Hz, unreliable_ordered):
#      [peer_id, skater_state_array, ...,
#       puck_position, puck_velocity, puck_carrier_peer_id,
#       goalie0_state[5], goalie1_state[5],
#       score0, score1, phase, period, time_remaining]
#
# 2. Stats  (reliable, event-driven):
#      [pid, G, A, SOG, HITS] × N players
#      team_shots[0], team_shots[1]
#      period_scores[0][0..P-1], period_scores[1][0..P-1]
#      num_periods (trailing sentinel)
#
# Emits signals for any state-change the decode detects; GameManager relays
# them to the rest of the game.

signal phase_changed(new_phase: int)
signal game_over_triggered()
signal period_changed(period: int)
signal clock_updated(time_remaining: float)
signal shots_on_goal_changed(sog_0: int, sog_1: int)

const GOALIE_STATE_SIZE: int = 5
const PUCK_STATE_SIZE: int = 3
const GAME_STATE_SIZE: int = 5  # score0, score1, phase, period, time_remaining
const STATS_PLAYER_RECORD_SIZE: int = 5  # peer_id, G, A, SOG, HITS

var _registry: PlayerRegistry = null
var _state_machine: GameStateMachine = null
var _puck_getter: Callable = Callable()
var _puck_controller_getter: Callable = Callable()
var _goalie_controllers_getter: Callable = Callable()


func setup(
		registry: PlayerRegistry,
		state_machine: GameStateMachine,
		puck_getter: Callable,
		puck_controller_getter: Callable,
		goalie_controllers_getter: Callable) -> void:
	_registry = registry
	_state_machine = state_machine
	_puck_getter = puck_getter
	_puck_controller_getter = puck_controller_getter
	_goalie_controllers_getter = goalie_controllers_getter


# ── World state ──────────────────────────────────────────────────────────────

func encode_world_state() -> Array:
	var puck_controller: PuckController = _puck_controller_getter.call() as PuckController
	if puck_controller == null or _state_machine == null:
		return []
	var state: Array = []
	for peer_id: int in _registry.all():
		var record: PlayerRecord = _registry.get_record(peer_id)
		state.append(peer_id)
		state.append(record.controller.get_network_state().to_array())
	state.append_array(puck_controller.get_state().to_array())
	var goalie_controllers: Array = _goalie_controllers_getter.call()
	for gc: GoalieController in goalie_controllers:
		state.append_array(gc.get_state().to_array())
	state.append(_state_machine.scores[0])
	state.append(_state_machine.scores[1])
	state.append(_state_machine.current_phase)
	state.append(_state_machine.current_period)
	state.append(int(ceil(_state_machine.time_remaining)))
	return state


func decode_world_state(state: Array) -> void:
	var goalie_controllers: Array = _goalie_controllers_getter.call()
	var game_state_offset: int = state.size() - GAME_STATE_SIZE
	var goalie_offset: int = game_state_offset - goalie_controllers.size() * GOALIE_STATE_SIZE
	var puck_offset: int = goalie_offset - PUCK_STATE_SIZE
	_apply_skater_states(state, puck_offset)
	_apply_puck_state(state, puck_offset)
	_apply_goalie_states(state, goalie_offset, goalie_controllers)
	_apply_game_state(state, game_state_offset)


func _apply_skater_states(state: Array, end: int) -> void:
	var i: int = 0
	while i < end:
		var peer_id: int = state[i]
		var skater_state: Array = state[i + 1]
		i += 2
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record == null:
			continue
		var skater_network_state := SkaterNetworkState.from_array(skater_state)
		if record.is_local:
			(record.controller as LocalController).reconcile(skater_network_state)
		else:
			record.controller.apply_network_state(skater_network_state)


func _apply_puck_state(state: Array, offset: int) -> void:
	var puck_controller: PuckController = _puck_controller_getter.call() as PuckController
	if puck_controller == null:
		return
	var puck_state := PuckNetworkState.from_array(
			state.slice(offset, offset + PUCK_STATE_SIZE))
	puck_controller.apply_state(puck_state)


func _apply_goalie_states(state: Array, offset: int, goalie_controllers: Array) -> void:
	for gi: int in range(goalie_controllers.size()):
		var start: int = offset + gi * GOALIE_STATE_SIZE
		var goalie_net_state := GoalieNetworkState.from_array(
				state.slice(start, start + GOALIE_STATE_SIZE))
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
		var puck: Puck = _puck_getter.call() as Puck
		if puck != null:
			puck.pickup_locked = PhaseRules.is_dead_puck_phase(new_phase)
		if new_phase == GamePhase.Phase.GAME_OVER:
			game_over_triggered.emit()
		phase_changed.emit(new_phase)
	period_changed.emit(period)
	clock_updated.emit(t_remaining)


# ── Stats ────────────────────────────────────────────────────────────────────

func encode_stats() -> Array:
	var data: Array = []
	var players := _registry.all()
	for pid: int in players:
		data.append(pid)
		data.append_array(players[pid].stats.to_array())
	data.append(_state_machine.team_shots[0])
	data.append(_state_machine.team_shots[1])
	for team_id: int in 2:
		data.append_array(_state_machine.period_scores[team_id])
	data.append(_state_machine.period_scores[0].size())  # sentinel
	return data


func decode_stats(data: Array) -> void:
	var num_periods: int = data[-1]
	var footer_size: int = 2 + 2 * num_periods + 1  # shots×2 + scores×2P + sentinel
	var players_end: int = data.size() - footer_size
	var i: int = 0
	while i < players_end:
		var pid: int = data[i]
		var record: PlayerRecord = _registry.get_record(pid)
		if record != null:
			record.stats = PlayerStats.from_array(
					data.slice(i + 1, i + STATS_PLAYER_RECORD_SIZE))
		i += STATS_PLAYER_RECORD_SIZE
	_state_machine.team_shots[0] = data[i]
	_state_machine.team_shots[1] = data[i + 1]
	i += 2
	while _state_machine.period_scores[0].size() < num_periods:
		_state_machine.period_scores[0].append(0)
		_state_machine.period_scores[1].append(0)
	for team_id: int in 2:
		for p: int in num_periods:
			_state_machine.period_scores[team_id][p] = data[i]
			i += 1
	shots_on_goal_changed.emit(
			_state_machine.team_shots[0], _state_machine.team_shots[1])
