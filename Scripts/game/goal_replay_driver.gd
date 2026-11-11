class_name GoalReplayDriver
extends Node

# Drives the in-game goal replay, on every peer from its own recorder, by:
#   1. Extracting the last CLIP_DURATION seconds from ReplayRecorder on goal.
#   2. Parking the live sim (ReplayLiveSimHold: the puck sim, goalie AI, and
#      interpolation on every posed actor) so it doesn't fight the replay.
#   3. Decoding each recorded packet into typed actor states (via the codec's
#      side-effect-free decode_for_replay) and applying them directly to the
#      Skater / Puck / Goalie nodes, sampled at render time, so poses reflect
#      what happened.
#
# Bypasses WorldStateCodec.decode_world_state because that path mutates the
# host's GameStateMachine — replaying a packet would slam phase / score / clock
# back to whatever was captured before the goal.
#
# A ReplayStinger wipe hides both camera cuts: live → replay at the start, and
# replay → live (where the post-goal faceoff staging teleports everyone) at the
# end. The incoming wipe sweeps over live play: the replay takes the world over
# (parks the sim, enters replay mode, cuts to its cameras) only once the band
# covers the screen, so nothing freezes in sight. finish() runs the outgoing
# wipe and then stop(); stop() is the immediate teardown. replay_finishing marks
# where the replay itself ends — the outgoing wipe is not part of it (the GIF
# export closes its clip there).
#
# Owned by GameManager; PhaseCoordinator.start_goal_replay starts it on every
# peer.
#
# Testing: integration-only. This drives LIVE scene actors (Skater / Puck /
# Goalie nodes) via the actor-driven ReplayPlaybackEngine, so there is no
# headless unit test; the pieces it composes are covered instead
# (test_goal_replay_rules, test_world_state_codec, test_replay_recorder,
# test_goal_replay_store).

# Seconds of history extracted: the longest play GoalReplayRules keeps
# (MAX_PRE_TOUCH), room for the scoring touch to sit before the goal, and the
# post-goal tail.
const CLIP_DURATION: float = 12.0
const OUTRO_HOLD: float = 0.25    # real seconds on the goal frame before the outgoing wipe

enum Stage { IDLE, WIPE_IN, PLAYING, OUTRO, WIPE_OUT }

signal replay_started
signal replay_finishing
# The incoming wipe covers the screen and the replay is about to pose the
# actors: whatever else was driving them (the post-game reel) lets go now.
signal taking_over
signal replay_stopped
# Once per recorded frame the replay steps onto: the game state the arena showed
# at that instant (clock, score, phase) and the team carrying the puck (-1 loose),
# so the board and the crowd can play the moment as it was.
signal replay_frame_changed(game_state: Dictionary, carrier_team: int)
# A recorded body check the replay re-fires, with the live broadcast's force, so
# the crowd rises to it as it did live.
signal body_check_replayed(force: float)

var _codec: WorldStateCodec = null
var _registry: PlayerRegistry = null
var _puck: Puck = null
var _goalies: Array[Goalie] = []
var _goalie_controllers: Array[GoalieController] = []

# The live cinematic mirrors replay mode to clients; a stored goal replayed for
# one peer's GIF export (GoalClipExporter) stays local.
var use_shared_replay_mode: bool = true

var _frames: Array[PackedByteArray] = []
var _timestamps: Array[float] = []
var _scoring_team: int = -1
var _clip_start_ts: float = 0.0
var _clip_end_ts: float = 0.0
var _goal_ts: float = 0.0
var _slowmo_start_ts: float = 0.0
var _virtual_clock: float = 0.0
var _stage: Stage = Stage.IDLE
var _outro_elapsed: float = 0.0

# Which recorded frames bracket the virtual clock, decoded once per bracket.
var _cursor := ReplayFrameCursor.new()
var _last_fed_snap: Dictionary = {}

var _sim_hold := ReplayLiveSimHold.new()

var _stinger: ReplayStinger = null
var _stinger_primary: Color = Color.BLACK
var _stinger_secondary: Color = Color.WHITE

# Hard cam (broadcast main, current from the incoming wipe) and the net cam
# behind the defending goal, cut to once slow motion is on and the puck is
# within GoalReplayRules.NET_CAM_CUT_RANGE. The driver owns make_current() for
# both and restores _saved_prev_camera itself.
var _hard_cam: SpectatorCamera = null
var _net_cam: SpectatorCamera = null
var _saved_prev_camera: Camera3D = null
var _has_cut_to_net_cam: bool = false
var _net_cam_position: Vector3 = Vector3.ZERO
# The replay parked the world and entered replay mode (at full cover); before
# that, live play is still running under the incoming wipe.
var _took_over: bool = false
# Goal-line z of the defending goal; 0 means no goal was supplied and no net cam.
var _defending_goal_z: float = 0.0
var _goal_center: Vector3 = Vector3.ZERO

# Audio + body-check VFX events extracted from the recorder, ordered by
# host_ts. We walk these in lockstep with the virtual clock so the cinematic
# re-fires the sounds and burst VFX that played live — see
# ReplayEventReplayer for the actual dispatch.
var _events: Array[Dictionary] = []
var _next_event_idx: int = 0


func _ready() -> void:
	_stinger = ReplayStinger.new()
	add_child(_stinger)
	_stinger.covered.connect(_on_stinger_covered)


func start(recorder: ReplayRecorder,
		codec: WorldStateCodec,
		registry: PlayerRegistry,
		puck: Puck,
		goalie_controllers: Array,
		defending_goal_z: float = 0.0,
		stinger_primary: Color = Color.BLACK,
		stinger_secondary: Color = Color.WHITE,
		scoring_team: int = -1) -> void:
	var clip: Dictionary = recorder.extract_clip(CLIP_DURATION)
	var timestamps: Array[float] = clip.timestamps
	if timestamps.size() >= 2:
		clip.events = recorder.extract_events(timestamps[0], timestamps[timestamps.size() - 1])
	clip.goal_ts = recorder.goal_ts()
	clip.defending_goal_z = defending_goal_z
	clip.scoring_team_id = scoring_team
	clip.stinger_primary = stinger_primary
	clip.stinger_secondary = stinger_secondary
	replay_clip(clip, codec, registry, puck, goalie_controllers)


# Plays a clip as the goal cinematic: one start() just extracted, or one
# GoalReplayStore kept from get_active_clip(). The trim and the slow motion are
# re-derived from its events, so a stored goal replays exactly as it aired.
func replay_clip(clip: Dictionary,
		codec: WorldStateCodec,
		registry: PlayerRegistry,
		puck: Puck,
		goalie_controllers: Array) -> void:
	if _stage != Stage.IDLE:
		stop()

	var frames: Array[PackedByteArray] = clip.frames
	var timestamps: Array[float] = clip.timestamps
	if frames.size() < 2:
		return
	var defending_goal_z: float = float(clip.get("defending_goal_z", 0.0))
	_scoring_team = int(clip.get("scoring_team_id", -1))

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
	_cursor.bind(codec)
	_cursor.reset()
	_last_fed_snap = {}
	# A copy: _events is this replay's, and a stored clip's list must survive it.
	var events: Array[Dictionary] = []
	events.assign(clip.get("events", []))
	_events = events

	# The clip runs a short tail past the goal frame; the scoring touch is the
	# scoring team's last contact before it. The trim and the slow motion hang
	# off those two.
	_goal_ts = float(clip.get("goal_ts", -1.0))
	if _goal_ts < _clip_start_ts or _goal_ts > _clip_end_ts:
		_goal_ts = _clip_end_ts
	var touch_idx: int = GoalReplayRules.scoring_touch_index(_events, _goal_ts, _scoring_team)
	var touch_ts: float = float(_events[touch_idx].host_ts) if touch_idx >= 0 else -1.0
	var touch_pos := Vector3(0.0, 0.0, defending_goal_z)
	if touch_idx >= 0:
		var pos: Array = _events[touch_idx].event.pos
		touch_pos = Vector3(pos[0], pos[1], pos[2])
	_net_cam_position = GoalReplayRules.net_cam_position(defending_goal_z, touch_pos.x)
	var anchor_ts: float = touch_ts if touch_ts >= 0.0 else _goal_ts
	_clip_start_ts = maxf(_clip_start_ts, GoalReplayRules.clip_start_ts(
			_events, anchor_ts, touch_pos.z, signf(defending_goal_z), _scoring_team))
	_slowmo_start_ts = GoalReplayRules.slowmo_start_ts(touch_ts, _goal_ts)
	_virtual_clock = _clip_start_ts
	_next_event_idx = 0
	while _next_event_idx < _events.size() and _events[_next_event_idx].host_ts < _clip_start_ts:
		_next_event_idx += 1

	_defending_goal_z = defending_goal_z
	_goal_center = Vector3(0.0, 0.0, defending_goal_z)
	_has_cut_to_net_cam = false
	_took_over = false

	_stinger_primary = clip.get("stinger_primary", Color.BLACK) as Color
	_stinger_secondary = clip.get("stinger_secondary", Color.WHITE) as Color
	_stage = Stage.WIPE_IN
	_stinger.play(_stinger_primary, _stinger_secondary)
	replay_started.emit()


# At full cover: park the live world, enter replay mode and stand up the
# cameras. Live play ran on under the band until now.
func _take_over() -> void:
	taking_over.emit()
	_took_over = true
	_sim_hold.grab(_puck, _goalie_controllers, _registry.skaters())
	if use_shared_replay_mode:
		NetworkManager.start_replay_mode(_clip_start_ts)
	else:
		NetworkManager.set_replay_mode_local(true, _clip_start_ts)
	_saved_prev_camera = get_viewport().get_camera_3d()

	_hard_cam = SpectatorCamera.new()
	add_child(_hard_cam)
	_hard_cam.setup(func() -> Vector3: return _puck.global_position)

	if _defending_goal_z != 0.0:
		_net_cam = SpectatorCamera.new()
		add_child(_net_cam)
		var goal_z: float = _defending_goal_z
		_net_cam.setup(func() -> Vector3:
			return GoalReplayRules.net_cam_look_target(_puck.global_position, goal_z))
		_net_cam.set_booth(_net_cam_position, 55.0, 0.15)


# Ends the replay behind the outgoing wipe. A replay still under its incoming
# wipe has shown nothing yet, so it stops at once and that wipe plays out over
# the live view.
func finish() -> void:
	match _stage:
		Stage.PLAYING, Stage.OUTRO:
			_stage = Stage.WIPE_OUT
			_stinger.play(_stinger_primary, _stinger_secondary)
			replay_finishing.emit()
		Stage.WIPE_IN:
			stop()


func stop() -> void:
	if _stage == Stage.IDLE:
		return
	_stage = Stage.IDLE

	if _saved_prev_camera != null and is_instance_valid(_saved_prev_camera):
		_saved_prev_camera.make_current()
	_saved_prev_camera = null
	if _hard_cam != null:
		_hard_cam.queue_free()
		_hard_cam = null
	if _net_cam != null:
		_net_cam.queue_free()
		_net_cam = null
	_has_cut_to_net_cam = false

	# The host mirrors the stop even from under the incoming wipe: a client may
	# already have started its own replay off the GOAL_SCORED phase byte. A
	# local replay that never took over leaves replay mode to its owner (the
	# post-game reel still running under the band).
	if use_shared_replay_mode:
		NetworkManager.stop_replay_mode()
	elif _took_over:
		NetworkManager.set_replay_mode_local(false)
	if _took_over:
		_sim_hold.release()
	_took_over = false
	_frames = []
	_timestamps = []
	_cursor.reset()
	_last_fed_snap = {}
	_events = []
	_next_event_idx = 0
	_codec = null
	_registry = null
	_puck = null
	_goalies = []
	_goalie_controllers = []
	replay_stopped.emit()


func is_active() -> bool:
	return _stage != Stage.IDLE


# Snapshot of the clip currently being replayed, for GoalReplayStore to keep a
# copy that outlives the ~18 s recorder ring. start_ts is the TRIMMED start (the
# play that scored) so the post-game loop begins where the live cinematic did,
# not at the raw clip head; the rest is what replay_clip() reads to air it
# again. Valid between replay_started and replay_stopped.
func get_active_clip() -> Dictionary:
	return {
		"frames": _frames,
		"timestamps": _timestamps,
		"start_ts": _clip_start_ts,
		"end_ts": _clip_end_ts,
		"events": _events,
		"goal_ts": _goal_ts,
		"defending_goal_z": _defending_goal_z,
		"scoring_team_id": _scoring_team,
		"stinger_primary": _stinger_primary,
		"stinger_secondary": _stinger_secondary,
	}


func _on_stinger_covered() -> void:
	match _stage:
		Stage.WIPE_IN:
			_stage = Stage.PLAYING
			_take_over()
			# Pose the clip's first frame before the cam seeds on the puck, or it
			# would snap to the puck still sitting in the net.
			_pose(0.0)
			_hard_cam.snap_to_position()
			_hard_cam.make_current()
		Stage.WIPE_OUT:
			stop()


func _process(delta: float) -> void:
	match _stage:
		Stage.PLAYING:
			_advance(delta)
		Stage.OUTRO:
			_pose(0.0)
			_outro_elapsed += delta
			if _outro_elapsed >= OUTRO_HOLD:
				finish()
		Stage.WIPE_OUT:
			_pose(0.0)


func _advance(delta: float) -> void:
	var speed: float = GoalReplayRules.playback_speed(_virtual_clock, _slowmo_start_ts)
	var prev_clock: float = _virtual_clock
	_virtual_clock += delta * speed
	if _virtual_clock >= _clip_end_ts:
		_virtual_clock = _clip_end_ts
		_stage = Stage.OUTRO
		_outro_elapsed = 0.0
	_pose(_virtual_clock - prev_clock)


# Poses the world at the virtual clock. The held goal frame is re-posed every
# frame too: the skaters' own tick keeps integrating their replayed velocity,
# and a frame that is not re-posed slides with it.
func _pose(sim_delta: float) -> void:
	NetworkManager.set_replay_clock(_virtual_clock)

	if not _cursor.seek(_frames, _timestamps, _virtual_clock):
		return
	# Pass the virtual-clock advance (slow-mo-scaled, exactly clamped at clip end)
	# rather than the wall-frame delta, so procedural pose driven off it — the
	# skater leg gait — keeps cadence with the on-screen motion during slow-mo.
	ReplayPlaybackEngine.apply_interpolated_snapshot(
			_cursor.from_snap(), _cursor.to_snap(), _cursor.alpha(), _cursor.bracket_dt(),
			sim_delta, _registry.all(), _puck, _goalie_controllers)
	_dispatch_due_events()
	var snap: Dictionary = _cursor.to_snap()
	if not is_same(snap, _last_fed_snap):
		_last_fed_snap = snap
		var gs: Variant = snap.get("game_state")
		if gs is Dictionary:
			replay_frame_changed.emit(gs,
					_registry.resolve_team_id_for_peer(int(snap.get("carrier_peer_id", -1))))

	# One-way cut to the net cam for the finish; it holds through the outro.
	if not _has_cut_to_net_cam and _net_cam != null \
			and _virtual_clock >= _slowmo_start_ts \
			and _puck.global_position.distance_to(_goal_center) <= GoalReplayRules.NET_CAM_CUT_RANGE:
		_net_cam.snap_to_position()
		_net_cam.make_current()
		_has_cut_to_net_cam = true


# Walk events whose timestamps have passed the virtual clock and fire each
# one through ReplayEventReplayer so puck-collision sounds, pickup sounds,
# shot sounds, and body-check sound+VFX play in time with the cinematic.
func _dispatch_due_events() -> void:
	while _next_event_idx < _events.size() \
			and _events[_next_event_idx].host_ts <= _virtual_clock:
		var event: Dictionary = _events[_next_event_idx].event
		ReplayEventReplayer.dispatch(event, _registry)
		if event.get("kind", "") == "body_check":
			body_check_replayed.emit(float(event.get("speed", 0.0)))
		_next_event_idx += 1
