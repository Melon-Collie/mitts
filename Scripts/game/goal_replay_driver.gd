class_name GoalReplayDriver
extends Node

# Drives in-game goal replay on the HOST by:
#   1. Extracting the last CLIP_DURATION seconds from ReplayRecorder on goal.
#   2. Freezing live host physics (puck, goalie AI) so authoritative simulation
#      doesn't fight the replay positions.
#   3. Decoding each recorded packet into typed actor states (via the codec's
#      side-effect-free decode_for_replay) and applying them directly to the
#      Skater / Puck / Goalie nodes.
#
# Bypasses WorldStateCodec.decode_world_state because that path mutates the
# host's GameStateMachine — replaying a packet would slam phase / score / clock
# back to whatever was captured before the goal.
#
# Owned by GameManager (host only). start() / stop() called from there.

const CLIP_DURATION: float = 4.0  # seconds of history to replay

@export var playback_speed: float = 1.0
@export var slowmo_window: float = 0.75  # seconds before clip end that slow-motion kicks in
@export var slowmo_speed: float = 0.4    # playback multiplier during slow-motion window

signal replay_started
signal replay_stopped

var _codec: WorldStateCodec = null
var _registry: PlayerRegistry = null
var _puck: Puck = null
var _goalies: Array[Goalie] = []
var _goalie_controllers: Array[GoalieController] = []

var _frames: Array[PackedByteArray] = []
var _timestamps: Array[float] = []
var _clip_start_ts: float = 0.0
var _clip_end_ts: float = 0.0
var _virtual_clock: float = 0.0
var _active: bool = false

# Bracket cache — re-decoded only when the virtual clock crosses a frame boundary.
var _cached_from_snap: Dictionary = {}
var _cached_to_snap: Dictionary = {}
var _cached_from_idx: int = -1
var _cached_to_idx: int = -1

# Snapshot of pre-replay processing flags so we can restore on stop.
var _saved_goalie_processing: Array[bool] = []


func start(recorder: ReplayRecorder,
		codec: WorldStateCodec,
		registry: PlayerRegistry,
		puck: Puck,
		goalie_controllers: Array) -> void:
	if _active:
		stop()

	var clip: Dictionary = recorder.extract_clip(CLIP_DURATION)
	var frames: Array[PackedByteArray] = clip.frames
	var timestamps: Array[float] = clip.timestamps
	if frames.size() < 2:
		return

	_codec = codec
	_registry = registry
	_puck = puck
	_goalie_controllers = []
	_goalies = []
	for gc: GoalieController in goalie_controllers:
		_goalie_controllers.append(gc)
		_goalies.append(gc.goalie)

	_frames = frames
	_timestamps = timestamps
	_clip_start_ts = timestamps[0]
	_clip_end_ts = timestamps[timestamps.size() - 1]
	_virtual_clock = _clip_start_ts
	_cached_from_idx = -1
	_cached_to_idx = -1
	_active = true

	_freeze_live_simulation()

	NetworkManager.start_replay_mode(_clip_start_ts)
	replay_started.emit()


func stop() -> void:
	if not _active:
		return
	_active = false
	NetworkManager.stop_replay_mode()
	_unfreeze_live_simulation()
	_frames = []
	_timestamps = []
	_cached_from_snap = {}
	_cached_to_snap = {}
	_cached_from_idx = -1
	_cached_to_idx = -1
	_codec = null
	_registry = null
	_puck = null
	_goalies = []
	_goalie_controllers = []
	replay_stopped.emit()


func _process(delta: float) -> void:
	if not _active:
		return

	var speed: float = slowmo_speed if (_clip_end_ts - _virtual_clock) < slowmo_window else playback_speed
	_virtual_clock += delta * speed
	if _virtual_clock > _clip_end_ts:
		stop()
		return

	NetworkManager.set_replay_clock(_virtual_clock)

	var idx: int = _find_frame_idx(_virtual_clock)
	if idx < 0:
		return
	var idx_next: int = mini(idx + 1, _frames.size() - 1)

	# Re-decode only when the bracket changes (every ~25 ms at 40 Hz).
	if idx != _cached_from_idx or idx_next != _cached_to_idx:
		_cached_from_snap = _codec.decode_for_replay(_frames[idx])
		_cached_to_snap = _codec.decode_for_replay(_frames[idx_next])
		_cached_from_idx = idx
		_cached_to_idx = idx_next

	if _cached_from_snap.is_empty():
		return

	var bracket_dt: float = _timestamps[idx_next] - _timestamps[idx]
	var t: float = clampf((_virtual_clock - _timestamps[idx]) / bracket_dt, 0.0, 1.0) \
			if bracket_dt > 0.0 else 0.0
	_apply_interpolated_snapshot(t, bracket_dt)


func _find_frame_idx(t: float) -> int:
	var best: int = -1
	for i: int in _timestamps.size():
		if _timestamps[i] <= t:
			best = i
		else:
			break
	return best


func _apply_interpolated_snapshot(t: float, dt: float) -> void:
	# Skaters: Hermite position (velocity as tangent), Hermite angle for facing
	# and upper_body_rotation, linear lerp for blade/hand (local-space, no derivative).
	var from_skaters: Dictionary = _cached_from_snap.skaters
	var to_skaters: Dictionary = _cached_to_snap.skaters
	for peer_id: int in from_skaters:
		if not to_skaters.has(peer_id):
			continue
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record == null or record.controller == null:
			continue
		var fs: SkaterNetworkState = from_skaters[peer_id]
		var ts: SkaterNetworkState = to_skaters[peer_id]
		var interp := SkaterNetworkState.new()
		interp.position = BufferedStateInterpolator.hermite(
				fs.position, fs.velocity, ts.position, ts.velocity, t, dt)
		interp.velocity = fs.velocity.lerp(ts.velocity, t)
		var fa: float = BufferedStateInterpolator.hermite_angle(
				atan2(fs.facing.x, fs.facing.y), fs.facing_angular_velocity,
				atan2(ts.facing.x, ts.facing.y), ts.facing_angular_velocity, t, dt)
		interp.facing = Vector2(sin(fa), cos(fa))
		interp.upper_body_rotation_y = BufferedStateInterpolator.hermite_angle(
				fs.upper_body_rotation_y, fs.upper_body_angular_velocity,
				ts.upper_body_rotation_y, ts.upper_body_angular_velocity, t, dt)
		interp.blade_position = fs.blade_position.lerp(ts.blade_position, t)
		interp.top_hand_position = fs.top_hand_position.lerp(ts.top_hand_position, t)
		interp.is_ghost = ts.is_ghost
		record.controller.apply_replay_state(interp)

	# Puck: Hermite position (velocity as tangent). Velocity set to zero so the
	# frozen RigidBody doesn't drift between render frames.
	var fp: PuckNetworkState = _cached_from_snap.puck
	var tp: PuckNetworkState = _cached_to_snap.puck
	if _puck != null and fp != null and tp != null:
		_puck.set_puck_position(BufferedStateInterpolator.hermite(
				fp.position, fp.velocity, tp.position, tp.velocity, t, dt))
		_puck.set_puck_velocity(Vector3.ZERO)

	# Goalies: linear lerp — they move slowly and have no angular velocity field.
	var from_goalies: Array = _cached_from_snap.goalies
	var to_goalies: Array = _cached_to_snap.goalies
	for i: int in from_goalies.size():
		if i >= _goalies.size() or i >= to_goalies.size():
			break
		var fg: GoalieNetworkState = from_goalies[i]
		var tg: GoalieNetworkState = to_goalies[i]
		_goalies[i].set_goalie_position(
				lerpf(fg.position_x, tg.position_x, t),
				lerpf(fg.position_z, tg.position_z, t))
		_goalies[i].set_goalie_rotation_y(lerp_angle(fg.rotation_y, tg.rotation_y, t))


func _freeze_live_simulation() -> void:
	if _puck != null:
		_puck.freeze = true
	_saved_goalie_processing.clear()
	for gc: GoalieController in _goalie_controllers:
		_saved_goalie_processing.append(gc.is_physics_processing())
		gc.set_physics_process(false)


func _unfreeze_live_simulation() -> void:
	# puck.freeze is intentionally not restored: after stop() the game transitions
	# to FACEOFF_PREP which calls puck.reset(), unconditionally setting freeze=false.
	# Restoring a saved value here could re-freeze the puck before reset() runs.
	if _puck != null:
		_puck.freeze = false
	for i: int in _goalie_controllers.size():
		var was_processing: bool = _saved_goalie_processing[i] if i < _saved_goalie_processing.size() else true
		_goalie_controllers[i].set_physics_process(was_processing)
	_saved_goalie_processing.clear()
