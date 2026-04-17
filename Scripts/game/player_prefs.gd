extends Node

const SAVE_PATH: String = "user://preferences.cfg"

var player_name: String = "Player"
var is_left_handed: bool = true
var last_ip: String = ""

func _ready() -> void:
	_load()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "left_handed", is_left_handed)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	player_name = cfg.get_value("player", "name", "Player")
	is_left_handed = cfg.get_value("player", "left_handed", true)
	last_ip = cfg.get_value("player", "last_ip", "")
