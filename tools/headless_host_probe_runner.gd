extends Node

# The work behind tools/headless_host_probe.gd. Starts a match whose every
# skater is a bot on a host with no skater of its own, and watches it to
# GAME_OVER, logging each phase change with the wall time and the tick rate the
# host held since the last one.
#
# Two hosts. As a server (`as_server`) it is DedicatedServer.start_match from a
# MatchConfig: no lobby, no seat, no camera. Otherwise it is a player's machine:
# an offline lobby with the host moved to a spectator seat, its camera and HUD
# mounted.

const FrameCost: GDScript = preload("res://tools/frame_cost_runner.gd")

const _START_TIMEOUT_FRAMES: int = 6000
# How long the run watches the host after GAME_OVER, to see what it does next
# with nobody to press a button.
const _POST_GAME_WATCH_S: float = 8.0

var _t0_ms: int = 0
var _last_phase: int = -1
var _last_phase_ms: int = 0
var _last_phase_tick: int = 0
var _phases: Array[Dictionary] = []
var _goals: int = 0
var _match_t0_ms: int = 0
var _match_frame0: int = 0
# Read as the match opens: a replay mounts cameras of its own later on.
var _camera_at_start: bool = false


# What the main thread spent in live play: the process step a frame and the
# tick, timed apart as tools/frame_cost_runner.gd times them.
var _bracket: FrameCost.Bracket = null
var _live_frames: int = 0
var _live_ticks: int = 0
var _live_proc_us: int = 0
var _live_phys_us: int = 0
var _live_wall_us: int = 0
var _freed: PackedStringArray = PackedStringArray()


# `opts`: team_size, period_s, periods, timeout_s, max_fps (0 leaves the prefs'
# cap), as_server, overtime, and free (node paths under the match scene to free
# before the match plays, to see what each costs).
func begin(opts: Dictionary) -> void:
	_t0_ms = Time.get_ticks_msec()
	var team_size: int = clampi(int(opts.team_size), 3, 5)
	if opts.as_server:
		_open_as_server(team_size, float(opts.period_s), int(opts.periods), bool(opts.overtime))
	else:
		await _open_through_lobby(team_size, float(opts.period_s), int(opts.periods),
				bool(opts.overtime))
	var started: bool = await _match_scene_up()
	if not started:
		_finish("never_started", team_size)
		return
	if int(opts.max_fps) > 0:
		Engine.max_fps = int(opts.max_fps)
	_free_nodes(opts.free as PackedStringArray)
	if opts.look_away:
		_mount_camera_seeing_nobody()
	_match_t0_ms = Time.get_ticks_msec()
	_match_frame0 = Engine.get_process_frames()
	_camera_at_start = get_viewport().get_camera_3d() != null
	GameManager.goal_scored.connect(func(_t: Team, _s: String, _a: String, _b: String) -> void:
		_goals += 1)
	_bracket = FrameCost.install_brackets(get_tree().root)
	var deadline_ms: int = _t0_ms + int(float(opts.timeout_s) * 1000.0)
	var reached: bool = false
	var t_prev: int = Time.get_ticks_usec()
	var tick_prev: int = Engine.get_physics_frames()
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		var t: int = Time.get_ticks_usec()
		var tick: int = Engine.get_physics_frames()
		if _phase() == GamePhase.Phase.PLAYING:
			_live_frames += 1
			_live_ticks += tick - tick_prev
			_live_proc_us += _bracket.proc_us
			_live_phys_us += _bracket.phys_us
			_live_wall_us += t - t_prev
		_bracket.proc_us = 0
		_bracket.phys_us = 0
		t_prev = t
		tick_prev = tick
		_note_phase()
		if _phase() == GamePhase.Phase.GAME_OVER:
			reached = true
			break
	if reached:
		var until_ms: int = Time.get_ticks_msec() + int(_POST_GAME_WATCH_S * 1000.0)
		while Time.get_ticks_msec() < until_ms:
			await get_tree().process_frame
			_note_phase()
	_finish("game_over" if reached else "timed_out", team_size)


# A current camera far above the rink and facing up: every skater is off camera
# to SkaterCameraCull, so each takes the path a skater nobody can see takes.
func _mount_camera_seeing_nobody() -> void:
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	cam.global_position = Vector3(0.0, 500.0, 0.0)
	cam.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	cam.make_current()


func _free_nodes(paths: PackedStringArray) -> void:
	for path: String in paths:
		var node: Node = get_tree().current_scene.get_node_or_null(path)
		if node == null:
			push_error("[headless-host] --free: no node at '%s'" % path)
			continue
		node.queue_free()
		_freed.append(path)


func _finish(outcome: String, team_size: int) -> void:
	var sm: GameStateMachine = GameManager.get("_state_machine") as GameStateMachine
	var scores: Array[int] = sm.scores if sm != null else ([0, 0] as Array[int])
	_last_phase_closed()
	var match_s: float = float(Time.get_ticks_msec() - _match_t0_ms) / 1000.0
	var row: Dictionary = {
		"outcome": outcome,
		"team_size": team_size,
		"skaters": get_tree().get_nodes_in_group("skaters").size(),
		"host": "server" if NetworkManager.is_dedicated_server else "spectator",
		"host_is_spectator": GameManager.is_local_spectator(),
		"host_has_skater": GameManager.get_local_player() != null,
		"host_has_camera": _camera_at_start,
		"freed": _freed,
		"live_process_ms": snappedf(float(_live_proc_us) / 1000.0 / maxf(float(_live_frames), 1.0), 0.01),
		"live_tick_ms": snappedf(float(_live_phys_us) / 1000.0 / maxf(float(_live_ticks), 1.0), 0.01),
		"live_main_thread_share": snappedf(
				float(_live_proc_us + _live_phys_us) / maxf(float(_live_wall_us), 1.0), 0.001),
		"score": scores,
		"goals_seen": _goals,
		"period": sm.current_period if sm != null else 0,
		"wall_s": snappedf(float(Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.1),
		"fps": snappedf(float(Engine.get_process_frames() - _match_frame0) / maxf(match_s, 0.001), 0.1),
		"fps_cap": Engine.max_fps,
		"native": NativeKernels.summary(),
		"phases": _phases,
	}
	print("[headless-host] %s" % JSON.stringify(row))
	get_tree().quit()


func _phase() -> int:
	var sm: GameStateMachine = GameManager.get("_state_machine") as GameStateMachine
	return sm.current_phase if sm != null else -1


func _note_phase() -> void:
	var phase: int = _phase()
	if phase == _last_phase:
		return
	_last_phase_closed()
	_last_phase = phase
	_last_phase_ms = Time.get_ticks_msec()
	_last_phase_tick = Engine.get_physics_frames()


# Logs the phase being left: how long it ran and the tick rate held in it.
func _last_phase_closed() -> void:
	if _last_phase < 0:
		return
	var span_s: float = float(Time.get_ticks_msec() - _last_phase_ms) / 1000.0
	_phases.append({
		"phase": GamePhase.Phase.keys()[_last_phase],
		"s": snappedf(span_s, 0.1),
		"hz": snappedf(float(Engine.get_physics_frames() - _last_phase_tick) / maxf(span_s, 0.001), 0.1),
	})


func _open_as_server(team_size: int, period_s: float, periods: int, overtime: bool) -> void:
	var config: MatchConfig = MatchConfig.from_dict({
		"game_id": PlayerPrefs.generate_uuid(),
		"team_size": team_size,
		"num_periods": periods,
		"period_duration": period_s,
		"ot_enabled": overtime,
		"fill_bots": true,
	})
	DedicatedServer.start_match(config)


func _open_through_lobby(team_size: int, period_s: float, periods: int, overtime: bool) -> void:
	var tree: SceneTree = get_tree()
	PlayerPrefs.preferred_team_size = team_size
	NetworkManager.start_offline()
	tree.change_scene_to_file(Constants.SCENE_LOBBY)
	while tree.current_scene == null or tree.current_scene.scene_file_path != Constants.SCENE_LOBBY:
		await tree.process_frame
	await tree.process_frame
	var lobby: LobbyManager = _find_lobby(tree.current_scene)
	lobby.set("_period_duration", period_s)
	lobby.set("_num_periods", periods)
	lobby.set("_ot_enabled", overtime)
	lobby.call("_on_spectate_pressed")
	await tree.process_frame
	_fill_bots(lobby, team_size)
	await tree.process_frame
	lobby.call("_on_start_pressed")


func _match_scene_up() -> bool:
	var tree: SceneTree = get_tree()
	var waited: int = 0
	while tree.current_scene == null \
			or tree.current_scene.scene_file_path != Constants.SCENE_HOCKEY \
			or GameManager.get("_state_machine") == null:
		await tree.process_frame
		waited += 1
		if waited > _START_TIMEOUT_FRAMES:
			push_error("[headless-host] the match scene never came up")
			return false
	return true


func _fill_bots(lobby: LobbyManager, team_size: int) -> void:
	var taken: Dictionary = lobby.get("_lobby_slots")
	for s: int in team_size:
		for team_id: int in 2:
			var key: int = LobbySlotKey.encode(team_id, s)
			if not taken.has(key):
				NetworkManager.send_bot_slot(key, true)


func _find_lobby(n: Node) -> LobbyManager:
	if n is LobbyManager:
		return n as LobbyManager
	for c: Node in n.get_children():
		var found: LobbyManager = _find_lobby(c)
		if found != null:
			return found
	return null
