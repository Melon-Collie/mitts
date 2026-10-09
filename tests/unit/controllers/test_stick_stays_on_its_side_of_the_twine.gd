extends GutTest

# The twine is compliant: the blade sinks up to NET_BLADE_MESH_GIVE into it, and
# which face stops it (inside or outside) is decided by which side the stick is
# on. A stick resting in the mesh sits within the give of the plane — on the
# FAR side of it when it pressed through — so classifying from the plane alone
# flips sides the tick after contact, and the stick then walks out of (or into)
# the cage through the side net.
#
# Drives a real Skater + SkaterController: the stick is pressed into each panel
# from each side and held there while the cursor keeps pulling through, and the
# blade must stay within the give of its own side for the whole press.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = 1.0 / 120.0
const G: float = GameRules.GOAL_LINE_Z
const HW: float = GameRules.NET_HALF_WIDTH
const GIVE: float = GameRules.NET_BLADE_MESH_GIVE
# The blade contact is mid-blade while the twine bounds heel and toe — the toe
# from last tick's blade heading, which a turning stick has moved on from — so
# the contact rests a few cm past the give. The faults this pins are tens of cm.
const TOL: float = 0.06


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _c: SkaterController


func before_each() -> void:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_c = SkaterController.new()
	add_child_autofree(_c)
	_c.setup(skater, puck, gs)


func _tick(cursor: Vector3) -> void:
	var sk: Skater = _c.skater
	sk.capture_prev_blade_contact()
	var input := InputState.new()
	input.delta = DT
	input.mouse_world_pos = cursor
	_c._process_input(input, DT)
	sk._physics_process(DT)


# Glide in to `at` facing `facing` with the stick held on `from` (relative to the
# body, so it arrives continuously rather than being placed into the net), then
# drag the cursor to `to` and hold it there. Calls `check` with the blade contact
# on every tick of the drag and the hold; returns the first failure, or "".
func _press(at: Vector3, facing: Vector2, from: Vector3, to: Vector3, check: Callable) -> String:
	var sk: Skater = _c.skater
	var start: Vector3 = at - Vector3(facing.x, 0.0, facing.y) * 3.0
	sk.global_position = start
	sk.velocity = Vector3.ZERO
	sk.set_facing(facing)
	_c._ik.reset_blade_smoothing()
	sk.reseed_blade_history()
	var hold: Vector3 = from - at
	for i: int in 30:
		_tick(start + hold)
	for i: int in 60:
		sk.global_position = start.lerp(at, float(i + 1) / 60.0)
		_tick(sk.global_position + hold)
	for i: int in 20:
		_tick(from)
	for i: int in 120:
		_tick(from.lerp(to, minf(1.0, float(i) / 60.0)))
		var msg: String = check.call(sk.get_blade_contact_global())
		if msg != "":
			return "tick %d: %s" % [i, msg]
	return ""


func _depth(p: Vector3) -> float:
	return absf(p.z) - G


func test_a_stick_in_the_cage_does_not_walk_out_through_the_side() -> void:
	# Dragged hard enough, the stick slides forward along the twine and out of
	# the mouth, and from there round the post is open ice — that is leaving the
	# right way. Only arriving beside the cage WITHOUT having left through the
	# mouth is going through the side net.
	for side: float in [1.0, -1.0]:
		var left_by_mouth: Array[bool] = [false]
		var msg: String = _press(Vector3(0.0, 0.0, G - 1.0), Vector2(0.0, 1.0),
				Vector3(0.3 * side, 0.0, G + 0.35), Vector3(2.2 * side, 0.0, G + 0.45),
				func(b: Vector3) -> String:
					if _depth(b) < 0.0:
						left_by_mouth[0] = true
					if not left_by_mouth[0] and _depth(b) > 0.1 \
							and absf(b.x) > HW + GIVE + TOL:
						return "blade out through the side twine at %s" % b
					return "")
		assert_eq(msg, "", "side %+.0f" % side)


func test_a_stick_beside_the_cage_does_not_walk_in_through_the_side() -> void:
	for side: float in [1.0, -1.0]:
		var msg: String = _press(Vector3(2.0 * side, 0.0, G + 0.5), Vector2(-side, 0.0),
				Vector3(1.4 * side, 0.0, G + 0.5), Vector3(-0.2 * side, 0.0, G + 0.5),
				func(b: Vector3) -> String:
					if _depth(b) > 0.1 and _depth(b) < GameRules.NET_DEPTH - 0.1 \
							and absf(b.x) < HW - GIVE - TOL:
						return "blade in through the side twine at %s" % b
					return "")
		assert_eq(msg, "", "side %+.0f" % side)


func test_a_stick_behind_the_cage_does_not_walk_in_through_the_back() -> void:
	var msg: String = _press(Vector3(0.2, 0.0, G + 2.3), Vector2(0.0, -1.0),
			Vector3(0.2, 0.0, G + 1.6), Vector3(0.1, 0.0, G + 0.3),
			func(b: Vector3) -> String:
				if absf(b.x) < HW - 0.1 and NetGeometry.back_plane_distance(b) < -GIVE - TOL:
					return "blade in through the back twine at %s" % b
				return "")
	assert_eq(msg, "", "behind the net")


func test_a_stick_in_the_cage_does_not_walk_out_through_the_back() -> void:
	var msg: String = _press(Vector3(0.0, 0.0, G - 0.6), Vector2(0.0, 1.0),
			Vector3(0.1, 0.0, G + 0.3), Vector3(0.2, 0.0, G + 2.0),
			func(b: Vector3) -> String:
				if absf(b.x) < HW - 0.1 and NetGeometry.back_plane_distance(b) > GIVE + TOL:
					return "blade out through the back twine at %s" % b
				return "")
	assert_eq(msg, "", "in the cage")
