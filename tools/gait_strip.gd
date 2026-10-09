extends SceneTree

# Renders the skating gait as STRIPS: a scenario skated through the real
# controller, captured every few ticks from behind, beside and ahead of the
# skater, one column per capture. Where render-poses.sh holds a pose, this shows
# a stroke — which skate goes where over a cycle, and when a state comes on. It
# also prints the locomotion mix at each capture, so a strip says which state
# the legs were skating as well as what it looked like.
#
#   .claude/hooks/render-strip.sh                      # every scenario
#   .claude/hooks/render-strip.sh turn45,keyD          # named scenarios only
#
# Scenarios and framing live in tools/gait_strip_runner.gd. PNGs go to
# user://gait_strip (never the repo tree; the path prints on save).
#
# A two-line bootstrap for the same reason as tools/pose_capture.gd: the runner
# names Skater and friends, which only compile once the autoloads exist.
const RUNNER: String = "res://tools/gait_strip_runner.gd"
const TILE: int = 320

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
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	runner.call("begin", only)
