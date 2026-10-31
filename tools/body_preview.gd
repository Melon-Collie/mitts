extends SceneTree

# Renders the skater's body (SkaterConnectedMesh) pose by pose from four sides,
# one sheet per pose, to .preview/body/.
#
#   .claude/hooks/render-body.sh                 # every pose in the set
#   .claude/hooks/render-body.sh --only=stride,rest   # poses whose name contains one
#   .claude/hooks/render-body.sh --pants         # the pants alone
#   .claude/hooks/render-body.sh --audit         # + count faces folded inside out
#   BODY_AUDIT_ZONE=33 ... --audit               # + list one zone's folded faces
#   .claude/hooks/render-body.sh --head          # framed on the helmet
#   .claude/hooks/render-body.sh --waist         # framed on the belt: the tuck
#   .claude/hooks/render-body.sh --skate         # framed on the near skate
#   BODY_PREVIEW_KIT=1,1 ...                     # in slot 1's away kit
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
	runner.call("begin_preview", only, args.has("--pants"),
			args.has("--audit"), args.has("--head"), args.has("--waist"),
			args.has("--skate"))
