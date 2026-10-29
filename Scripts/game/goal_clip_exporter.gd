class_name GoalClipExporter
extends Node

# Owns the "save this goal as a GIF" feature end to end: when to capture, what
# the player's press means, and handing the result to the encoder.
#
# Two places a goal can be saved, one capture behind both:
#   - the in-game goal cinematic (GoalReplayDriver), live as it airs, and
#   - the post-game screen, which airs a stored goal again through this node's
#     own GoalReplayDriver (save_stored_goal) and captures that.
#
# Both are segment-shaped: a segment opens, frames accumulate for its whole
# length, and it closes. During the live cinematic the player's press ARMS the
# open segment rather than starting a capture, because a press two thirds of
# the way through a goal still means "save the goal," not "save the last two
# seconds." The cost of that is capturing speculatively on every cinematic —
# see ClipFrameCapture. A stored goal is armed from its first frame, so the
# post-game screen captures nothing it won't save.
#
# Entirely local. Every peer runs its own replay drivers off its own recorder,
# so a save touches no RPC, needs no host, and never has to agree with anyone.
#
# Owned by GameManager, which forwards the player's press to request_export()
# and the post-game screen's pick to save_stored_goal().

enum State {
	IDLE,      ## nothing armed; a segment may or may not be capturing
	ARMED,     ## press registered, waiting for the current segment to close
	ENCODING,  ## segment closed, worker thread is encoding
}

signal state_changed(state: State)
## Whether a segment is open to be saved. Separate from state_changed because
## a segment opening and closing is not a state transition — IDLE spans both —
## and it is what decides whether the HUD shows a prompt at all.
signal availability_changed(available: bool)
## ok = false on any failure; path is empty in that case.
signal export_finished(path: String, ok: bool)
## A stored goal finished airing for its export (not when one is cancelled), so
## whatever it displaced can resume.
signal stored_replay_finished
## A stored goal's incoming wipe covers the screen and its replay is about to
## pose the actors, so whatever it played over (the post-game reel) lets go.
signal stored_replay_taking_over
## The stored goal's replay_frame_changed and its every stop (finished or
## cancelled), so the arena board can show the goal's recorded clock and score.
signal stored_replay_frame_changed(game_state: Dictionary, carrier_team: int)
signal stored_replay_stopped
signal stored_replay_body_check(force: float)

var _capture: ClipFrameCapture = null
var _exporter: GifExporter = null
var _goal_driver: GoalReplayDriver = null
var _stored_driver: GoalReplayDriver = null
var _state: State = State.IDLE
# Scorer of the segment currently being captured, for the filename.
var _segment_label: String = ""
# Supplies the scorer for the live cinematic (a stored goal carries its own
# meta). A Callable rather than a GameManager reach-up, per the layering rule.
var _goal_label_provider: Callable = Callable()
var _cancelling_stored: bool = false


func _ready() -> void:
	_capture = ClipFrameCapture.new()
	add_child(_capture)
	_exporter = GifExporter.new()
	_exporter.export_finished.connect(_on_export_finished)
	add_child(_exporter)
	_stored_driver = GoalReplayDriver.new()
	_stored_driver.use_shared_replay_mode = false
	add_child(_stored_driver)
	_stored_driver.taking_over.connect(stored_replay_taking_over.emit)
	_stored_driver.replay_frame_changed.connect(stored_replay_frame_changed.emit)
	_stored_driver.body_check_replayed.connect(stored_replay_body_check.emit)
	_stored_driver.replay_finishing.connect(_close_segment)
	_stored_driver.replay_stopped.connect(_on_stored_replay_stopped)


func setup(goal_driver: GoalReplayDriver) -> void:
	_goal_driver = goal_driver
	if goal_driver != null:
		goal_driver.replay_started.connect(_on_goal_replay_started)
		goal_driver.replay_finishing.connect(_close_segment)
		goal_driver.replay_stopped.connect(_close_segment)


func state() -> State:
	return _state


# True when a press would do something — a segment is capturing and we aren't
# already busy. Drives the HUD prompt's visibility.
func can_export() -> bool:
	return _state == State.IDLE and _capture != null and _capture.is_capturing()


# The player pressed save. Arms the open segment; the export itself fires when
# that segment closes and its frames are complete.
func request_export() -> void:
	if not can_export():
		return
	_set_state(State.ARMED)


func set_goal_label_provider(provider: Callable) -> void:
	_goal_label_provider = provider


# True when a stored goal can be aired and saved now: the encoder exists and
# nothing is capturing, armed or encoding.
func can_save_stored() -> bool:
	return GifExporter.is_available() and _state == State.IDLE \
			and _capture != null and not _capture.is_capturing() \
			and not _stored_driver.is_active()


# Airs `clip` (a GoalReplayStore entry) as the goal cinematic on the live
# actors and saves it. Whatever else poses them keeps going under the incoming
# wipe and must let go on stored_replay_taking_over. False when nothing started.
func save_stored_goal(clip: Dictionary, codec: WorldStateCodec, registry: PlayerRegistry,
		puck: Puck, goalie_controllers: Array) -> bool:
	if not can_save_stored():
		return false
	_stored_driver.replay_clip(clip, codec, registry, puck, goalie_controllers)
	if not _stored_driver.is_active():
		return false
	_open_segment(String(clip.get("scorer_name", "")), clip)
	_set_state(State.ARMED)
	return true


# Ends a stored goal's airing without saving it or announcing it finished.
func cancel_stored() -> void:
	if not _stored_driver.is_active():
		return
	if _capture.is_capturing():
		_capture.discard()
		availability_changed.emit(false)
	if _state == State.ARMED:
		_set_state(State.IDLE)
	_cancelling_stored = true
	_stored_driver.stop()
	_cancelling_stored = false


func _on_goal_replay_started() -> void:
	var label: String = ""
	if _goal_label_provider.is_valid():
		label = String(_goal_label_provider.call())
	_open_segment(label, _goal_driver.get_active_clip())


# Stopped before finished: finished resumes the post-game reel, whose first
# frame must not be cleared by this goal's stop.
func _on_stored_replay_stopped() -> void:
	_close_segment()
	stored_replay_stopped.emit()
	if not _cancelling_stored:
		stored_replay_finished.emit()


# `clip` carries the stinger colors the segment's intro wipe is painted in.
func _open_segment(label: String, clip: Dictionary) -> void:
	# Without the extension there is no encode to feed, so don't pay the
	# capture cost either.
	if _capture == null or not GifExporter.is_available():
		return
	_segment_label = label
	_capture.start(clip.get("stinger_primary", Color.BLACK) as Color,
			clip.get("stinger_secondary", Color.WHITE) as Color)
	availability_changed.emit(true)


# End of a segment: hand it to the encoder if the player armed it, otherwise
# throw the frames away.
func _close_segment() -> void:
	if _capture == null or not _capture.is_capturing():
		return
	if _state != State.ARMED:
		_capture.discard()
		availability_changed.emit(false)
		return
	_capture.stop()
	availability_changed.emit(false)
	var frames: Array[Image] = _capture.take()
	if not _exporter.export_frames(frames, _capture.fps(), _segment_label):
		_set_state(State.IDLE)
		export_finished.emit("", false)
		return
	_set_state(State.ENCODING)


# World teardown (match end, quit to free play, kicked). Drops any segment in
# progress and any stored goal still airing; an encode already handed to the
# worker thread is left to finish and land its file, since the frames it holds
# are complete and no longer depend on anything being torn down.
func abort() -> void:
	cancel_stored()
	if _capture != null and _capture.is_capturing():
		_capture.discard()
		availability_changed.emit(false)
	if _state == State.ARMED:
		_set_state(State.IDLE)


func _on_export_finished(path: String, ok: bool) -> void:
	_set_state(State.IDLE)
	export_finished.emit(path, ok)


func _set_state(next: State) -> void:
	if _state == next:
		return
	_state = next
	state_changed.emit(_state)
