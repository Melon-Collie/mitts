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

const _SHOTS: Array[Dictionary] = [
	{"name": "boot", "stage": _STAGE_BOOT, "open": "_open_nothing"},
	{"name": "options_gameplay", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 0},
	{"name": "options_camera", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 1},
	{"name": "options_video", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 2},
	{"name": "options_audio", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 3},
	{"name": "options_controls", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 4},
	{"name": "options_accessibility", "stage": _STAGE_BOOT, "open": "_open_boot_options", "arg": 5},
	# Free play lands with the side menu open; this is that landing, so it runs
	# before side_player dismisses the first-run callout on the player card.
	{"name": "side_menu", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": ""},
	{"name": "side_play", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_play_pressed"},
	{"name": "side_player", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_player_card_pressed"},
	{"name": "side_locker", "stage": _STAGE_FREE_PLAY, "open": "_open_locker"},
	{"name": "side_career", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_career_pressed"},
	{"name": "side_tutorials", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_tutorial_pressed"},
	{"name": "side_drills", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_drills_pressed"},
	{"name": "side_options", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_options_pressed"},
	{"name": "side_exit", "stage": _STAGE_FREE_PLAY, "open": "_open_side_menu", "arg": "_on_exit_pressed"},
	{"name": "hud_free_play", "stage": _STAGE_FREE_PLAY, "open": "_close_side_menu"},
	{"name": "hud_tutorial", "stage": _STAGE_TUTORIAL, "open": "_open_nothing"},
	{"name": "lobby", "stage": _STAGE_LOBBY, "open": "_open_nothing"},
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
# Deepest overlay stack a shot opens (locker over player settings over the side
# menu), plus slack.
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
			var name: String = shot.name
			if name == token or name.begins_with(token + "_"):
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
		_STAGE_LOBBY:
			NetworkManager.start_offline()
			path = Constants.SCENE_LOBBY
	_stage = stage
	tree.change_scene_to_file(path)
	while tree.current_scene == null or tree.current_scene.scene_file_path != path:
		await tree.process_frame
	# Bottom centre is below every menu column and dialog, so no shot catches a
	# button in its hover state.
	var view: Vector2 = get_viewport().get_visible_rect().size
	Input.warp_mouse(view * Vector2(0.5, 0.97))
	await _settle(_STAGE_SETTLE_FRAMES, _STAGE_SETTLE_SEC)


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
			return side != null and side.visible
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


func _open_locker() -> void:
	_open_side_menu("_on_player_card_pressed")
	var popup: PlayerSettingsPopup = _find(get_tree().current_scene, PlayerSettingsPopup) \
			as PlayerSettingsPopup
	_invoke(popup, "_open_locker")
