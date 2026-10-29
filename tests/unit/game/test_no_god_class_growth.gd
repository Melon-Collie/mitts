extends GutTest

# Two limits on the shape of Scripts/: how long a file may be, and how wide its
# public surface may be. A file not listed below must stay under the limit.
#
# The lists are the files already over a limit, named without a number: they may
# grow or shrink freely, so ordinary work inside them never touches this file and
# concurrent branches never conflict here. What the guard stops is a NEW god
# class — a file crossing the limit for the first time. Adding it to a list is
# allowed when it genuinely has to be that big; say why in the commit.
#
# A listed file that drops under its limit has graduated and must leave the list,
# and an entry for a file that no longer exists must go, so the lists stay the
# true backlog.
#
# WHAT THE NUMBERS MEAN. 800 lines is roughly the point past which an agent
# reads a file partially and edits it blind. 25 public functions is the point
# past which "what does this class do" stops having a one-sentence answer.
#
# Two API entries will never graduate: network_manager.gd, because Godot
# dispatches @rpc by name on the node, so its receive_*/send_*/notify_* surface
# IS the wire protocol; and player_attributes.gd, one accessor per body dial.
#
# Scope is Scripts/ only. A long test is not the same cost as a long subsystem,
# and addons/ is vendored. Generated data under _GENERATED_DIR is a measurement
# written as constants, never read or edited by hand, so it is not counted.

const _GENERATED_DIR: String = "res://Scripts/domain/ai/generated/"

const _SIZE_LIMIT: int = 800

const _OVERSIZED: Array[String] = [
	"res://Scripts/actors/hockey_rink.gd",
	"res://Scripts/actors/puck.gd",
	"res://Scripts/actors/skater.gd",
	"res://Scripts/actors/skater_mesh_builder.gd",
	"res://Scripts/ai/skater_agent_state_machine.gd",
	"res://Scripts/controllers/local_controller.gd",
	"res://Scripts/controllers/puck_controller.gd",
	"res://Scripts/controllers/remote_controller.gd",
	"res://Scripts/controllers/skater_controller.gd",
	"res://Scripts/controllers/skater_ik_coordinator.gd",
	"res://Scripts/domain/ai/role_behaviors/carrier.gd",
	"res://Scripts/domain/state/game_state_machine.gd",
	"res://Scripts/game/game_manager.gd",
	"res://Scripts/game/player_prefs.gd",
	"res://Scripts/game/tutorial_manager.gd",
	"res://Scripts/networking/network_manager.gd",
	"res://Scripts/networking/network_telemetry.gd",
	"res://Scripts/ui/career_stats_screen.gd",
	"res://Scripts/ui/hud.gd",
	"res://Scripts/ui/lobby_manager.gd",
	"res://Scripts/ui/network_debug_overlay.gd",
	"res://Scripts/ui/side_menu.gd",
	"res://Scripts/ui/slot_grid_panel.gd",
]

const _API_LIMIT: int = 25

const _WIDE: Array[String] = [
	"res://Scripts/actors/puck.gd",
	"res://Scripts/actors/skater.gd",
	"res://Scripts/controllers/puck_controller.gd",
	"res://Scripts/controllers/skater_controller.gd",
	"res://Scripts/domain/state/game_state_machine.gd",
	"res://Scripts/domain/state/player_attributes.gd",
	"res://Scripts/game/game_manager.gd",
	"res://Scripts/game/shot_on_goal_tracker.gd",
	"res://Scripts/networking/network_manager.gd",
	"res://Scripts/networking/network_telemetry.gd",
]


func _all_files(root: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	for d: String in dir.get_directories():
		out.append_array(_all_files("%s/%s" % [root, d], suffix))
	for f: String in dir.get_files():
		if f.ends_with(suffix):
			out.append("%s/%s" % [root, f])
	return out


# Lines as an editor shows them: a trailing newline does not open a new one.
func _line_count(path: String) -> int:
	var src: String = FileAccess.get_file_as_string(path)
	if src.ends_with("\n"):
		src = src.substr(0, src.length() - 1)
	return src.split("\n").size()


# Functions the file offers to other files: declared at column 0 (an inner
# class's methods are that class's surface, not this one's) and not `_`-prefixed.
func _public_func_count(path: String) -> int:
	var re := RegEx.create_from_string("^(static )?func [a-z][a-zA-Z0-9_]*\\(")
	var n: int = 0
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if re.search(line) != null:
			n += 1
	return n


# The shared guard. `measure` maps a path to its number; everything else is the
# same three rules for both axes.
func _assert_limit(listed: Array[String], limit: int, unit: String,
		measure: Callable, remedy: String) -> void:
	var seen: Dictionary[String, bool] = {}
	for path: String in _all_files("res://Scripts", ".gd"):
		if path.begins_with(_GENERATED_DIR):
			continue
		var measured: int = measure.call(path)
		seen[path] = true
		if not listed.has(path):
			if measured > limit:
				fail_test(("%s is %d %s, over the %d limit. %s — or add it to the " +
						"list in test_no_god_class_growth.gd if it genuinely has to " +
						"be this big, and say why in the commit.")
						% [path, measured, unit, limit, remedy])
		elif measured <= limit:
			fail_test(("%s is down to %d %s, under the %d limit — it graduated. " +
					"Delete its entry from the list.") % [path, measured, unit, limit])
	for path: String in listed:
		if not seen.has(path):
			fail_test("%s no longer exists; drop its stale entry from the list." % path)
	# A guard that scanned nothing passes silently, which is the one way this
	# can rot into decoration. Scripts/ has ~340 .gd files.
	assert_gt(seen.size(), 250, "the %s scan must actually reach Scripts/" % unit)


func test_no_new_file_grows_past_the_size_limit() -> void:
	_assert_limit(_OVERSIZED, _SIZE_LIMIT, "lines", _line_count,
			"Split it, or move the prose to its area CLAUDE.md")


func test_no_new_class_widens_past_the_api_limit() -> void:
	_assert_limit(_WIDE, _API_LIMIT, "public functions", _public_func_count,
			"Split it, or make the callers go through fewer entry points")
