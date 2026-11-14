extends Node

# The work behind tools/own_goal_hunt.gd: an all-bot match (the local player
# spectating), a ring of the last few seconds of the puck and whoever touched it,
# and on every goal whose last touch was the defending team's, that ring printed.

const _START_TIMEOUT_FRAMES: int = 6000
const _RING_TICKS: int = 360
const _PRINT_EVERY_TICKS: int = 6
const _PERIOD_SEC: float = 36000.0

var _ring: Array[String] = []
var _ring_head: int = 0
var _goals: int = 0
var _own_goals: int = 0
var _last_toucher: int = -1
var _last_carrier: int = -1
var _live_ticks: int = 0


func begin(team_size: int, seconds: float) -> void:
	_ring.resize(_RING_TICKS)
	_ring.fill("")
	await _start_match(team_size)
	GameManager.goal_scored.connect(_on_goal)
	process_physics_priority = 1_000_000_000
	var target: int = int(seconds * Engine.physics_ticks_per_second)
	while _live_ticks < target:
		await get_tree().physics_frame
	print("[own-goal] SUMMARY %s" % JSON.stringify({
		"team_size": team_size, "live_s": seconds, "goals": _goals, "own_goals": _own_goals}))
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if GameManager.puck == null:
		return
	if not GameManager.is_movement_locked():
		_live_ticks += 1
	var reg: PlayerRegistry = GameManager.get("_registry")
	var tracker: ShotOnGoalTracker = GameManager.get("_shot_tracker")
	if tracker != null:
		_last_toucher = tracker.get_last_toucher()
	var carrier: Skater = GameManager.get_puck_carrier()
	_last_carrier = reg.resolve_peer_id(carrier) if carrier != null else -1
	var puck: Puck = GameManager.puck
	var p: Vector3 = puck.global_position
	var v: Vector3 = puck.linear_velocity
	var line := "t=%d puck=(%.2f,%.2f,%.2f) v=(%.1f,%.1f) carrier=%d toucher=%d" % [
			Engine.get_physics_frames(), p.x, p.y, p.z, v.x, v.z, _last_carrier, _last_toucher]
	var who: int = _last_carrier if _last_carrier != -1 else _last_toucher
	if who != -1:
		line += " | " + _describe(reg, who)
	_ring[_ring_head] = line
	_ring_head = (_ring_head + 1) % _RING_TICKS


func _describe(reg: PlayerRegistry, peer_id: int) -> String:
	var rec: PlayerRecord = reg.get_record(peer_id)
	if rec == null or rec.skater == null:
		return "peer %d ?" % peer_id
	var s: Skater = rec.skater
	var pos: Vector3 = s.global_position
	var fwd: Vector3 = -s.global_transform.basis.z
	var out := "peer %d team %d pos=(%.2f,%.2f) vel=(%.1f,%.1f) fwd=(%.2f,%.2f)" % [
			peer_id, rec.team.team_id, pos.x, pos.z, s.velocity.x, s.velocity.z, fwd.x, fwd.z]
	if rec.controller is AIController:
		var agent: SkaterAgent = rec.controller.get("_agent")
		if agent != null:
			var sm: SkaterAgentStateMachine = agent.get("_sm")
			var cursor: SkaterAgentCarryCursor = sm.get("_carry_cursor")
			var state_name: String = SkaterAgentStateMachine.State.keys()[agent.get_state()]
			var mode_name: String = SkaterAgentCarryCursor.Mode.keys()[cursor.mode]
			var input: InputState = agent.get("_scratch_input")
			var m: Vector3 = input.mouse_world_pos
			out += " state=%s mode=%s mouse=(%.2f,%.2f) intent=%s win=%s dec=%s" % [
					state_name, mode_name, m.x, m.z, agent.debug_intent(), agent.debug_winner(),
					agent.debug_last_decision().replace("\n", " / ")]
	return out


func _on_goal(scoring_team: Team, _scorer: String, _a1: String, _a2: String) -> void:
	_goals += 1
	var reg: PlayerRegistry = GameManager.get("_registry")
	var who: int = _last_carrier if _last_carrier != -1 else _last_toucher
	var who_team: int = reg.resolve_team_id_for_peer(who) if who != -1 else -1
	var own: bool = who_team != -1 and who_team != scoring_team.team_id
	if not own:
		print("[own-goal] goal #%d by team %d (toucher %d, carried=%s)" % [
				_goals, scoring_team.team_id, who, _last_carrier != -1])
		return
	_own_goals += 1
	print("[own-goal] OWN GOAL #%d into team %d's net by peer %d (carried=%s) — last %d ticks:" % [
			_own_goals, who_team, who, _last_carrier != -1, _RING_TICKS])
	for i: int in _RING_TICKS:
		var idx: int = (_ring_head + i) % _RING_TICKS
		if i % _PRINT_EVERY_TICKS == 0 or i >= _RING_TICKS - 12:
			print("[own-goal]   " + _ring[idx])


func _start_match(team_size: int) -> void:
	var tree: SceneTree = get_tree()
	PlayerPrefs.preferred_team_size = team_size
	NetworkManager.start_offline()
	tree.change_scene_to_file(Constants.SCENE_LOBBY)
	while tree.current_scene == null or tree.current_scene.scene_file_path != Constants.SCENE_LOBBY:
		await tree.process_frame
	await tree.process_frame
	var lobby: LobbyManager = _find_lobby(tree.current_scene)
	lobby.set("_period_duration", _PERIOD_SEC)
	lobby.call("_on_spectate_pressed")
	await tree.process_frame
	await tree.process_frame
	var taken: Dictionary = lobby.get("_lobby_slots")
	for s: int in team_size:
		for team_id: int in 2:
			var key: int = LobbySlotKey.encode(team_id, s)
			if not taken.has(key):
				NetworkManager.send_bot_slot(key, true)
	await tree.process_frame
	lobby.call("_on_start_pressed")
	var waited: int = 0
	while tree.current_scene == null \
			or tree.current_scene.scene_file_path != Constants.SCENE_HOCKEY:
		await tree.process_frame
		waited += 1
		if waited > _START_TIMEOUT_FRAMES:
			push_error("[own-goal] the match never started")
			break


func _find_lobby(n: Node) -> LobbyManager:
	if n is LobbyManager:
		return n as LobbyManager
	for c: Node in n.get_children():
		var found: LobbyManager = _find_lobby(c)
		if found != null:
			return found
	return null
