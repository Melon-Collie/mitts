class_name StateBufferManager
extends RefCounted

# Host-only rolling snapshot buffer for all actors.
# Pre-allocated ring buffers avoid per-tick GC pressure at 240 Hz.
# Owned by GameManager; WorldStateCodec reads latest_*() for broadcasts.
# Phase 7 lag compensation queries get_state_at() for historical rewind.

const BUFFER_SIZE: int = 720  # 3 seconds at 240 Hz

var _skater_buffers: Dictionary = {}   # peer_id -> Array[SkaterNetworkState]
var _skater_ptrs: Dictionary = {}      # peer_id -> int
var _puck_buffer: Array = []           # Array[PuckNetworkState], BUFFER_SIZE slots
var _puck_ptr: int = 0
var _goalie_buffers: Dictionary = {}   # team_id -> Array[GoalieNetworkState]
var _goalie_ptrs: Dictionary = {}      # team_id -> int
var _capture_count: int = 0


func setup(registry: PlayerRegistry, goalie_controllers: Array) -> void:
	for peer_id: int in registry.all():
		_alloc_skater(peer_id)
	_puck_buffer.resize(BUFFER_SIZE)
	for i: int in BUFFER_SIZE:
		_puck_buffer[i] = PuckNetworkState.new()
	for gc: GoalieController in goalie_controllers:
		_alloc_goalie(gc.team_id)


func add_player(peer_id: int) -> void:
	if not _skater_buffers.has(peer_id):
		_alloc_skater(peer_id)


func remove_player(peer_id: int) -> void:
	_skater_buffers.erase(peer_id)
	_skater_ptrs.erase(peer_id)


func is_ready() -> bool:
	return _capture_count > 0


func capture(registry: PlayerRegistry, puck_controller: PuckController, goalie_controllers: Array) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0

	for peer_id: int in registry.all():
		if not _skater_buffers.has(peer_id):
			_alloc_skater(peer_id)
		var ptr: int = _skater_ptrs[peer_id]
		var slot: SkaterNetworkState = _skater_buffers[peer_id][ptr]
		var state: SkaterNetworkState = registry.get_record(peer_id).controller.get_network_state()
		slot.copy_from(state)
		slot.host_timestamp = now
		_skater_ptrs[peer_id] = (ptr + 1) % BUFFER_SIZE

	var puck_slot: PuckNetworkState = _puck_buffer[_puck_ptr]
	var puck_state: PuckNetworkState = puck_controller.get_state()
	puck_slot.copy_from(puck_state)
	puck_slot.host_timestamp = now
	_puck_ptr = (_puck_ptr + 1) % BUFFER_SIZE

	for gc: GoalieController in goalie_controllers:
		if not _goalie_buffers.has(gc.team_id):
			_alloc_goalie(gc.team_id)
		var ptr: int = _goalie_ptrs[gc.team_id]
		var slot: GoalieNetworkState = _goalie_buffers[gc.team_id][ptr]
		var state: GoalieNetworkState = gc.get_state()
		slot.copy_from(state)
		slot.host_timestamp = now
		_goalie_ptrs[gc.team_id] = (ptr + 1) % BUFFER_SIZE

	_capture_count += 1


# ── Latest state reads (used by WorldStateCodec for world state broadcast) ────

func latest_skater_state(peer_id: int) -> SkaterNetworkState:
	if not _skater_buffers.has(peer_id):
		return SkaterNetworkState.new()
	var ptr: int = (_skater_ptrs[peer_id] - 1 + BUFFER_SIZE) % BUFFER_SIZE
	return _skater_buffers[peer_id][ptr]


func latest_puck_state() -> PuckNetworkState:
	var ptr: int = (_puck_ptr - 1 + BUFFER_SIZE) % BUFFER_SIZE
	return _puck_buffer[ptr]


func latest_goalie_state(team_id: int) -> GoalieNetworkState:
	if not _goalie_buffers.has(team_id):
		return GoalieNetworkState.new()
	var ptr: int = (_goalie_ptrs[team_id] - 1 + BUFFER_SIZE) % BUFFER_SIZE
	return _goalie_buffers[team_id][ptr]


# ── Historical query (used by Phase 7 lag compensation) ──────────────────────

func get_state_at(host_timestamp: float) -> WorldSnapshot:
	var snap := WorldSnapshot.new()
	snap.host_timestamp = host_timestamp
	snap.puck_state = _interpolate_puck(host_timestamp)
	for peer_id: int in _skater_buffers:
		snap.skater_states[peer_id] = _interpolate_skater(peer_id, host_timestamp)
	for team_id: int in _goalie_buffers:
		snap.goalie_states[team_id] = _interpolate_goalie(team_id, host_timestamp)
	return snap


# ── Private helpers ───────────────────────────────────────────────────────────

func _alloc_goalie(team_id: int) -> void:
	var buf: Array = []
	buf.resize(BUFFER_SIZE)
	for i: int in BUFFER_SIZE:
		buf[i] = GoalieNetworkState.new()
	_goalie_buffers[team_id] = buf
	_goalie_ptrs[team_id] = 0


func _alloc_skater(peer_id: int) -> void:
	var buf: Array = []
	buf.resize(BUFFER_SIZE)
	for i: int in BUFFER_SIZE:
		buf[i] = SkaterNetworkState.new()
	_skater_buffers[peer_id] = buf
	_skater_ptrs[peer_id] = 0


func _interpolate_skater(peer_id: int, ts: float) -> SkaterNetworkState:
	var buf: Array = _skater_buffers[peer_id]
	var ptr: int = _skater_ptrs[peer_id]
	var bracket: Array = _find_bracket(buf, ptr, ts)
	var t: float = bracket[0]
	var from_s: SkaterNetworkState = bracket[1]
	var to_s: SkaterNetworkState = bracket[2]
	if t < 0.0:
		return to_s if to_s != null else SkaterNetworkState.new()
	var result := SkaterNetworkState.new()
	result.position = from_s.position.lerp(to_s.position, t)
	result.rotation = from_s.rotation.lerp(to_s.rotation, t)
	result.velocity = from_s.velocity.lerp(to_s.velocity, t)
	result.blade_position = from_s.blade_position.lerp(to_s.blade_position, t)
	result.top_hand_position = from_s.top_hand_position.lerp(to_s.top_hand_position, t)
	result.upper_body_rotation_y = lerpf(from_s.upper_body_rotation_y, to_s.upper_body_rotation_y, t)
	result.facing = from_s.facing.lerp(to_s.facing, t).normalized()
	result.is_ghost = to_s.is_ghost
	result.host_timestamp = ts
	return result


func _interpolate_puck(ts: float) -> PuckNetworkState:
	var bracket: Array = _find_bracket_puck(ts)
	var t: float = bracket[0]
	var from_p: PuckNetworkState = bracket[1]
	var to_p: PuckNetworkState = bracket[2]
	if t < 0.0:
		return to_p if to_p != null else PuckNetworkState.new()
	var result := PuckNetworkState.new()
	result.position = from_p.position.lerp(to_p.position, t)
	result.velocity = from_p.velocity.lerp(to_p.velocity, t)
	result.carrier_peer_id = to_p.carrier_peer_id
	result.host_timestamp = ts
	return result


func _interpolate_goalie(team_id: int, ts: float) -> GoalieNetworkState:
	var bracket: Array = _find_bracket_goalie(team_id, ts)
	var t: float = bracket[0]
	var from_g: GoalieNetworkState = bracket[1]
	var to_g: GoalieNetworkState = bracket[2]
	if t < 0.0:
		return to_g if to_g != null else GoalieNetworkState.new()
	var result := GoalieNetworkState.new()
	result.position_x = lerpf(from_g.position_x, to_g.position_x, t)
	result.position_z = lerpf(from_g.position_z, to_g.position_z, t)
	result.rotation_y = lerpf(from_g.rotation_y, to_g.rotation_y, t)
	result.state_enum = to_g.state_enum
	result.five_hole_openness = lerpf(from_g.five_hole_openness, to_g.five_hole_openness, t)
	result.host_timestamp = ts
	return result


# Returns [t, from, to]. t < 0 means no valid bracket; from may be null.
func _find_bracket(buf: Array, write_ptr: int, ts: float) -> Array:
	var newest_ptr: int = (write_ptr - 1 + BUFFER_SIZE) % BUFFER_SIZE
	var newest: SkaterNetworkState = buf[newest_ptr]
	if newest.host_timestamp == 0.0:
		return [-1.0, null, null]
	if ts >= newest.host_timestamp:
		return [-1.0, null, newest]
	var i: int = newest_ptr
	var prev: int = (i - 1 + BUFFER_SIZE) % BUFFER_SIZE
	while prev != write_ptr:
		var s: SkaterNetworkState = buf[prev]
		if s.host_timestamp == 0.0 or s.host_timestamp <= ts:
			var from_s: SkaterNetworkState = buf[prev]
			var to_s: SkaterNetworkState = buf[i]
			var dt: float = to_s.host_timestamp - from_s.host_timestamp
			if dt <= 0.0:
				return [0.0, from_s, to_s]
			return [clampf((ts - from_s.host_timestamp) / dt, 0.0, 1.0), from_s, to_s]
		i = prev
		prev = (prev - 1 + BUFFER_SIZE) % BUFFER_SIZE
	return [-1.0, null, newest]


func _find_bracket_puck(ts: float) -> Array:
	var newest_ptr: int = (_puck_ptr - 1 + BUFFER_SIZE) % BUFFER_SIZE
	var newest: PuckNetworkState = _puck_buffer[newest_ptr]
	if newest.host_timestamp == 0.0:
		return [-1.0, null, null]
	if ts >= newest.host_timestamp:
		return [-1.0, null, newest]
	var i: int = newest_ptr
	var prev: int = (i - 1 + BUFFER_SIZE) % BUFFER_SIZE
	while prev != _puck_ptr:
		var s: PuckNetworkState = _puck_buffer[prev]
		if s.host_timestamp == 0.0 or s.host_timestamp <= ts:
			var from_p: PuckNetworkState = _puck_buffer[prev]
			var to_p: PuckNetworkState = _puck_buffer[i]
			var dt: float = to_p.host_timestamp - from_p.host_timestamp
			if dt <= 0.0:
				return [0.0, from_p, to_p]
			return [clampf((ts - from_p.host_timestamp) / dt, 0.0, 1.0), from_p, to_p]
		i = prev
		prev = (prev - 1 + BUFFER_SIZE) % BUFFER_SIZE
	return [-1.0, null, newest]


func _find_bracket_goalie(team_id: int, ts: float) -> Array:
	var buf: Array = _goalie_buffers[team_id]
	var write_ptr: int = _goalie_ptrs[team_id]
	var newest_ptr: int = (write_ptr - 1 + BUFFER_SIZE) % BUFFER_SIZE
	var newest: GoalieNetworkState = buf[newest_ptr]
	if newest.host_timestamp == 0.0:
		return [-1.0, null, null]
	if ts >= newest.host_timestamp:
		return [-1.0, null, newest]
	var i: int = newest_ptr
	var prev: int = (i - 1 + BUFFER_SIZE) % BUFFER_SIZE
	while prev != write_ptr:
		var s: GoalieNetworkState = buf[prev]
		if s.host_timestamp == 0.0 or s.host_timestamp <= ts:
			var from_g: GoalieNetworkState = buf[prev]
			var to_g: GoalieNetworkState = buf[i]
			var dt: float = to_g.host_timestamp - from_g.host_timestamp
			if dt <= 0.0:
				return [0.0, from_g, to_g]
			return [clampf((ts - from_g.host_timestamp) / dt, 0.0, 1.0), from_g, to_g]
		i = prev
		prev = (prev - 1 + BUFFER_SIZE) % BUFFER_SIZE
	return [-1.0, null, newest]
