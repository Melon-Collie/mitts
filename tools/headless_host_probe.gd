extends SceneTree

# Plays a whole match on a host that has no skater of its own, headless, and
# reports whether it reached GAME_OVER: the question a dedicated server asks of
# the host path (docs/dedicated-server-plan.md). Wraps
# tools/headless_host_probe_runner.gd; run it through
# .claude/hooks/probe-headless-host.sh.
#
#   --team-size=<3|5>   skaters a side, all bots (default 5)
#   --period=<sec>      period length (default 40)
#   --periods=<n>       periods (default 3)
#   --timeout=<sec>     wall-clock limit on the whole run (default 600)
#   --max-fps=<n>       cap the process step during the match (default: the prefs' cap)
#
# A bootstrap only, for the reason pose_capture.gd gives: a `-s` script compiles
# before the autoloads register, so the typed runner is loaded once the tree is up.
const RUNNER: String = "res://tools/headless_host_probe_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var team_size: int = 5
	var period_s: float = 40.0
	var periods: int = 3
	var timeout_s: float = 600.0
	var max_fps: int = 0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--team-size="):
			team_size = int(a.trim_prefix("--team-size="))
		elif a.begins_with("--period="):
			period_s = float(a.trim_prefix("--period="))
		elif a.begins_with("--periods="):
			periods = int(a.trim_prefix("--periods="))
		elif a.begins_with("--timeout="):
			timeout_s = float(a.trim_prefix("--timeout="))
		elif a.begins_with("--max-fps="):
			max_fps = int(a.trim_prefix("--max-fps="))
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin", team_size, period_s, periods, timeout_s, max_fps)
