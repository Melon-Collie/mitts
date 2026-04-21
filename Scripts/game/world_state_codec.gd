class_name WorldStateCodec
extends RefCounted

# Handles the flat Array serialization format that `NetworkManager` ferries
# between host and clients. Pulled out of GameManager so the wire format lives
# in one place and the application layer speaks in typed network-state objects.
#
# Two wire formats are defined here:
#
# 1. World state  (20 Hz, unreliable_ordered):
#      [ws_sequence, peer_id, skater_bytes(35), queue_depth, ...,
#       puck_bytes(13), goalie0_bytes(10), goalie1_bytes(10),
#       score0, score1, phase, period, time_remaining]
#
#    Quantization layout:
#      Skater  (35 B): pos s16/s8/s16@1cm, vel 3×s16@0.1m/s,
#                      blade 3×s16@1cm, top_hand 3×s16@1cm,
#                      facing u16 (0–TAU→0–65535), upper_body_rot f32,
#                      last_processed_ts f32, flags u8 (shot_state[3:0]+ghost[4]),
#                      shot_charge u8
#      Puck    (13 B): pos s16/s8/s16@1cm, vel 3×s16@0.1m/s, carrier_peer_id s16
#      Goalie  (10 B): pos_x s16@1cm, pos_z s16@1cm, rot_y f32, state u8, fho u8
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
signal queue_depth_feedback(depth: int)

const GOALIE_STATE_SIZE: int = 1
const PUCK_STATE_SIZE: int = 1
const GAME_STATE_SIZE: int = 5  # score0, score1, phase, period, time_remaining
const STATS_PLAYER_RECORD_SIZE: int = 5  # peer_id, G, A, SOG, HITS

var _ws_sequence: int = 0
var _last_period: int = -1

var _registry: PlayerRegistry = null
var _state_machine: GameStateMachine = null
var _puck_getter: Callable = Callable()
var _puck_controller_getter: Callable = Callable()  # decode side only
var _goalie_controllers_getter: Callable = Callable()
var _state_buffer: StateBufferManager = null


func setup(
		registry: PlayerRegistry,
		state_machine: GameStateMachine,
		puck_getter: Callable,
		puck_controller_getter: Callable,
		goalie_controllers_getter: Callable,
		state_buffer: StateBufferManager) -> void:
	_registry = registry
	_state_machine = state_machine
	_puck_getter = puck_getter
	_puck_controller_getter = puck_controller_getter
	_goalie_controllers_getter = goalie_controllers_getter
	_state_buffer = state_buffer


# ── World state ──────────────────────────────────────────────────────────────

func encode_world_state() -> Array:
	if _state_buffer == null or not _state_buffer.is_ready() or _state_machine == null:
		return []
	var state: Array = [_ws_sequence]
	_ws_sequence = (_ws_sequence + 1) & 0xFFFF
	for peer_id: int in _registry.all():
		var record: PlayerRecord = _registry.get_record(peer_id)
		state.append(peer_id)
		state.append(_encode_skater_quantized(_state_buffer.latest_skater_state(peer_id)))
		var depth: int = 0
		if record != null and not record.is_local:
			depth = (record.controller as RemoteController).get_queue_depth()
		state.append(depth)
	state.append(_encode_puck_quantized(_state_buffer.latest_puck_state()))
	var goalie_count: int = _goalie_controllers_getter.call().size()
	for i: int in goalie_count:
		state.append(_encode_goalie_quantized(_state_buffer.latest_goalie_state(i)))
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
	_apply_skater_states(state, 1, puck_offset)
	_apply_puck_state(state, puck_offset)
	_apply_goalie_states(state, goalie_offset, goalie_controllers)
	_apply_game_state(state, game_state_offset)


func _apply_skater_states(state: Array, start: int, end: int) -> void:
	var i: int = start
	while i < end:
		var peer_id: int = state[i]
		var skater_bytes: PackedByteArray = state[i + 1]
		var depth: int = state[i + 2]
		i += 3
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record == null:
			continue
		var skater_network_state := _decode_skater_quantized(skater_bytes)
		if record.is_local:
			(record.controller as LocalController).reconcile(skater_network_state)
			queue_depth_feedback.emit(depth)
		else:
			record.controller.apply_network_state(skater_network_state)


func _apply_puck_state(state: Array, offset: int) -> void:
	var puck_controller: PuckController = _puck_controller_getter.call() as PuckController
	if puck_controller == null:
		return
	var puck_state := _decode_puck_quantized(state[offset] as PackedByteArray)
	puck_controller.apply_state(puck_state)


func _apply_goalie_states(state: Array, offset: int, goalie_controllers: Array) -> void:
	for gi: int in range(goalie_controllers.size()):
		var goalie_net_state := _decode_goalie_quantized(state[offset + gi] as PackedByteArray)
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
	if period != _last_period:
		_last_period = period
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


# ── Quantization helpers ──────────────────────────────────────────────────────

# Skater: 35 bytes
# Offsets: pos(0..4) vel(5..10) blade(11..16) top_hand(17..22)
#          facing(23..24) ubrot(25..28) lp_ts(29..32) flags(33) charge(34)
static func _encode_skater_quantized(s: SkaterNetworkState) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(35)
	var o: int = 0
	b.encode_s16(o, clampi(roundi(s.position.x * 100.0), -32768, 32767)); o += 2
	b.encode_s8(o, clampi(roundi(s.position.y * 100.0), -128, 127)); o += 1
	b.encode_s16(o, clampi(roundi(s.position.z * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.velocity.x * 10.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.velocity.y * 10.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.velocity.z * 10.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.blade_position.x * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.blade_position.y * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.blade_position.z * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.top_hand_position.x * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.top_hand_position.y * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.top_hand_position.z * 100.0), -32768, 32767)); o += 2
	var angle: float = atan2(s.facing.y, s.facing.x)
	if angle < 0.0:
		angle += TAU
	b.encode_u16(o, roundi(angle / TAU * 65535.0) & 0xFFFF); o += 2
	b.encode_float(o, s.upper_body_rotation_y); o += 4
	b.encode_float(o, s.last_processed_host_timestamp); o += 4
	var flags: int = (s.shot_state & 0x0F) | (0x10 if s.is_ghost else 0)
	b.encode_u8(o, flags); o += 1
	b.encode_u8(o, clampi(roundi(s.shot_charge * 255.0), 0, 255))
	return b


static func _decode_skater_quantized(b: PackedByteArray) -> SkaterNetworkState:
	var s := SkaterNetworkState.new()
	var o: int = 0
	s.position.x = b.decode_s16(o) / 100.0; o += 2
	s.position.y = b.decode_s8(o) / 100.0; o += 1
	s.position.z = b.decode_s16(o) / 100.0; o += 2
	s.velocity.x = b.decode_s16(o) / 10.0; o += 2
	s.velocity.y = b.decode_s16(o) / 10.0; o += 2
	s.velocity.z = b.decode_s16(o) / 10.0; o += 2
	s.blade_position.x = b.decode_s16(o) / 100.0; o += 2
	s.blade_position.y = b.decode_s16(o) / 100.0; o += 2
	s.blade_position.z = b.decode_s16(o) / 100.0; o += 2
	s.top_hand_position.x = b.decode_s16(o) / 100.0; o += 2
	s.top_hand_position.y = b.decode_s16(o) / 100.0; o += 2
	s.top_hand_position.z = b.decode_s16(o) / 100.0; o += 2
	var angle: float = b.decode_u16(o) / 65535.0 * TAU; o += 2
	s.facing = Vector2(cos(angle), sin(angle))
	s.upper_body_rotation_y = b.decode_float(o); o += 4
	s.last_processed_host_timestamp = b.decode_float(o); o += 4
	var flags: int = b.decode_u8(o); o += 1
	s.shot_state = flags & 0x0F
	s.is_ghost = (flags & 0x10) != 0
	s.shot_charge = b.decode_u8(o) / 255.0
	return s


# Puck: 13 bytes
# Offsets: pos(0..4) vel(5..10) carrier_peer_id(11..12)
static func _encode_puck_quantized(s: PuckNetworkState) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(13)
	var o: int = 0
	b.encode_s16(o, clampi(roundi(s.position.x * 100.0), -32768, 32767)); o += 2
	b.encode_s8(o, clampi(roundi(s.position.y * 100.0), -128, 127)); o += 1
	b.encode_s16(o, clampi(roundi(s.position.z * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.velocity.x * 10.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.velocity.y * 10.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.velocity.z * 10.0), -32768, 32767)); o += 2
	b.encode_s16(o, s.carrier_peer_id)
	return b


static func _decode_puck_quantized(b: PackedByteArray) -> PuckNetworkState:
	var s := PuckNetworkState.new()
	var o: int = 0
	s.position.x = b.decode_s16(o) / 100.0; o += 2
	s.position.y = b.decode_s8(o) / 100.0; o += 1
	s.position.z = b.decode_s16(o) / 100.0; o += 2
	s.velocity.x = b.decode_s16(o) / 10.0; o += 2
	s.velocity.y = b.decode_s16(o) / 10.0; o += 2
	s.velocity.z = b.decode_s16(o) / 10.0; o += 2
	s.carrier_peer_id = b.decode_s16(o)
	return s


# Goalie: 10 bytes
# Offsets: pos_x(0..1) pos_z(2..3) rot_y(4..7) state(8) fho(9)
static func _encode_goalie_quantized(s: GoalieNetworkState) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(10)
	var o: int = 0
	b.encode_s16(o, clampi(roundi(s.position_x * 100.0), -32768, 32767)); o += 2
	b.encode_s16(o, clampi(roundi(s.position_z * 100.0), -32768, 32767)); o += 2
	b.encode_float(o, s.rotation_y); o += 4
	b.encode_u8(o, s.state_enum); o += 1
	b.encode_u8(o, clampi(roundi(s.five_hole_openness * 255.0), 0, 255))
	return b


static func _decode_goalie_quantized(b: PackedByteArray) -> GoalieNetworkState:
	var s := GoalieNetworkState.new()
	var o: int = 0
	s.position_x = b.decode_s16(o) / 100.0; o += 2
	s.position_z = b.decode_s16(o) / 100.0; o += 2
	s.rotation_y = b.decode_float(o); o += 4
	s.state_enum = b.decode_u8(o); o += 1
	s.five_hole_openness = b.decode_u8(o) / 255.0
	return s
