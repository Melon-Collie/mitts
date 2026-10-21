extends SceneTree

# What each Video setting costs, measured in a live 5v5 against bots on the
# Forward+ renderer — the numbers the Options → Video notes are written from.
# Wraps tools/graphics_cost_runner.gd; run it through
# .claude/hooks/measure-graphics.sh, which picks the GPU (a real one locally,
# software Vulkan in a web session).
#
#   --only=<labels>  comma-separated condition labels or prefixes ("shadows")
#   --list           print the condition list
#   --out=<path>     markdown table (default user://graphics_cost.md)
#
# This file is only a bootstrap, for the reason pose_capture.gd gives: a `-s`
# script compiles before the autoloads register, so the typed runner is loaded
# once the tree is up.
const RUNNER: String = "res://tools/graphics_cost_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var only: String = ""
	var out_path: String = "user://graphics_cost.md"
	var list_only: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a == "--list":
			list_only = true
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin", only, out_path, list_only)
