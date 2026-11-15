extends SceneTree

# Staged own-goal trials in an all-bot match: a loose puck behind and beside a
# net, that team's defenseman coming to it (tools/own_goal_stage_runner.gd).
# Run it through .claude/hooks/stage-own-goals.sh. A -s script compiles before
# the autoloads register, so the typed runner is loaded once the tree is up.
#
#   --team-size=<3|5>   (default 5)
#   --side=<left|right|both>  which side of the net the puck goes (default both)
const RUNNER: String = "res://tools/own_goal_stage_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var team_size: int = 5
	var sides: Array[float] = [1.0, -1.0]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--team-size="):
			team_size = int(a.trim_prefix("--team-size="))
		elif a == "--side=left":
			sides = [-1.0]
		elif a == "--side=right":
			sides = [1.0]
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin_staged", team_size, sides)
