extends Node

# The work behind tools/ui_preview.gd. Each shot names the stage it needs and
# the runner method that opens it; shots run in table order, a stage loads once
# for its run of shots, and every overlay is dismissed with Escape afterwards —
# so a popup that ignores ui_cancel fails the run instead of bleeding into the
# next shot.
#
# Openers call the same handler the on-screen button calls, by name. A renamed
# handler is reported as a failure naming it, never a silently wrong picture.

const _STAGE_BOOT: String = "boot"
const _STAGE_FREE_PLAY: String = "free_play"
const _STAGE_TUTORIAL: String = "tutorial"
const _STAGE_LOBBY: String = "lobby"
const _STAGE_MATCH: String = "match"

const _SHOTS: Array[Dictionary] = [
	{"name": "boot", "stage": _STAGE_BOOT, "open": "_open_nothing"},
	{"name": "options_gameplay", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 0},
	{"name": "options_camera", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 1},
	{"name": "options_video", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 2},
	{"name": "options_video_performance", "stage": _STAGE_BOOT, "open": "_open_video_performance"},
	{"name": "options_audio", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 3},
	{"name": "options_controls", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 4},
	{"name": "options_accessibility", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 5},
	# Free play lands with the side menu open; this is that landing, so it runs
	# before side_player dismisses the first-run callout on the player card.
	{"name": "side_menu", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": ""},
	{"name": "side_play", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_play_pressed"},
	{"name": "side_player", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_player_card_pressed"},
	{"name": "side_player_body", "stage": _STAGE_FREE_PLAY, "open": "_open_player_region", "arg": PlayerSettingsPopup.Region.BODY},
	{"name": "side_player_head", "stage": _STAGE_FREE_PLAY, "open": "_open_player_region", "arg": PlayerSettingsPopup.Region.HEAD},
	{"name": "side_player_stick", "stage": _STAGE_FREE_PLAY, "open": "_open_player_region", "arg": PlayerSettingsPopup.Region.STICK},
	{"name": "side_player_skates", "stage": _STAGE_FREE_PLAY, "open": "_open_player_region", "arg": PlayerSettingsPopup.Region.SKATES},
	{"name": "side_career", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_career_pressed"},
	{"name": "side_tutorials", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_tutorial_pressed"},
	{"name": "side_drills", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_drills_pressed"},
	{"name": "side_options", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_options_pressed"},
	{"name": "side_exit", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_exit_pressed"},
	{"name": "hud_free_play", "stage": _STAGE_FREE_PLAY, "open": "_close_side_menu"},
	{"name": "post_game_analytics", "stage": _STAGE_FREE_PLAY, "open": "_open_post_game_analytics"},
	{"name": "hud_tutorial", "stage": _STAGE_TUTORIAL, "open": "_open_nothing"},
	{"name": "lobby", "stage": _STAGE_LOBBY, "open": "_open_nothing"},
	{"name": "hud_match", "stage": _STAGE_MATCH, "open": "_open_nothing"},
]

# Long enough for a match scene's first-frame setup (camera ease-in, HUD
# fade-ins) to finish. Both bounds hold because the software rasterizer runs a
# match at about one frame a second: frames alone would be minutes of game time
# on a fast machine, seconds alone a handful of frames here.
const _STAGE_SETTLE_FRAMES: int = 10
const _STAGE_SETTLE_SEC: float = 3.0
# Covers the menu open tweens, which run on real time.
const _SHOT_SETTLE_FRAMES: int = 4
const _SHOT_SETTLE_SEC: float = 0.8
# Game time a match runs past the opening faceoff before its shots, so the
# skaters have spread out of the faceoff formation.
const _MATCH_PLAY_SEC: float = 6.0
# Physics ticks allowed per rendered frame while that time elapses. At the
# software rasterizer's ~1 fps the default 8 would take minutes of wall clock.
const _MATCH_STEPS_PER_FRAME: int = 60
const _MATCH_START_TIMEOUT_FRAMES: int = 600
# Deepest overlay stack a shot opens (player settings over the side menu), plus
# slack.
const _MAX_DISMISS_PRESSES: int = 6

var _out_dir: String = ""
var _stage: String = ""
var _shot_ok: bool = true
var _failed: bool = false


func begin(only: String, out_dir: String, list_only: bool) -> void:
	if list_only:
		for shot: Dictionary in _SHOTS:
			print("%-24s %s" % [shot.name, shot.stage])
		get_tree().quit()
		return
	var shots: Array[Dictionary] = _select(only)
	if shots.is_empty():
		get_tree().quit(1)
		return
	_out_dir = out_dir
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for shot: Dictionary in shots:
		if shot.stage != _stage:
			await _enter_stage(shot.stage)
		_shot_ok = true
		if has_method(shot.open):
			var args: Array = [shot.arg] if shot.has("arg") else []
			await Callable(self, shot.open).callv(args)
		else:
			_fail("no opener %s for shot %s" % [shot.open, shot.name])
		if _shot_ok:
			await _settle(_SHOT_SETTLE_FRAMES, _SHOT_SETTLE_SEC)
			await _snap(shot.name)
		await _dismiss(shot.name)
	get_tree().quit(1 if _failed else 0)


# Shot names, or group prefixes: "options" selects every options_* shot.
func _select(only: String) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	if only.is_empty():
		picked.assign(_SHOTS)
		return picked
	var tokens: PackedStringArray = only.split(",", false)
	for token: String in tokens:
		var hit: bool = false
		for shot: Dictionary in _SHOTS:
			var shot_name: String = shot.name
			if shot_name == token or shot_name.begins_with(token + "_"):
				hit = true
				if not picked.has(shot):
					picked.append(shot)
		if not hit:
			var names: PackedStringArray = []
			for shot: Dictionary in _SHOTS:
				names.append(shot.name)
			push_error("[ui-preview] no shot matches '%s'; shots: %s" % [token, ", ".join(names)])
			return []
	# Table order, not argument order: it is what keeps a stage to one load.
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _SHOTS.find(a) < _SHOTS.find(b))
	return picked


func _enter_stage(stage: String) -> void:
	var tree: SceneTree = get_tree()
	# The side menu's own teardown before it launches a scene.
	if _stage != "" and _stage != _STAGE_BOOT:
		GameManager.on_scene_exit()
		NetworkSimManager.clear_pending()
		NetworkManager.reset()
	var path: String = Constants.SCENE_HOCKEY
	match stage:
		_STAGE_BOOT:
			path = Constants.SCENE_BOOT
		_STAGE_FREE_PLAY:
			NetworkManager.start_free_play()
		_STAGE_TUTORIAL:
			NetworkManager.start_tutorial(TutorialRegistry.MOVEMENT_ID)
		_STAGE_LOBBY, _STAGE_MATCH:
			NetworkManager.start_offline()
			path = Constants.SCENE_LOBBY
	_stage = stage
	tree.change_scene_to_file(path)
	while tree.current_scene == null or tree.current_scene.scene_file_path != path:
		await tree.process_frame
	if stage == _STAGE_MATCH:
		await _start_match()
	# Bottom centre is below every menu column and dialog, so no shot catches a
	# button in its hover state.
	var view: Vector2 = get_viewport().get_visible_rect().size
	Input.warp_mouse(view * Vector2(0.5, 0.97))
	await _settle(_STAGE_SETTLE_FRAMES, _STAGE_SETTLE_SEC)


# From the offline lobby: the host's Fill with Bots and Start Game, then play
# until the opening faceoff is well behind.
func _start_match() -> void:
	var tree: SceneTree = get_tree()
	var lobby: LobbyManager = _find(tree.current_scene, LobbyManager) as LobbyManager
	_invoke(lobby, "_fill_open_slots_with_bots")
	_invoke(lobby, "_on_start_pressed")
	var waited: int = 0
	while tree.current_scene == null \
			or tree.current_scene.scene_file_path != Constants.SCENE_HOCKEY \
			or GameManager.is_movement_locked():
		await tree.process_frame
		waited += 1
		if waited > _MATCH_START_TIMEOUT_FRAMES:
			_fail("the match never left the opening faceoff")
			return
	var default_steps: int = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = _MATCH_STEPS_PER_FRAME
	var target: int = Engine.get_physics_frames() \
			+ int(_MATCH_PLAY_SEC * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < target:
		await tree.process_frame
	Engine.max_physics_steps_per_frame = default_steps


func _settle(frames: int, seconds: float) -> void:
	var start_ms: int = Time.get_ticks_msec()
	var n: int = 0
	while n < frames or Time.get_ticks_msec() - start_ms < int(seconds * 1000.0):
		await get_tree().process_frame
		n += 1


func _snap(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir.path_join(shot_name + ".png")
	if img.save_png(path) != OK:
		_fail("could not write %s" % path)
		return
	print("[ui-preview] %s %dx%d -> %s" % [shot_name, img.get_width(), img.get_height(),
			ProjectSettings.globalize_path(path)])


# Escape until the stage is back at rest — the player's own way out.
func _dismiss(shot_name: String) -> void:
	for i: int in _MAX_DISMISS_PRESSES:
		if not _overlay_open():
			return
		for pressed: bool in [true, false]:
			var ev := InputEventAction.new()
			ev.action = &"ui_cancel"
			ev.pressed = pressed
			Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
	if _overlay_open():
		_fail("Escape did not close what %s opened; reloading the stage" % shot_name)
		var stage: String = _stage
		_stage = ""
		await _enter_stage(stage)


func _overlay_open() -> bool:
	match _stage:
		_STAGE_BOOT:
			var options: Control = _boot().get("_settings_container") as Control
			return options != null and options.visible
		_STAGE_FREE_PLAY:
			var side: SideMenu = _find(get_tree().current_scene, SideMenu) as SideMenu
			var analytics: PostGameAnalytics = _find(get_tree().current_scene,
					PostGameAnalytics) as PostGameAnalytics
			return (side != null and side.visible) \
					or (analytics != null and analytics.visible)
	return false


func _fail(message: String) -> void:
	push_error("[ui-preview] " + message)
	_shot_ok = false
	_failed = true


func _invoke(target: Object, method: String) -> void:
	if target == null:
		_fail("nothing to call %s on" % method)
	elif not target.has_method(method):
		_fail("%s no longer has %s" % [target.get_class(), method])
	else:
		target.call(method)


func _find(node: Node, cls: Script) -> Node:
	if node == null:
		return null
	if is_instance_of(node, cls):
		return node
	for child: Node in node.get_children():
		var hit: Node = _find(child, cls)
		if hit != null:
			return hit
	return null


func _boot() -> Boot:
	return get_tree().current_scene as Boot


# --- Openers ----------------------------------------------------------------

func _open_nothing() -> void:
	pass


func _open_boot_options(tab: int) -> void:
	var boot: Boot = _boot()
	_invoke(boot, "_on_settings_pressed")
	var panel: OptionsPanel = _find(boot, OptionsPanel) as OptionsPanel
	if panel == null:
		_fail("Boot has no OptionsPanel")
		return
	panel.call("_activate_tab", tab)


# The Video tab scrolled to its Performance section, where the cost notes are.
func _open_video_performance() -> void:
	_open_boot_options(2)
	await _settle(2, 0.0)
	var tab: OptionsVideoTab = _find(_boot(), OptionsVideoTab) as OptionsVideoTab
	var scroll: ScrollContainer = null
	var up: Node = tab
	while up != null and scroll == null:
		scroll = up as ScrollContainer
		up = up.get_parent()
	if scroll == null:
		_fail("the Video tab is not in a ScrollContainer")
		return
	var header: Label = null
	var rating: Control = null
	for child: Node in tab.get_children():
		if child is Label and (child as Label).text == "PERFORMANCE":
			header = child as Label
		elif child is HBoxContainer \
				and ((child as HBoxContainer).get_child(0) as Label).text == "Shadow Quality":
			rating = (child as HBoxContainer).get_child(child.get_child_count() - 1) as Control
	if header == null or rating == null or not rating.has_meta(&"impact"):
		_fail("the Video tab has no PERFORMANCE section with a rated Shadow Quality")
		return
	scroll.scroll_vertical = int(header.position.y)
	await _settle(2, 0.0)
	# Hovered, so the shot shows a rating's explanation as a player gets it.
	var hover := InputEventMouseMotion.new()
	hover.position = rating.get_global_rect().get_center()
	get_viewport().push_input(hover)
	await _settle(2, ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5) + 0.3)


func _open_side_menu(handler: String) -> void:
	var side: SideMenu = _find(get_tree().current_scene, SideMenu) as SideMenu
	if side == null:
		_fail("free play has no SideMenu")
		return
	side.open()
	if not handler.is_empty():
		_invoke(side, handler)


func _close_side_menu() -> void:
	var side: SideMenu = _find(get_tree().current_scene, SideMenu) as SideMenu
	if side == null:
		_fail("free play has no SideMenu")
		return
	side.close()


func _open_player_region(region: int) -> void:
	_open_side_menu("_on_player_card_pressed")
	var popup: PlayerSettingsPopup = _find(get_tree().current_scene, PlayerSettingsPopup) \
			as PlayerSettingsPopup
	if popup == null:
		_fail("the side menu has no PlayerSettingsPopup")
		return
	popup.call("_show_region", region)


# A past game's analytics, as the career screen opens a local replay: a fixed
# made-up game, so the picture changes only when the screen does.
func _open_post_game_analytics() -> void:
	_close_side_menu()
	var screen: PostGameAnalytics = _find(get_tree().current_scene, PostGameAnalytics) \
			as PostGameAnalytics
	if screen == null:
		_fail("free play has no PostGameAnalytics")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var events: Array[ShotEvent] = []
	for i: int in 46:
		var team: int = 0 if rng.randf() < 0.55 else 1
		var goal_z: float = -GameRules.GOAL_LINE_Z if team == 0 else GameRules.GOAL_LINE_Z
		var along: float = rng.randf_range(1.5, GameRules.GOAL_LINE_Z - GameRules.BLUE_LINE_Z)
		var pos := Vector3(rng.randf_range(-9.0, 9.0), 0.0, goal_z - signf(goal_z) * along)
		var xg: float = clampf(0.7 * exp(-pos.distance_to(Vector3(0.0, 0.0, goal_z)) / 4.5),
				0.02, 0.6)
		var roll: float = rng.randf()
		var outcome: int = ShotEvent.Outcome.GOAL if roll < xg * 0.9 \
				else ShotEvent.Outcome.SAVED if roll < 0.55 \
				else ShotEvent.Outcome.MISSED if roll < 0.8 else ShotEvent.Outcome.BLOCKED
		events.append(ShotEvent.make(-1, team, pos, xg, outcome, ShotEvent.ShotType.SHOT,
				outcome <= ShotEvent.Outcome.SAVED, 1 + i % 3, rng.randf_range(0.0, 300.0)))
	var box: Array = [
		{"team_id": 0, "hits": 9, "takeaways": 6, "giveaways": 5,
				"faceoff_wins": 11, "faceoff_losses": 8},
		{"team_id": 1, "hits": 13, "takeaways": 3, "giveaways": 8,
				"faceoff_wins": 8, "faceoff_losses": 11},
	]
	screen.present_history(events, -1, -1, "preview game", [], box)
