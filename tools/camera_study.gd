extends SceneTree

# Offscreen camera study: plays an offline match against bots until someone
# carries the puck through open ice and renders that instant from
# the live GameCamera and from a grid of pitch / FOV / scale setups, one PNG
# each, plus a metrics JSON.
#
#   .claude/hooks/render-camera.sh                 # every setup
#   .claude/hooks/render-camera.sh --list          # print the setups
#
# A bootstrap only, for the reason pose_capture.gd gives: a `-s` script
# compiles before the autoloads register. The work is in camera_study_runner.gd.
const RUNNER: String = "res://tools/camera_study_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var out_dir: String = "user://camera_study"
	var only: String = ""
	var list_only: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a == "--list":
			list_only = true
	var script: GDScript = load(RUNNER) as GDScript
	if script == null or not script.can_instantiate():
		push_error("[camera-study] %s failed to load" % RUNNER)
		quit(1)
		return
	var runner: Node = script.new() as Node
	root.add_child(runner)
	runner.call("begin", only, out_dir, list_only)
