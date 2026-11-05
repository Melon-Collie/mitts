extends GutTest

# The near-miss bobble through the host's real present-time detection
# (PuckController._check_interactions): a puck fired at a standing receiver's
# blade, on its line or a reach off it. A blade on the line holds what a reach
# can't, whichever way the blade points; past the bobble line the puck comes
# back off the face, nobody's.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")

var _pc: PuckController = null
var _puck: Puck = null
var _receiver: Skater = null


func before_each() -> void:
	_puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_receiver = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_receiver)
	_receiver.global_position = Vector3(0.0, 0.0, -8.0)
	_receiver.set_physics_process(false)
	_receiver.set_process(false)
	_receiver.capture_prev_blade_contact()   # a still blade
	_pc = PuckController.new()
	add_child_autofree(_pc)
	_pc.set_physics_process(false)
	_pc.set_process(false)
	_pc.setup(_puck, true)
	_pc.set_team_id_by_skater({_receiver: 0})
	_pc.set_skater_getter(func() -> Array: return [_receiver])
	_pc.set_peer_id_resolver(func(_s: Skater) -> int: return 2)


# The face normal the puck is fired against, pointing back out of the face.
func _face() -> Vector3:
	var axis: Vector3 = PuckReceptionRules.blade_axis(_receiver.get_blade_contact_global(),
			_receiver.top_hand.global_position, Vector3.FORWARD)
	return Vector3(-axis.z, 0.0, axis.x)


# Fires the puck square onto the blade at `speed`, along the face normal, with
# its line `along` metres toward the toe from the blade's middle.
func _fire(speed: float, along: float) -> void:
	var axis: Vector3 = PuckReceptionRules.blade_axis(_receiver.get_blade_contact_global(),
			_receiver.top_hand.global_position, Vector3.FORWARD)
	_fire_along(speed, _face(), axis * along)


# Fires the puck at `speed` travelling against `toward`, its line passing
# `aside` off the blade's middle.
func _fire_along(speed: float, toward: Vector3, aside: Vector3) -> void:
	var mid: Vector3 = _receiver.get_blade_contact_global()
	var line: Vector3 = Vector3(mid.x, _puck.ice_height, mid.z) + aside
	_pc._prev_puck_pos = line + toward * 0.8
	_puck.set_puck_position(line + toward * 0.05)
	_puck.set_puck_velocity(-toward * speed)
	_pc._check_interactions()


func test_a_hard_pass_held_at_the_middle() -> void:
	_fire(20.0, 0.0)
	assert_eq(_puck.carrier, _receiver, "on the line at 20 m/s, the middle holds it")


func test_anywhere_along_the_blade_is_on_the_line() -> void:
	_fire(20.0, 0.14)
	assert_eq(_puck.carrier, _receiver, "a path across the toe still meets the blade")


func test_end_on_through_the_middle_holds() -> void:
	var axis: Vector3 = PuckReceptionRules.blade_axis(_receiver.get_blade_contact_global(),
			_receiver.top_hand.global_position, Vector3.FORWARD)
	_fire_along(20.0, axis, Vector3.ZERO)
	assert_eq(_puck.carrier, _receiver, "the blade's direction doesn't decide the catch")


func test_the_same_pass_reached_for_bobbles_off_the_face() -> void:
	_fire(20.0, 0.45)
	assert_null(_puck.carrier, "reached for at the rim, it bobbles")
	var v: Vector3 = _puck.get_puck_velocity()
	var flat := Vector3(v.x, 0.0, v.z)
	assert_between(flat.length(), 2.0, 3.2, "loose, but nowhere near a tip")
	assert_gt(flat.normalized().dot(_face()), 0.99, "square in, straight back off the face")
	assert_gt(v.y, 0.0, "driven hard into the face, it hops")
	assert_true(_puck.is_on_cooldown(_receiver), "his hands are blown open: he can't play it yet")


func test_harder_still_bobbles_even_at_the_middle() -> void:
	_fire(26.0, 0.0)
	assert_null(_puck.carrier)
	var v: Vector3 = _puck.get_puck_velocity()
	assert_lt(Vector3(v.x, 0.0, v.z).length(), 3.2)


func test_a_soft_pass_holds_anywhere_in_reach() -> void:
	_fire(12.0, 0.45)
	assert_eq(_puck.carrier, _receiver)
