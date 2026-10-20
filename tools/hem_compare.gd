extends SceneTree

# Dev comparison: every jersey-hem sim (HemSimMode) skated through one scripted
# run side by side — see hem_compare_runner.gd. Run through
# .claude/hooks/render-hem.sh; output paths print on save (user://).
#
# A two-line bootstrap for the reason pose_capture.gd gives: the real work names
# Skater and SkaterController, which only compile once the autoloads exist.
const RUNNER: String = "res://tools/hem_compare_runner.gd"

var _started: bool = false


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(64, 64))
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin")
