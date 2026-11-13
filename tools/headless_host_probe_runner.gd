extends Node

# The work behind tools/headless_host_probe.gd. Opens an offline lobby, moves
# the host to a spectator seat, fills every skater seat with a bot, starts the
# match and watches it to GAME_OVER, logging each phase change with the wall
# time and the tick rate the host held since the last one.
#
# The host still mounts its spectator camera and HUD here. What this measures is
# the simulation and the match flow with no skater on the simulating machine;
# a server with no camera at all is a step further than this goes.

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


# `max_fps` caps the process step once the match is up; 0 leaves the prefs' cap.
func begin(team_size: int, period_s: float, periods: int, timeout_s: float, max_fps: int) -> void:
	_t0_ms = Time.get_ticks_msec()
	var started: bool = await _start_match(clampi(team_size, 3, 5), period_s, periods)
	if not started:
		_finish("never_started", team_size)
		return
	if max_fps > 0:
		Engine.max_fps = max_fps
	_match_t0_ms = Time.get_ticks_msec()
	_match_frame0 = Engine.get_process_frames()
	GameManager.goal_scored.connect(func(_t: Team, _s: String, _a: String, _b: String) -> void:
		_goals += 1)
	var deadline_ms: int = _t0_ms + int(timeout_s * 1000.0)
	var reached: bool = false
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
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


func _finish(outcome: String, team_size: int) -> void:
	var sm: GameStateMachine = GameManager.get("_state_machine") as GameStateMachine
	var scores: Array[int] = sm.scores if sm != null else ([0, 0] as Array[int])
	_last_phase_closed()
	var match_s: float = float(Time.get_ticks_msec() - _match_t0_ms) / 1000.0
	var row: Dictionary = {
		"outcome": outcome,
		"team_size": team_size,
		"skaters": get_tree().get_nodes_in_group("skaters").size(),
		"host_is_spectator": GameManager.is_local_spectator(),
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


func _start_match(team_size: int, period_s: float, periods: int) -> bool:
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
	lobby.call("_on_spectate_pressed")
	await tree.process_frame
	_fill_bots(lobby, team_size)
	await tree.process_frame
	lobby.call("_on_start_pressed")
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
