extends SceneTree

# Bot-vs-bot matches, headless, watching for own goals. Bootstrap for
# tools/own_goal_hunt_runner.gd (a -s script compiles before the autoloads
# register, so the typed runner is loaded once the tree is up).
#
#   --team-size=<3|5>   (default 3)
#   --seconds=<n>       live-play seconds to watch (default 600)
const RUNNER: String = "res://tools/own_goal_hunt_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var team_size: int = 3
	var seconds: float = 600.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--team-size="):
			team_size = int(a.trim_prefix("--team-size="))
		elif a.begins_with("--seconds="):
			seconds = float(a.trim_prefix("--seconds="))
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin", team_size, seconds)
