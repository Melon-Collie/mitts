extends SceneTree

# Offscreen renderer for the menus and HUD — what a headless test cannot say
# about a screen is how it reads. Drives the real scenes (Boot, Hockey in free
# play and the tutorial, the offline Lobby) through a list of named shots, opens
# each overlay through the handler its button calls, and writes one PNG a shot.
#
#   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . \
#       --rendering-driver opengl3 --rendering-method gl_compatibility \
#       --audio-driver Dummy -s res://tools/ui_preview.gd -- --only=boot,side
#
# `--only=` takes shot names or group prefixes (`options` matches every
# `options_*` shot); `--list` prints the shot list; `--out=` is the output
# directory (default user://ui_preview). The shot list is in ui_preview_runner.gd.
#
# This file is only a bootstrap, for the reason pose_capture.gd gives: a `-s`
# script compiles before the autoloads register, so the typed runner is loaded
# once the tree is up.
const RUNNER: String = "res://tools/ui_preview_runner.gd"

var _started: bool = false


func _init() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _started:
		return
	_started = true
	var only: String = ""
	var out_dir: String = "user://ui_preview"
	var list_only: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a == "--list":
			list_only = true
	var runner: Node = (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
	runner.call("begin", only, out_dir, list_only)
