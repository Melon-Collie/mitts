class_name GoalReplayDriver
extends Node

# Drives in-game goal replay on the HOST by:
#   1. Extracting the last CLIP_DURATION seconds from ReplayRecorder on goal.
#   2. Freezing live host physics (puck) so authoritative simulation
#      doesn't fight the replay positions.
#   3. Decoding each recorded packet into typed actor states (via the codec's
#      side-effect-free decode_for_replay) and applying them directly to the
#      Skater / Puck nodes.
#   4. Goalie controllers run freely tracking the replay puck — their AI
#      drives body-part animation naturally without needing frame-by-frame state.
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
@export var outro_duration: float = 0.25 # extra hold at clip end before stopping

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

var _outro_elapsed: float = -1.0  # >= 0 while holding the final frame
var _spectator_cam: SpectatorCamera = null


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
	_outro_elapsed = -1.0
	_active = true

	_freeze_live_simulation()

	_spectator_cam = SpectatorCamera.new()
	add_child(_spectator_cam)
	_spectator_cam.setup(func() -> Vector3: return _puck.global_position)
	_spectator_cam.activate()

	NetworkManager.start_replay_mode(_clip_start_ts)
	replay_started.emit()


func stop() -> void:
	if not _active:
		return
	_active = false
	_outro_elapsed = -1.0

	if _spectator_cam != null:
		_spectator_cam.deactivate()
		_spectator_cam.queue_free()
		_spectator_cam = null

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

	# Outro: hold the final frame for outro_duration real seconds then stop.
	if _outro_elapsed >= 0.0:
		_outro_elapsed += delta
		if _outro_elapsed >= outro_duration:
			stop()
		return

	var speed: float = slowmo_speed if (_clip_end_ts - _virtual_clock) < slowmo_window else playback_speed
	_virtual_clock += delta * speed
	if _virtual_clock >= _clip_end_ts:
		_virtual_clock = _clip_end_ts
		_outro_elapsed = 0.0

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


func _freeze_live_simulation() -> void:
	if _puck != null:
		_puck.freeze = true
	# Snap goalies to clip-start positions, then let GoalieController._physics_process
	# run freely. It reads puck.global_position, which is driven to replay positions
	# each frame, so the AI tracks the replay puck with natural body-part animation.
	if _frames.size() > 0:
		var first_snap: Dictionary = _codec.decode_for_replay(_frames[0])
		var first_goalies: Array = first_snap.goalies
		for i: int in first_goalies.size():
			if i >= _goalies.size():
				break
			var fg: GoalieNetworkState = first_goalies[i]
			_goalies[i].set_goalie_position(fg.position_x, fg.position_z)
			_goalies[i].set_goalie_rotation_y(fg.rotation_y)


func _unfreeze_live_simulation() -> void:
	# puck.freeze is intentionally not restored: after stop() the game transitions
	# to FACEOFF_PREP which calls puck.reset(), unconditionally setting freeze=false.
	# Restoring a saved value here could re-freeze the puck before reset() runs.
	if _puck != null:
		_puck.freeze = false
