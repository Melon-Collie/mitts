extends SceneTree

# Sweeps the cursor round a carrier and draws the arms at each step, with a
# readout per frame of how close each arm comes to the torso and how the shaft
# sits in each glove; the skating scenarios also trace the blade against the
# cursor tick by tick, which is where a turn that catches shows.
#
#   .claude/hooks/render-arms.sh [scenario,scenario] [--tile=512]   # --list prints them
#
# A two-line bootstrap for the reason pose_capture.gd gives: the runner names
# Skater and SkaterController, which only compile once the autoloads exist.
const RUNNER: String = "res://tools/arm_sweep_runner.gd"
const TILE: int = 256

var _started: bool = false


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(_tile(), _tile()))
	process_frame.connect(_on_frame)


# Each view's size in pixels, square: --tile=N, for a pose that needs reading
# closer than the sheet's default.
func _tile() -> int:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tile="):
			return maxi(int(a.trim_prefix("--tile=")), 64)
	return TILE


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	var only: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	runner.set("tile", _tile())
	runner.call("begin", only, args.has("--list"))
