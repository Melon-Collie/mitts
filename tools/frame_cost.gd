extends SceneTree

# What the main thread spends on a live match against bots, by skater count —
# measured headless, so nothing is drawn and the frame is the CPU's alone.
# Wraps tools/frame_cost_runner.gd; run it through
# .claude/hooks/measure-frame-cost.sh, which sweeps the skater counts.
#
#   --skaters=<n>   skaters on the ice, 2..10 (the local player and n - 1 bots)
#   --frames=<n>    live-play frames to sample (default 1200)
#
# A bootstrap only, for the reason pose_capture.gd gives: a `-s` script compiles
# before the autoloads register, so the typed runner is loaded once the tree is up.
const RUNNER: String = "res://tools/frame_cost_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var skaters: int = 10
	var frames: int = 1200
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--skaters="):
			skaters = int(a.trim_prefix("--skaters="))
		elif a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin", skaters, frames)
