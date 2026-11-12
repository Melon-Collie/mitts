extends GutTest

# A puck the post or the boards knock off the stick leaves through the same
# signal a pass does. The controller says which it was, so the stats can tell a
# fumble from a pass: never a shot attempt, and nothing for an opponent to pick
# off.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const _IK: String = "res://Scripts/controllers/skater_ik_coordinator.gd"
const _CONTROLLER: String = "res://Scripts/controllers/skater_controller.gd"


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _controller: SkaterController = null


func before_each() -> void:
	var puck := PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var skater := SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


func test_a_forced_release_is_no_shot_whatever_was_released_last() -> void:
	_controller.last_release_was_shot = true
	_controller._do_release(Vector3.FORWARD, 3.0, true)
	assert_true(_controller.last_release_was_forced)
	assert_false(_controller.last_release_was_shot)


func test_a_played_release_clears_the_flag() -> void:
	_controller._do_release(Vector3.FORWARD, 3.0, true)
	_controller._do_release(Vector3.FORWARD, 20.0)
	assert_false(_controller.last_release_was_forced)


func test_the_flags_are_set_before_the_release_is_announced() -> void:
	var seen: Array[bool] = []
	_controller.puck_release_requested.connect(
			func(_d: Vector3, _p: float, _s: bool) -> void:
				seen.append(_controller.last_release_was_forced))
	_controller._do_release(Vector3.FORWARD, 3.0, true)
	assert_eq(seen, [true] as Array[bool])


# ── The call sites ───────────────────────────────────────────────────────────

# The argument list of every call to `callee` in the file at `path`.
func _release_calls(path: String, callee: String) -> PackedStringArray:
	var calls := PackedStringArray()
	var src: String = FileAccess.get_file_as_string(path)
	var at: int = src.find(callee)
	while at != -1:
		var open: int = at + callee.length()
		var depth: int = 1
		var end: int = open
		while depth > 0:
			depth += int(src[end] == "(") - int(src[end] == ")")
			end += 1
		calls.append(src.substr(open, end - 1 - open))
		at = src.find(callee, end)
	return calls


func test_every_release_the_blade_pass_makes_is_forced() -> void:
	# The blade pass only ever lets the puck go against the boards.
	var calls: PackedStringArray = _release_calls(_IK, "_controller._do_release(")
	assert_gt(calls.size(), 0)
	for args: String in calls:
		assert_true(args.ends_with(", true"), args)


func test_the_post_knock_loose_is_forced() -> void:
	var forced: int = 0
	for args: String in _release_calls(_CONTROLLER, "\t_do_release("):
		if args.contains("post_catch_release_speed"):
			assert_true(args.ends_with(", true"), args)
			forced += 1
	assert_eq(forced, 1)
