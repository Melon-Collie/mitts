extends Node

const SAVE_PATH: String = "user://preferences.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const FPS_CAP_VALUES: Array[int] = [30, 60, 120, 144, 240, 0]
const REBINDABLE_ACTIONS: PackedStringArray = [
	"move_up", "move_down", "move_left", "move_right", "brake",
	"shoot", "slapshot", "self_pass", "self_shot", "block",
	"elevation_up", "elevation_down", "reset",
]

var player_name: String = "Player"
var jersey_number: int = 10
var is_left_handed: bool = true
var last_ip: String = ""
var master_volume: float = 1.0
var master_muted: bool = false
var is_fullscreen: bool = false
var resolution_index: int = 1
var vsync_enabled: bool = true
var fps_cap_index: int = 5
var brightness: float = 1.0
var mouse_sensitivity: float = 1.0
var bindings: Dictionary = {}  # action -> {type, physical_keycode or button_index}

func _ready() -> void:
	_load()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "jersey_number", jersey_number)
	cfg.set_value("player", "left_handed", is_left_handed)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("video", "fullscreen", is_fullscreen)
	cfg.set_value("video", "resolution_index", resolution_index)
	cfg.set_value("video", "vsync_enabled", vsync_enabled)
	cfg.set_value("video", "fps_cap_index", fps_cap_index)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	for action: String in REBINDABLE_ACTIONS:
		if not bindings.has(action):
			continue
		var b: Dictionary = bindings[action]
		var t: String = b.get("type", "")
		cfg.set_value("bindings", action + "_type", t)
		if t == "key":
			cfg.set_value("bindings", action + "_code", b.get("physical_keycode", 0))
		elif t == "mouse":
			cfg.set_value("bindings", action + "_code", b.get("button_index", 0))
	cfg.save(SAVE_PATH)

func apply_bindings() -> void:
	for action: String in bindings:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		var b: Dictionary = bindings[action]
		if b.get("type") == "key":
			var ev := InputEventKey.new()
			ev.physical_keycode = b.physical_keycode as Key
			InputMap.action_add_event(action, ev)
		elif b.get("type") == "mouse":
			var ev := InputEventMouseButton.new()
			ev.button_index = b.button_index as MouseButton
			InputMap.action_add_event(action, ev)

func _read_current_input_event(action: String) -> Dictionary:
	if not InputMap.has_action(action):
		return {}
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return {"type": "key", "physical_keycode": int((ev as InputEventKey).physical_keycode)}
		elif ev is InputEventMouseButton:
			return {"type": "mouse", "button_index": int((ev as InputEventMouseButton).button_index)}
	return {}

func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, master_muted)

func apply_video() -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RESOLUTIONS[resolution_index])
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_CAP_VALUES[fps_cap_index]
	var we := Engine.get_main_loop().current_scene.find_child(
		"WorldEnvironment", true, false) as WorldEnvironment
	if we != null:
		we.environment.adjustment_enabled = true
		we.environment.adjustment_brightness = brightness

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		player_name = cfg.get_value("player", "name", "Player").substr(0, 10)
		if player_name.strip_edges().is_empty():
			player_name = "Player"
		jersey_number = clamp(cfg.get_value("player", "jersey_number", 10), 0, 99)
		is_left_handed = cfg.get_value("player", "left_handed", true)
		last_ip = cfg.get_value("player", "last_ip", "")
		master_volume = clampf(cfg.get_value("audio", "master_volume", 1.0), 0.0, 1.0)
		master_muted = cfg.get_value("audio", "master_muted", false)
		is_fullscreen = cfg.get_value("video", "fullscreen", false)
		resolution_index = clamp(cfg.get_value("video", "resolution_index", 1), 0, RESOLUTIONS.size() - 1)
		vsync_enabled = cfg.get_value("video", "vsync_enabled", true)
		fps_cap_index = clamp(cfg.get_value("video", "fps_cap_index", 5), 0, FPS_CAP_VALUES.size() - 1)
		brightness = clampf(cfg.get_value("video", "brightness", 1.0), 0.5, 1.5)
		mouse_sensitivity = clampf(cfg.get_value("input", "mouse_sensitivity", 1.0), 0.5, 3.0)
		for action: String in REBINDABLE_ACTIONS:
			var t: String = cfg.get_value("bindings", action + "_type", "")
			if t == "key":
				bindings[action] = {"type": "key", "physical_keycode": cfg.get_value("bindings", action + "_code", 0)}
			elif t == "mouse":
				bindings[action] = {"type": "mouse", "button_index": cfg.get_value("bindings", action + "_code", 0)}
	# Fill in InputMap defaults for any action not in the saved config
	for action: String in REBINDABLE_ACTIONS:
		if not bindings.has(action):
			var b: Dictionary = _read_current_input_event(action)
			if not b.is_empty():
				bindings[action] = b
	apply_audio()
	apply_bindings()
	call_deferred(&"apply_video")
