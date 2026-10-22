extends SceneTree

# Renders the puck's drawn attitude as STRIPS: the real Puck driven by the
# host's analytic drive through a scripted situation — a board glance, a
# landing, a mid-air deflection, a release off a blade — captured every few
# ticks by a camera that follows it, with PuckSpinRig's state printed per
# frame. The spin, wobble and tumble are cosmetic, so this is how a change to
# them is seen without playing.
#
#   .claude/hooks/render-puck.sh                  # every scenario
#   .claude/hooks/render-puck.sh board,deflect    # named scenarios only
#   .claude/hooks/render-puck.sh --list           # the scenario names
#
# Scenarios and framing live in tools/puck_strip_runner.gd. PNGs go to
# PUCK_STRIP_OUT (default user://puck_strip; the hook points it at
# .preview/puck).
#
# A two-line bootstrap for the same reason as tools/gait_strip.gd: the runner
# names Puck and friends, which only compile once the autoloads exist.
const RUNNER: String = "res://tools/puck_strip_runner.gd"

var _started: bool = false


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(320, 240))
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
