extends Node

const SAVE_PATH: String = "user://preferences.cfg"

var player_name: String = "Player"
var jersey_number: int = 10
var is_left_handed: bool = true
var last_ip: String = ""
var master_volume: float = 1.0
var master_muted: bool = false

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
	cfg.save(SAVE_PATH)

func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, master_muted)

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
	apply_audio()
