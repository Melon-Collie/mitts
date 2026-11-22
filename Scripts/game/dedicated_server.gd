class_name DedicatedServer
extends Node

# One match on a dedicated server, start to exit: read a MatchConfig, start the
# match from it, wait for GAME_OVER, print the result and quit
# (docs/dedicated-server-plan.md). Boot adds one in place of the title card when
# the process was launched as a server:
#
#   godot --headless -- --server --match-config=<file.json>
#   MITTS_MATCH_CONFIG='<json>' godot --headless -- --server

const LAUNCH_ARG: String = "--server"
const CONFIG_ARG: String = "--match-config="
const CONFIG_ENV: String = "MITTS_MATCH_CONFIG"

# What the process exits with, for whatever started it.
const EXIT_OK: int = 0
const EXIT_BAD_CONFIG: int = 2
const EXIT_NEVER_STARTED: int = 3

# The line the result is printed on, for whatever reads the log.
const RESULT_TAG: String = "[server] result "

# Loading the match scene takes a few seconds on a cold disk; a server still
# without one after this long is not going to get one.
const _START_TIMEOUT_S: float = 60.0
# After GAME_OVER, before quitting: the final stats go out on a reliable
# channel, and a quit drops what has not left yet.
const _RESULT_FLUSH_S: float = 3.0

var _match_up: bool = false


static func launch_requested() -> bool:
	return LAUNCH_ARG in OS.get_cmdline_user_args()


# The config the process was launched with: a file named on the command line,
# or JSON in the environment. A launch that names neither is a problem, not a
# default match — a server nobody configured should not sit there playing one.
static func read_config() -> MatchConfig:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(CONFIG_ARG):
			continue
		var path: String = arg.trim_prefix(CONFIG_ARG)
		if not FileAccess.file_exists(path):
			return MatchConfig.unusable("no file at %s" % path)
		return MatchConfig.from_json(FileAccess.get_file_as_string(path))
	if OS.has_environment(CONFIG_ENV):
		return MatchConfig.from_json(OS.get_environment(CONFIG_ENV))
	return MatchConfig.unusable("none given: pass %s<file> or set %s" % [CONFIG_ARG, CONFIG_ENV])


# Starts `config`'s match on this machine as a server. The match scene loads on
# the next frame.
static func start_match(config: MatchConfig) -> void:
	NetworkManager.start_server()
	NetworkManager.pending_bot_difficulty = config.bot_difficulty
	NetworkManager.pending_goalie_difficulty = config.goalie_difficulty
	for seat: MatchConfig.Seat in config.bot_seats():
		NetworkManager.send_bot_slot(seat.slot_key(), true)
	var start: Dictionary = config.to_game_start()
	NetworkManager.send_game_start(start)
	NetworkManager.pending_game_config = start
	# About a tick a frame. Slower, and the ticks a frame owes run back to back
	# and their snapshots leave in one clump.
	Engine.max_fps = Engine.physics_ticks_per_second
	(Engine.get_main_loop() as SceneTree).change_scene_to_file(Constants.SCENE_HOCKEY)


func _ready() -> void:
	var config: MatchConfig = read_config()
	if not config.problem().is_empty():
		push_error("[server] bad match config: %s" % config.problem())
		get_tree().quit(EXIT_BAD_CONFIG)
		return
	if config.game_id.is_empty():
		config.game_id = PlayerPrefs.generate_uuid()
	print("[server] starting %s: %dv%d, %d bots, %d seats for players" % [
			config.game_id, config.team_size, config.team_size,
			config.bot_seats().size(), config.human_seats().size()])
	NetworkManager.host_ready.connect(func() -> void: _match_up = true, CONNECT_ONE_SHOT)
	GameManager.game_over.connect(_on_game_over, CONNECT_ONE_SHOT)
	get_tree().create_timer(_START_TIMEOUT_S).timeout.connect(_on_start_timeout)
	start_match(config)


func _on_start_timeout() -> void:
	if _match_up:
		return
	push_error("[server] the match scene never came up")
	get_tree().quit(EXIT_NEVER_STARTED)


func _on_game_over() -> void:
	get_tree().create_timer(_RESULT_FLUSH_S).timeout.connect(_report_and_quit)


func _report_and_quit() -> void:
	print(RESULT_TAG + JSON.stringify(GameManager.match_result()))
	get_tree().quit(EXIT_OK)
