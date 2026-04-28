class_name FileReplayDriver
extends Node

# Scene-level driver for full-game .mreplay playback. Companion to
# GoalReplayDriver — both consume the same ReplayPlaybackEngine, but where
# GoalReplayDriver runs on the live host and freezes the simulation,
# FileReplayDriver runs in the offline ReplayViewer scene, walks an
# arbitrary virtual clock (with seek + speed control), and drives actors
# that have no networking attached.
#
# Setup expects a roster + frame list parsed from ReplayFileReader.read().
# World-state frames feed the playback engine; event frames (currently goal
# events) replay through goal_event_emitted at their host_ts so the viewer
# HUD can show goal banners + jump-to-goal buttons.

@export var playback_speed: float = 1.0

# Brackets larger than this are treated as recording gaps (e.g. host's
# goal-replay window — broadcasts pause for ~8 s). Interpolating across one
# would drift actors smoothly between the pre- and post-gap positions; instead
# we hold the FROM frame so the moment that triggered the gap lingers, then
# snap to TO when virtual_clock reaches it. Any normal-play bracket is well
# under this (40 Hz = 25 ms; 5 Hz dead-puck phase = 200 ms; jitter adds
# tens of ms on top).
const _GAP_THRESHOLD_S: float = 0.5

signal goal_event_emitted(event: Dictionary)
signal game_state_changed(game_state: Dictionary)
signal playback_ended

var _codec: WorldStateCodec = null
# peer_id → PlayerRecord; built by the viewer from the .mreplay header roster.
# Avoids the heavyweight PlayerRegistry setup (state machine + teams + spawn
# wireup) that the live game uses.
var _records: Dictionary = {}
var _puck: Puck = null
var _goalie_controllers: Array[GoalieController] = []

# Filtered frame stream — index-aligned arrays keep _find_frame_idx hot
# without the per-frame Dictionary access cost.
var _frames: Array[PackedByteArray] = []
var _timestamps: Array[float] = []
# Goal events sorted by host_ts; replayed once each as virtual_clock crosses.
var _events: Array[Dictionary] = []
var _next_event_idx: int = 0

var _virtual_clock: float = 0.0
var _start_ts: float = 0.0
var _end_ts: float = 0.0
var _paused: bool = true
var _last_emitted_game_state: Dictionary = {}

# Bracket cache — re-decoded only when virtual_clock crosses a frame boundary.
var _cached_from_snap: Dictionary = {}
var _cached_to_snap: Dictionary = {}
var _cached_from_idx: int = -1
var _cached_to_idx: int = -1
# Forward-scan hint so _find_frame_idx stays O(1) when the clock advances
# normally; reset on backward seek.
var _frame_idx_hint: int = 0


func setup(codec: WorldStateCodec,
		records: Dictionary,
		puck: Puck,
		goalie_controllers: Array,
		decoded_frames: Array) -> void:
	_codec = codec
	_records = records
	_puck = puck
	_goalie_controllers = []
	for gc: GoalieController in goalie_controllers:
		_goalie_controllers.append(gc)
	_frames.clear()
	_timestamps.clear()
	_events.clear()
	for entry: Dictionary in decoded_frames:
		var kind: int = entry.kind
		if kind == ReplayFileWriter.KIND_WORLD_STATE:
			_frames.append(entry.payload)
			_timestamps.append(entry.host_ts)
		elif kind == ReplayFileWriter.KIND_EVENT:
			var parsed: Variant = JSON.parse_string(
					(entry.payload as PackedByteArray).get_string_from_utf8())
			if parsed is Dictionary:
				_events.append({"host_ts": entry.host_ts, "data": parsed as Dictionary})
	if _frames.is_empty():
		return
	_start_ts = _timestamps[0]
	_end_ts = _timestamps[_timestamps.size() - 1]
	_virtual_clock = _start_ts
	_paused = true


# ── Playback controls ────────────────────────────────────────────────────────

func play() -> void:
	if _frames.is_empty():
		return
	if _virtual_clock >= _end_ts:
		_seek_internal(_start_ts)
	_paused = false


func pause() -> void:
	_paused = true


func toggle_pause() -> void:
	if _paused:
		play()
	else:
		pause()


func is_paused() -> bool:
	return _paused


func seek(t: float) -> void:
	_seek_internal(clampf(t, _start_ts, _end_ts))


func _seek_internal(t: float) -> void:
	if t < _virtual_clock:
		_frame_idx_hint = 0  # backward seek invalidates forward scan hint
	_virtual_clock = t
	_cached_from_idx = -1
	_cached_to_idx = -1
	_next_event_idx = _find_next_event_idx(_virtual_clock)


# ── Read accessors for the viewer HUD ────────────────────────────────────────

func get_virtual_clock() -> float:
	return _virtual_clock


func get_start_ts() -> float:
	return _start_ts


func get_end_ts() -> float:
	return _end_ts


func get_duration() -> float:
	return _end_ts - _start_ts


func get_progress() -> float:
	var dur: float = get_duration()
	return (_virtual_clock - _start_ts) / dur if dur > 0.0 else 0.0


# Goal events sorted by host_ts. Caller can build jump-to-goal buttons.
func get_events() -> Array[Dictionary]:
	return _events.duplicate()


# ── Driving ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _paused or _frames.is_empty():
		return
	_virtual_clock += delta * playback_speed
	_skip_recording_gaps()
	if _virtual_clock >= _end_ts:
		_virtual_clock = _end_ts
		_paused = true
		_apply_current_frame(delta)
		_emit_due_events()
		playback_ended.emit()
		return
	_apply_current_frame(delta)
	_emit_due_events()


# When the virtual clock would otherwise sit on a gap bracket (host paused
# broadcasting during a goal-replay cinematic, or any future broadcast
# pause), jump straight to the post-gap timestamp so the viewer doesn't
# stare at a frozen goal-moment frame for 8 wall-clock seconds. Goal
# events are still surfaced because _emit_due_events catches anything
# with host_ts <= the new virtual_clock on the next tick.
func _skip_recording_gaps() -> void:
	var idx: int = _find_frame_idx(_virtual_clock)
	if idx < 0 or idx >= _frames.size() - 1:
		return
	var bracket_dt: float = _timestamps[idx + 1] - _timestamps[idx]
	if bracket_dt <= _GAP_THRESHOLD_S:
		return
	_virtual_clock = _timestamps[idx + 1]


func _apply_current_frame(delta: float) -> void:
	var idx: int = _find_frame_idx(_virtual_clock)
	if idx < 0:
		return
	var idx_next: int = mini(idx + 1, _frames.size() - 1)
	if idx != _cached_from_idx or idx_next != _cached_to_idx:
		_cached_from_snap = _codec.decode_for_replay(_frames[idx])
		_cached_to_snap = _codec.decode_for_replay(_frames[idx_next])
		_cached_from_idx = idx
		_cached_to_idx = idx_next
	if _cached_from_snap.is_empty():
		return
	var bracket_dt: float = _timestamps[idx_next] - _timestamps[idx]
	var t: float
	if bracket_dt > _GAP_THRESHOLD_S:
		t = 0.0  # hold FROM across the gap; snap when clock reaches TO
	elif bracket_dt > 0.0:
		t = clampf((_virtual_clock - _timestamps[idx]) / bracket_dt, 0.0, 1.0)
	else:
		t = 0.0
	ReplayPlaybackEngine.apply_interpolated_snapshot(
			_cached_from_snap, _cached_to_snap, t, bracket_dt, delta,
			_records, _puck, _goalie_controllers)
	# Emit game-state changes (score / phase / period / clock) so the viewer
	# HUD doesn't have to poll every tick. Compare-and-emit avoids spamming
	# subscribers with the same dict every frame.
	var gs: Dictionary = _cached_to_snap.get("game_state", {})
	if not gs.is_empty() and gs != _last_emitted_game_state:
		_last_emitted_game_state = gs
		game_state_changed.emit(gs)


func _emit_due_events() -> void:
	while _next_event_idx < _events.size() and _events[_next_event_idx].host_ts <= _virtual_clock:
		goal_event_emitted.emit(_events[_next_event_idx].data)
		_next_event_idx += 1


# Linear scan starting from the last successful index. When the clock
# advances normally this is O(1) per frame; backward seeks reset the hint
# so a worst-case seek-to-start is still O(N).
func _find_frame_idx(t: float) -> int:
	if _frame_idx_hint > 0 and _timestamps[_frame_idx_hint] > t:
		_frame_idx_hint = 0
	var best: int = -1
	for i: int in range(_frame_idx_hint, _timestamps.size()):
		if _timestamps[i] <= t:
			best = i
		else:
			break
	if best >= 0:
		_frame_idx_hint = best
	return best


func _find_next_event_idx(t: float) -> int:
	for i: int in _events.size():
		if _events[i].host_ts > t:
			return i
	return _events.size()
