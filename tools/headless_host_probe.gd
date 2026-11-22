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
#   --server            host as a dedicated server (default: a player's machine,
#                       its host in a spectator seat)
#   --no-ot             a tie ends the match (default: overtime, which runs
#                       until a goal and so has no fixed length)
#   --free=<a,b>        node paths under the match scene to free before the
#                       match plays (Hud, RinkArena/ArenaStands): what each costs
#   --look-away         mount a camera that sees no skater, so each takes the
#                       off-camera path: what the mesh pass costs
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
	var opts: Dictionary = {
		"team_size": 5, "period_s": 40.0, "periods": 3, "timeout_s": 600.0, "max_fps": 0,
		"as_server": false, "overtime": true, "free": PackedStringArray(), "look_away": false,
	}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--team-size="):
			opts.team_size = int(a.trim_prefix("--team-size="))
		elif a.begins_with("--period="):
			opts.period_s = float(a.trim_prefix("--period="))
		elif a.begins_with("--periods="):
			opts.periods = int(a.trim_prefix("--periods="))
		elif a.begins_with("--timeout="):
			opts.timeout_s = float(a.trim_prefix("--timeout="))
		elif a.begins_with("--max-fps="):
			opts.max_fps = int(a.trim_prefix("--max-fps="))
		elif a == "--server":
			opts.as_server = true
		elif a == "--no-ot":
			opts.overtime = false
		elif a == "--look-away":
			opts.look_away = true
		elif a.begins_with("--free="):
			opts.free = a.trim_prefix("--free=").split(",", false)
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin", opts)
