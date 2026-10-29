extends SceneTree

# Dev visualizer: close-ups of a dressed skater's upper body — the jersey, the
# shoulders, the yoke, the sleeves and elbows — in several kits, from the
# front, back, side, three-quarter and the game camera. One row per kit in one
# sheet. For judging how a kit sits on the body; kit_capture.gd lays the same
# paint out flat.
#
#   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --path . \
#       --rendering-driver opengl3 --rendering-method gl_compatibility \
#       --audio-driver Dummy -s res://tools/uniform_study.gd
#
# UNIFORM_STUDY_OUT sets the output directory (default user://uniform_study);
# UNIFORM_STUDY_KITS and UNIFORM_STUDY_POSES pick the rows and
# UNIFORM_STUDY_SHOTS the columns (see the runner).
# A two-line bootstrap for the same reason as pose_capture.gd: the work names
# Skater and SkaterController, which only compile once the autoloads are up.
const RUNNER: String = "res://tools/uniform_study_runner.gd"
const TILE: int = 512

var _started: bool = false


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(TILE, TILE))
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin")
