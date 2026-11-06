extends SceneTree

# How often the hands gameplay places can be held, in a live match against bots
# (docs/held-hands-plan.md, phase 1). Wraps tools/hold_sample_runner.gd:
#
#   godot --headless --path . -s res://tools/hold_sample.gd -- [--skaters=<n>] [--seconds=<s>]
#
# A bootstrap only, as tools/frame_cost.gd is: a `-s` script compiles before the
# autoloads register, so the typed runner is loaded once the tree is up.
const RUNNER: String = "res://tools/hold_sample_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var skaters: int = 10
	var seconds: float = 60.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--skaters="):
			skaters = int(a.trim_prefix("--skaters="))
		elif a.begins_with("--seconds="):
			seconds = float(a.trim_prefix("--seconds="))
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("sample", skaters, seconds)
