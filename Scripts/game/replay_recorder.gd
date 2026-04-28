class_name ReplayRecorder
extends RefCounted

# Shadows the host's 40 Hz world-state broadcast into a fixed-size in-memory
# circular buffer so GoalReplayDriver can extract the last N seconds on demand.
# Lives on the host only; created alongside WorldStateCodec in game_scene.gd.

const MEMORY_SIZE: int = 360  # ~9 s at 40 Hz (covers 8 s clip + 0.5 s post-goal window)

var _frames: Array[PackedByteArray]
var _timestamps: Array[float]
var _ptr: int = 0
var _count: int = 0


func setup() -> void:
	_frames.resize(MEMORY_SIZE)
	_timestamps.resize(MEMORY_SIZE)
	for i: int in MEMORY_SIZE:
		_frames[i] = PackedByteArray()
		_timestamps[i] = 0.0
	_ptr = 0
	_count = 0


func record_frame(data: PackedByteArray, host_ts: float) -> void:
	_frames[_ptr] = data.duplicate()
	_timestamps[_ptr] = host_ts
	_ptr = (_ptr + 1) % MEMORY_SIZE
	_count = mini(_count + 1, MEMORY_SIZE)


# Returns { frames: Array[PackedByteArray], timestamps: Array[float] } in
# chronological order covering the last `duration_secs` seconds.
# If fewer frames are available the full buffer is returned without error.
func extract_clip(duration_secs: float) -> Dictionary:
	if _count == 0:
		return {frames = [] as Array[PackedByteArray], timestamps = [] as Array[float]}

	var newest_ptr: int = (_ptr - 1 + MEMORY_SIZE) % MEMORY_SIZE
	var cutoff_ts: float = _timestamps[newest_ptr] - duration_secs

	# Walk backward from newest to find how many frames fall within the window.
	var include_count: int = 0
	for i: int in _count:
		var logical_newest: int = (_ptr - 1 - i + MEMORY_SIZE * 2) % MEMORY_SIZE
		if _timestamps[logical_newest] >= cutoff_ts:
			include_count += 1
		else:
			break

	# Oldest included frame index (logical order = chronological).
	var oldest_phys: int = (_ptr - include_count + MEMORY_SIZE * 2) % MEMORY_SIZE

	var out_frames: Array[PackedByteArray] = []
	var out_timestamps: Array[float] = []
	out_frames.resize(include_count)
	out_timestamps.resize(include_count)

	for i: int in include_count:
		var phys: int = (oldest_phys + i) % MEMORY_SIZE
		out_frames[i] = _frames[phys]
		out_timestamps[i] = _timestamps[phys]

	return {frames = out_frames, timestamps = out_timestamps}
