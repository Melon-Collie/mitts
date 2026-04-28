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
var _last_applied_idx: int = -1
var _active: bool = false

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
	_last_applied_idx = -1
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
	_codec = null
	_registry = null
	_puck = null
	_goalies = []
	_goalie_controllers = []
	replay_stopped.emit()


func _process(delta: float) -> void:
	if not _active:
		return

	_virtual_clock += delta * playback_speed
	if _virtual_clock > _clip_end_ts:
		_virtual_clock = _clip_start_ts  # loop

	NetworkManager.set_replay_clock(_virtual_clock)

	var idx: int = _find_frame_idx(_virtual_clock)
	if idx < 0 or idx == _last_applied_idx:
		return
	_last_applied_idx = idx

	var snapshot: Dictionary = _codec.decode_for_replay(_frames[idx])
	if snapshot.is_empty():
		return
	_apply_snapshot_to_actors(snapshot)


func _find_frame_idx(t: float) -> int:
	var best: int = -1
	for i: int in _timestamps.size():
		if _timestamps[i] <= t:
			best = i
		else:
			break
	return best


func _apply_snapshot_to_actors(snapshot: Dictionary) -> void:
	# Skaters: route through controllers' apply_network_state. LocalController
	# and RemoteController both implement it and update Skater visuals/IK.
	var skater_states: Dictionary = snapshot.skaters
	for peer_id: int in skater_states:
		var record: PlayerRecord = _registry.get_record(peer_id)
		if record == null or record.controller == null:
			continue
		record.controller.apply_network_state(skater_states[peer_id], _virtual_clock)

	# Puck: bypass PuckController (its apply_state is a no-op on host) and
	# position the rigid body directly. Body stays frozen for the duration.
	if _puck != null and snapshot.puck != null:
		var ps: PuckNetworkState = snapshot.puck
		_puck.set_puck_position(ps.position)
		_puck.set_puck_velocity(Vector3.ZERO)

	# Goalies: same reasoning — GoalieController.apply_state is a no-op on host,
	# so position the Goalie nodes directly.
	var goalie_states: Array = snapshot.goalies
	for i: int in goalie_states.size():
		if i >= _goalies.size():
			break
		var gs: GoalieNetworkState = goalie_states[i]
		_goalies[i].set_goalie_position(gs.position_x, gs.position_z)
		_goalies[i].set_goalie_rotation_y(gs.rotation_y)


func _freeze_live_simulation() -> void:
	if _puck != null:
		_puck.freeze = true
	_saved_goalie_processing.clear()
	for gc: GoalieController in _goalie_controllers:
		_saved_goalie_processing.append(gc.is_physics_processing())
		gc.set_physics_process(false)


func _unfreeze_live_simulation() -> void:
	# puck.freeze is intentionally not restored: the FACEOFF_PREP transition
	# that triggers stop() runs puck.reset() first, which unconditionally sets
	# freeze=false. Restoring a saved value here could re-freeze the puck.
	if _puck != null:
		_puck.freeze = false
	for i: int in _goalie_controllers.size():
		var was_processing: bool = _saved_goalie_processing[i] if i < _saved_goalie_processing.size() else true
		_goalie_controllers[i].set_physics_process(was_processing)
	_saved_goalie_processing.clear()
