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
var _goalie_buffers: Array = []        # Array of Array[GoalieNetworkState]
var _goalie_ptrs: Array = []           # Array[int]
var _capture_count: int = 0


func setup(registry: PlayerRegistry, goalie_count: int) -> void:
	for peer_id: int in registry.all():
		_alloc_skater(peer_id)
	_puck_buffer.resize(BUFFER_SIZE)
	for i: int in BUFFER_SIZE:
		_puck_buffer[i] = PuckNetworkState.new()
	_goalie_buffers.resize(goalie_count)
	_goalie_ptrs.resize(goalie_count)
	for i: int in goalie_count:
		var buf: Array = []
		buf.resize(BUFFER_SIZE)
		for j: int in BUFFER_SIZE:
			buf[j] = GoalieNetworkState.new()
		_goalie_buffers[i] = buf
		_goalie_ptrs[i] = 0


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

	for i: int in goalie_controllers.size():
		var ptr: int = _goalie_ptrs[i]
		var slot: GoalieNetworkState = _goalie_buffers[i][ptr]
		var state: GoalieNetworkState = (goalie_controllers[i] as GoalieController).get_state()
		slot.copy_from(state)
		slot.host_timestamp = now
		_goalie_ptrs[i] = (ptr + 1) % BUFFER_SIZE

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


func latest_goalie_state(index: int) -> GoalieNetworkState:
	if index >= _goalie_buffers.size():
		return GoalieNetworkState.new()
	var ptr: int = (_goalie_ptrs[index] - 1 + BUFFER_SIZE) % BUFFER_SIZE
	return _goalie_buffers[index][ptr]


# ── Historical query (used by Phase 7 lag compensation) ──────────────────────

func get_state_at(host_timestamp: float) -> WorldSnapshot:
	var snap := WorldSnapshot.new()
	snap.host_timestamp = host_timestamp
	snap.puck_state = _interpolate_puck(host_timestamp)
	for peer_id: int in _skater_buffers:
		snap.skater_states[peer_id] = _interpolate_skater(peer_id, host_timestamp)
	snap.goalie_states.resize(_goalie_buffers.size())
	for i: int in _goalie_buffers.size():
		snap.goalie_states[i] = _interpolate_goalie(i, host_timestamp)
	return snap


# ── Private helpers ───────────────────────────────────────────────────────────

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
	var from_s: SkaterNetworkState
	var to_s: SkaterNetworkState
	var t: float = _find_bracket(buf, ptr, ts, from_s, to_s)
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
	var from_s: SkaterNetworkState  # dummy — _find_bracket is generic via index
	var to_s: SkaterNetworkState
	var from_p: PuckNetworkState
	var to_p: PuckNetworkState
	var t: float = _find_bracket_puck(ts, from_p, to_p)
	if t < 0.0:
		return to_p if to_p != null else PuckNetworkState.new()
	var result := PuckNetworkState.new()
	result.position = from_p.position.lerp(to_p.position, t)
	result.velocity = from_p.velocity.lerp(to_p.velocity, t)
	result.carrier_peer_id = to_p.carrier_peer_id
	result.host_timestamp = ts
	return result


func _interpolate_goalie(index: int, ts: float) -> GoalieNetworkState:
	var from_g: GoalieNetworkState
	var to_g: GoalieNetworkState
	var t: float = _find_bracket_goalie(index, ts, from_g, to_g)
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


# Returns t in [0,1] and sets from_s/to_s. Returns -1.0 if no valid bracket.
func _find_bracket(buf: Array, write_ptr: int, ts: float, from_s: SkaterNetworkState, to_s: SkaterNetworkState) -> float:
	# Walk backwards from newest to find the two entries bracketing ts.
	var newest_ptr: int = (write_ptr - 1 + BUFFER_SIZE) % BUFFER_SIZE
	var newest: SkaterNetworkState = buf[newest_ptr]
	if newest.host_timestamp == 0.0:
		return -1.0
	if ts >= newest.host_timestamp:
		to_s = newest
		return -1.0
	var i: int = newest_ptr
	var prev: int = (i - 1 + BUFFER_SIZE) % BUFFER_SIZE
	while prev != write_ptr:
		var s: SkaterNetworkState = buf[prev]
		if s.host_timestamp == 0.0 or s.host_timestamp <= ts:
			from_s = buf[prev]
			to_s = buf[i]
			var dt: float = to_s.host_timestamp - from_s.host_timestamp
			if dt <= 0.0:
				return 0.0
			return clampf((ts - from_s.host_timestamp) / dt, 0.0, 1.0)
		i = prev
		prev = (prev - 1 + BUFFER_SIZE) % BUFFER_SIZE
	to_s = newest
	return -1.0


func _find_bracket_puck(ts: float, from_p: PuckNetworkState, to_p: PuckNetworkState) -> float:
	var newest_ptr: int = (_puck_ptr - 1 + BUFFER_SIZE) % BUFFER_SIZE
	var newest: PuckNetworkState = _puck_buffer[newest_ptr]
	if newest.host_timestamp == 0.0:
		return -1.0
	if ts >= newest.host_timestamp:
		to_p = newest
		return -1.0
	var i: int = newest_ptr
	var prev: int = (i - 1 + BUFFER_SIZE) % BUFFER_SIZE
	while prev != _puck_ptr:
		var s: PuckNetworkState = _puck_buffer[prev]
		if s.host_timestamp == 0.0 or s.host_timestamp <= ts:
			from_p = _puck_buffer[prev]
			to_p = _puck_buffer[i]
			var dt: float = to_p.host_timestamp - from_p.host_timestamp
			if dt <= 0.0:
				return 0.0
			return clampf((ts - from_p.host_timestamp) / dt, 0.0, 1.0)
		i = prev
		prev = (prev - 1 + BUFFER_SIZE) % BUFFER_SIZE
	to_p = newest
	return -1.0


func _find_bracket_goalie(index: int, ts: float, from_g: GoalieNetworkState, to_g: GoalieNetworkState) -> float:
	var buf: Array = _goalie_buffers[index]
	var write_ptr: int = _goalie_ptrs[index]
	var newest_ptr: int = (write_ptr - 1 + BUFFER_SIZE) % BUFFER_SIZE
	var newest: GoalieNetworkState = buf[newest_ptr]
	if newest.host_timestamp == 0.0:
		return -1.0
	if ts >= newest.host_timestamp:
		to_g = newest
		return -1.0
	var i: int = newest_ptr
	var prev: int = (i - 1 + BUFFER_SIZE) % BUFFER_SIZE
	while prev != write_ptr:
		var s: GoalieNetworkState = buf[prev]
		if s.host_timestamp == 0.0 or s.host_timestamp <= ts:
			from_g = buf[prev]
			to_g = buf[i]
			var dt: float = to_g.host_timestamp - from_g.host_timestamp
			if dt <= 0.0:
				return 0.0
			return clampf((ts - from_g.host_timestamp) / dt, 0.0, 1.0)
		i = prev
		prev = (prev - 1 + BUFFER_SIZE) % BUFFER_SIZE
	to_g = newest
	return -1.0
