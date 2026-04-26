class_name GoalReplayDriver
extends Node

# Drives in-game goal replay by:
#   1. Extracting the last CLIP_DURATION seconds from ReplayRecorder on goal.
#   2. Setting NetworkManager into virtual-clock mode so RemoteController,
#      PuckController, and GoalieController all interpolate against replay time.
#   3. Pumping recorded frames through WorldStateCodec.decode_world_state()
#      as the virtual clock advances, looping until FACEOFF_PREP.
#
# Owned by game_scene.gd (host only). start() / stop() called from there.

const CLIP_DURATION: float = 4.0  # seconds of history to replay

@export var playback_speed: float = 1.0

signal replay_started
signal replay_stopped

var _codec: WorldStateCodec = null
var _frames: Array[PackedByteArray] = []
var _timestamps: Array[float] = []
var _clip_start_ts: float = 0.0
var _clip_end_ts: float = 0.0
var _virtual_clock: float = 0.0
var _last_applied_idx: int = -1
var _active: bool = false


func start(recorder: ReplayRecorder, codec: WorldStateCodec) -> void:
	if _active:
		stop()

	var clip: Dictionary = recorder.extract_clip(CLIP_DURATION)
	var frames: Array[PackedByteArray] = clip.frames
	var timestamps: Array[float] = clip.timestamps

	if frames.size() < 2:
		return

	_codec = codec
	_frames = frames
	_timestamps = timestamps
	_clip_start_ts = timestamps[0]
	_clip_end_ts = timestamps[timestamps.size() - 1]
	_virtual_clock = _clip_start_ts
	_last_applied_idx = -1
	_active = true

	NetworkManager.start_replay_mode(_clip_start_ts)
	replay_started.emit()


func stop() -> void:
	if not _active:
		return
	_active = false
	NetworkManager.stop_replay_mode()
	_frames = []
	_timestamps = []
	_codec = null
	replay_stopped.emit()


func _process(delta: float) -> void:
	if not _active:
		return

	_virtual_clock += delta * playback_speed
	if _virtual_clock > _clip_end_ts:
		_virtual_clock = _clip_start_ts  # loop seamlessly

	NetworkManager.set_replay_clock(_virtual_clock)

	var idx: int = _find_frame_idx(_virtual_clock)
	if idx >= 0 and idx != _last_applied_idx:
		_last_applied_idx = idx
		_codec.decode_world_state(_frames[idx])


func _find_frame_idx(t: float) -> int:
	# Returns index of the last frame whose timestamp <= t.
	# Linear scan over ≤200 entries is negligible compared to decode cost.
	var best: int = -1
	for i: int in _timestamps.size():
		if _timestamps[i] <= t:
			best = i
		else:
			break
	return best
