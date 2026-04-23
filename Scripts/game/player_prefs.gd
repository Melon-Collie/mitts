extends Node

const SAVE_PATH: String = "user://preferences.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const FPS_CAP_VALUES: Array[int] = [30, 60, 120, 144, 240, 0]

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
	cfg.save(SAVE_PATH)

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
	if cfg.load(SAVE_PATH) != OK:
		return
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
	apply_audio()
	call_deferred(&"apply_video")
