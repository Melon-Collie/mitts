extends SceneTree

# Renders what the arm anatomy model makes of each reference carry; see
# tools/arm_reference_runner.gd. The hook is .claude/hooks/render-references.sh.
#
# A bootstrap for the same reason as tools/gait_strip.gd: the runner names
# Skater and friends, which only compile once the autoloads exist.
const RUNNER: String = "res://tools/arm_reference_runner.gd"

var _started: bool = false


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(360, 360))
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	var only: String = ""
	var list: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a == "--list":
			list = true
	runner.call("begin", only, list)
