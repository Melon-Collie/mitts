extends SceneTree

# Renders the connected-body prototype (SkaterConnectedMesh) beside the rig's
# current body, pose by pose, from four sides: one sheet per pose, the current
# body on the top row and the connected one under it, to .preview/body/.
#
#   .claude/hooks/render-body.sh                 # every pose in the set
#   .claude/hooks/render-body.sh --only=stride,rest   # poses whose name contains one
#   .claude/hooks/render-body.sh --new-only      # skip the current body's row
#   .claude/hooks/render-body.sh --pants         # the connected pants alone
#   .claude/hooks/render-body.sh --audit         # + count faces folded inside out
#
# Bootstrapped like pose_capture.gd, for the same reason: the runner names
# classes that need the autoloads up before they compile.
const RUNNER: String = "res://tools/body_preview_runner.gd"
const TILE: int = 448

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
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var only: String = ""
	for a: String in args:
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	runner.call("begin_preview", only, args.has("--new-only"), args.has("--pants"),
			args.has("--audit"))
