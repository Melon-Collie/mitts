extends SceneTree

# Candidate gameplay-camera rigs (camera_rigs.gd), measured and rendered: a table
# of how each maps the aim cursor onto the ice, then a live 3v3 frozen at a few
# moments and shot from every rig. Run through .claude/hooks/render-camera-rigs.sh.
#
# `--only=` takes rig names; `--measure` writes the table and stops (no renderer
# needed); `--out=` is the output directory (default user://camera_rigs).
#
# Only a bootstrap, for the reason ui_preview.gd gives.
const RUNNER: String = "res://tools/camera_rig_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var only: String = ""
	var out_dir: String = "user://camera_rigs"
	var measure_only: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a == "--measure":
			measure_only = true
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin", only, out_dir, measure_only)
